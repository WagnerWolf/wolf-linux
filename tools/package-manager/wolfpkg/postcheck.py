"""Verificação SOMENTE LEITURA de artefatos de boot e DKMS após operações.

Não executa pacman -S, mkinitcpio, dkms install nem modifica GRUB/EFI.
A ausência de arquivos gerados em /boot não é detectada por pacman -Qkk.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import subprocess


@dataclass(frozen=True)
class PostUpdateReport:
    critical: tuple[str, ...]
    advisory: tuple[str, ...]
    checked: tuple[str, ...]

    @property
    def safe_to_continue(self) -> bool:
        return not self.critical

    def describe(self) -> str:
        lines = ['=== VERIFICAÇÃO PÓS-ATUALIZAÇÃO (somente leitura) ===']
        lines.extend('[OK] ' + x for x in self.checked)
        lines.extend('[AVISO] ' + x for x in self.advisory)
        lines.extend('[ALERTA] ' + x for x in self.critical)
        if self.critical:
            lines.append('RESULTADO: há inconsistências; confira antes de reiniciar. Nenhum reparo automático foi realizado.')
        elif self.advisory:
            lines.append('RESULTADO: sem falha crítica detectada, mas existem ressalvas para verificação manual.')
        else:
            lines.append('RESULTADO: verificações aplicáveis aprovadas (não garantem ausência de falhas).')
        return '\n'.join(lines)


def _kernel_name(name: str) -> bool:
    return name in {'linux', 'linux-lts', 'linux-zen', 'linux-hardened',
                    'linux-rt', 'linux-rt-lts'}


def _read_preset(preset: Path, pkgbase: str) -> tuple[list[str], bool]:
    """Lê literais simples do preset, sem executar código shell nem expandir comandos."""
    try:
        content = preset.read_text(encoding='utf-8')
    except OSError:
        return [], False
    files = []
    for key in ('default_image', 'default_uki'):
        match = re.search(r'^\s*' + key + r'=[\'\"]?([^\'\"\n#]+)', content, re.M)
        if match:
            name = match.group(1).strip().replace('${pkgbase}', pkgbase).replace('$pkgbase', pkgbase)
            if name.startswith('/') and '$' not in name and '`' not in name:
                files.append(name)
    return files, True


def run_post_update_checks(*, root: Path = Path('/'), run=None) -> PostUpdateReport:
    """Inspeciona somente pacotes instalados, /boot e DKMS, com limites de tempo."""
    if run is None:
        def run(argv, timeout):
            return subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                                  stdin=subprocess.DEVNULL, check=False)

    critical: list[str] = []
    advisory: list[str] = []
    checked: list[str] = []

    def execute(argv, timeout=25):
        try:
            return run(argv, timeout)
        except (OSError, subprocess.TimeoutExpired) as exc:
            advisory.append(f'Comando {argv[0]} indisponível ou excedeu o prazo: {exc}')
            return None

    packages_result = execute(['pacman', '-Qq'])
    if packages_result is None or packages_result.returncode:
        critical.append('Não foi possível identificar os pacotes instalados (pacman -Qq).')
        return PostUpdateReport(tuple(critical), tuple(advisory), tuple(checked))
    installed = set(packages_result.stdout.splitlines())
    kernel_packages = {p for p in installed if _kernel_name(p)}
    if not kernel_packages:
        advisory.append('Nenhum kernel conhecido foi encontrado na lista de pacotes; confira manualmente se usar outro tipo de kernel.')

    modules_dir = root / 'usr/lib/modules'
    releases: dict[str, list[str]] = {}
    if modules_dir.is_dir():
        for f in sorted(modules_dir.glob('*/pkgbase')):
            try:
                name = f.read_text(encoding='utf-8').strip()
                if name in kernel_packages:
                    releases.setdefault(name, []).append(f.parent.name)
            except OSError:
                advisory.append(f'Não foi possível ler {f}.')

    has_mkinitcpio = 'mkinitcpio' in installed
    for name in sorted(kernel_packages):
        versions = releases.get(name, [])
        if not versions:
            critical.append(f'{name}: instalado no Pacman, mas sem diretório de módulos/pkgbase correspondente.')
            continue
        if len(versions) != 1:
            advisory.append(f'{name}: múltiplos diretórios de módulos encontrados: {", ".join(versions)}.')
        for release in versions:
            if not (modules_dir/release/'vmlinuz').is_file():
                critical.append(f'{name} ({release}): vmlinuz ausente em /usr/lib/modules.')
        if has_mkinitcpio:
            vmlinuz = root / 'boot' / ('vmlinuz-' + name)
            if not vmlinuz.is_file():
                critical.append(f'{name}: kernel ausente de /boot/vmlinuz-{name}.')
            else:
                checked.append(f'{name}: kernel presente em /boot.')
            preset = root / 'etc/mkinitcpio.d' / f'{name}.preset'
            if not preset.is_file():
                critical.append(f'{name}: preset mkinitcpio ausente ({preset}).')
                continue
            images, readable = _read_preset(preset, name)
            if not readable or not images:
                advisory.append(f'{name}: não foi possível interpretar o destino do initramfs/UKI; confira o preset manualmente.')
                continue
            for image in images:
                f = root / image.lstrip('/')
                if not f.is_file() or f.stat().st_size == 0:
                    critical.append(f'{name}: imagem de inicialização ausente/vazia em {image}.')
                else:
                    checked.append(f'{name}: imagem de inicialização presente em {image}.')
        else:
            advisory.append(f'{name}: mkinitcpio não instalado; destino de imagem de boot não verificado (pode usar dracut/UKI).')

    if {'nvidia-dkms', 'nvidia-open-dkms'} & installed and kernel_packages:
        status = execute(['dkms', 'status'], 45)
        if status is None or status.returncode:
            critical.append('NVIDIA DKMS instalada, mas não foi possível consultar dkms status.')
        else:
            for name in sorted(kernel_packages):
                for release in releases.get(name, []):
                    # DKMS pode reportar "installed (original_module exists)"; testar estado.
                    found = re.search(r'^nvidia/[^,]+,\s*' + re.escape(release) +
                                      r',\s*[^:]+:\s*installed\b', status.stdout, re.M)
                    if not found:
                        critical.append(f'{name} ({release}): NVIDIA DKMS não aparece como installed.')
                    else:
                        checked.append(f'{name} ({release}): NVIDIA DKMS instalada.')
    elif not ({'nvidia-dkms', 'nvidia-open-dkms'} & installed):
        checked.append('Pacote NVIDIA DKMS não instalado: verificação específica não aplicável.')

    # Não reparar banco, não assumir que pacman -Dk cobre kernels/initramfs.
    db = execute(['pacman', '-Dk'], 30)
    if db is None or db.returncode:
        advisory.append('pacman -Dk não confirmou a consistência do banco de pacotes; examine o resultado manualmente.')
    else:
        checked.append('pacman -Dk: banco de pacotes consistente.')
    return PostUpdateReport(tuple(critical), tuple(advisory), tuple(checked))
