#!/usr/bin/env python3
"""Contrato de PREVIEW (read-only) Wolf GUI <-> instalador Bash.

Nenhuma operação de montagem, formatação, particionamento ou instalação aqui.
O documento JSON não autoriza operações; somente o executor VM separado pode
consumi-lo após preflight independente e dupla confirmação explícita.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

SCHEMA = "wolf.install.preview.v4"
VM_MIN_BYTES = 32 * 1024**3
STACKS = ("daily", "gaming", "development", "android", "containers", "extras")
PRESETS = {
    "minimal": (),
    "test": ("daily", "gaming", "development", "extras"),
    "full": STACKS,
}
STORAGE_MODES = ("erase", "reuse", "manual")
PATH_RE = re.compile(r"^/dev/[a-zA-Z0-9._/+\-]+$")


class PlanError(ValueError):
    pass

ALLOWED_KEYBOARDS = frozenset({
    ('br', 'abnt2', ''), ('br', 'abnt2', 'thinkpad'),
    ('us', 'pc105', ''), ('pt', 'pc105', ''), ('es', 'pc105', ''),
    ('fr', 'pc105', ''), ('de', 'pc105', ''), ('it', 'pc105', ''),
})

def require_supported_keyboard(keyboard: dict) -> None:
    if (keyboard.get('layout'), keyboard.get('model'), keyboard.get('variant')) not in ALLOWED_KEYBOARDS:
        raise PlanError('Teclado não suportado pelo instalador; escolha um layout disponível no seletor.')



def inventory(raw: str | None = None) -> list[dict]:
    """Consulta lsblk sem alterar dispositivos. Não segue caminhos arbitrários."""
    if raw is None:
        try:
            proc = subprocess.run(
                ["lsblk", "--json", "-b", "-o", "NAME,PATH,TYPE,SIZE,MODEL,TRAN,RM,MAJ:MIN,FSTYPE,PARTTYPE,MOUNTPOINTS"],
                capture_output=True, text=True, check=False, timeout=8,
            )
        except (OSError, subprocess.TimeoutExpired):
            return []
        if proc.returncode:
            return []
        raw = proc.stdout
    try:
        data = json.loads(raw)
    except (TypeError, ValueError):
        return []
    devices = data.get("blockdevices", []) if isinstance(data, dict) else []
    if not isinstance(devices, list):
        return []
    out = []
    for d in devices:
        if not isinstance(d, dict) or d.get("type") != "disk":
            continue
        path = d.get("path")
        if not isinstance(path, str) or not PATH_RE.fullmatch(path):
            continue
        try:
            size = int(d.get("size") or 0)
        except (ValueError, TypeError):
            continue
        if size <= 0:
            continue
        parts = []
        for c in d.get("children") or []:
            if not isinstance(c, dict) or c.get("type") != "part":
                continue
            cp = c.get("path")
            if not isinstance(cp, str) or not PATH_RE.fullmatch(cp):
                continue
            try:
                cs = int(c.get("size") or 0)
            except (TypeError, ValueError):
                continue
            parts.append({"path": cp, "size": cs,
                          "fstype": str(c.get("fstype") or ""),
                          "mountpoints": c.get("mountpoints") or [], "maj_min": str(c.get("maj:min") or ""),
                          "parttype": str(c.get("parttype") or "").lower()})
        out.append({"path": path, "size": size,
                    "maj_min": str(d.get("maj:min") or ""),
                    "model": str(d.get("model") or "").strip(),
                    "transport": str(d.get("tran") or ""),
                    "removable": str(d.get("rm") or "").lower() in ("1", "true", "yes"),
                    "mountpoints": d.get("mountpoints") or [], "partitions": parts})
    return out


def _valid_ident(hostname: str, username: str) -> None:
    if not isinstance(username, str) or not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", username):
        raise PlanError("Usuário inválido")
    if not isinstance(hostname, str) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]{0,62}", hostname) or hostname.endswith("-"):
        raise PlanError("Hostname inválido")




def erase_usable_gib(disk_bytes: int, boot_mode: str) -> int:
    """Limite conservador do particionador: EFI 1 GiB e 1 GiB para alinhamento/folga.

    A GUI e o validador usam esta MESMA regra. Apenas leitura/cálculo;
    não substitui o preflight do Bash antes de escrever no disco.
    """
    if type(disk_bytes) is not int or disk_bytes <= 0:
        return 0
    if boot_mode not in ("UEFI", "BIOS"):
        return 0
    reserved = 1 + (1 if boot_mode == "UEFI" else 0)
    return max(0, min(16384, disk_bytes // 1024**3 - reserved))


def erase_size_bounds(disk_bytes: int, boot_mode: str, home_layout: str,
                      root_gib: int, home_gib: int) -> dict[str, int]:
    """Limites para barra+campo. Zero significa *restante* (não zero GiB)."""
    usable = erase_usable_gib(disk_bytes, boot_mode)
    if home_layout == "in-root":
        return {"usable": usable, "root_min": 0, "root_max": usable,
                "home_min": 0, "home_max": 0}
    if home_layout != "separate":
        raise PlanError("Layout de home inválido")
    # /home fixa precisa ter ao menos 10 GiB; /home=0 reserva esse mínimo
    # por significar 'restante do disco'. A raiz exige pelo menos 20 GiB.
    home_reserved = home_gib if home_gib >= 10 else 10
    return {"usable": usable, "root_min": 20,
            "root_max": max(0, usable - home_reserved),
            "home_min": 0, "home_max": max(0, usable - max(20, root_gib))}


def build_preview(*, disks: list[dict], disk_path: str, mode: str,
                  preset: str, stacks: tuple[str, ...], hostname: str, username: str,
                  keyboard: dict, boot_mode: str, roles: dict | None = None,
                  formats: dict | None = None, home_layout: str = "in-root",
                  cleanup_home: bool = False, erase_sizes: dict | None = None) -> dict:
    _valid_ident(hostname, username)
    if mode not in STORAGE_MODES:
        raise PlanError("Estratégia de armazenamento inválida")
    if preset not in (*PRESETS, "custom"):
        raise PlanError("Preset inválido")
    if not isinstance(stacks, (tuple, list)) or len(set(stacks)) != len(stacks) or any(s not in STACKS for s in stacks):
        raise PlanError("Stacks inválidas ou repetidas")
    if preset in PRESETS and tuple(stacks) != PRESETS[preset]:
        raise PlanError("Stacks não correspondem ao preset solicitado")
    if boot_mode not in ("UEFI", "BIOS", "unknown"):
        raise PlanError("Modo de boot inválido")
    if not isinstance(keyboard, dict) or set(keyboard) != {"layout", "model", "variant"}:
        raise PlanError("Layout de teclado inválido")
    if not all(isinstance(keyboard[k], str) and re.fullmatch(r"[a-z0-9]{0,16}", keyboard[k]) for k in keyboard):
        raise PlanError("Identificador de teclado inválido")
    disk = next((d for d in disks if d["path"] == disk_path), None)
    if disk_path and disk is None:
        raise PlanError("Disco escolhido não existe no inventário")
    roles = {"root": None, "esp": None, "home": None} if roles is None else roles
    formats = {"root": False, "esp": False, "home": False} if formats is None else formats
    if home_layout not in ("in-root", "separate"):
        raise PlanError("Modo de /home inválido")
    if type(cleanup_home) is not bool:
        raise PlanError("Limpeza de /home deve ser booleano explícito")
    if cleanup_home and (mode != "reuse" or home_layout != "separate"):
        raise PlanError("Limpeza de dotfiles permitida somente em /home separada, preservada, em Reutilizar")
    erase_sizes = {"root_gib": 0, "home_gib": 0} if erase_sizes is None else erase_sizes
    if not isinstance(erase_sizes, dict) or set(erase_sizes) != {"root_gib", "home_gib"}:
        raise PlanError("Tamanhos de partições inválidos")
    if any(type(v) is not int or v < 0 or v > 16384 for v in erase_sizes.values()):
        raise PlanError("Tamanhos devem ser números inteiros em GiB")
    if mode != "erase" and any(erase_sizes.values()):
        raise PlanError("Tamanhos automáticos só são válidos em Apagar disco")
    if mode == "erase":
        root_gib, home_gib = erase_sizes["root_gib"], erase_sizes["home_gib"]
        if home_layout == "in-root" and home_gib:
            raise PlanError("Não há partição /home dedicada no modo /home integrado")
        if home_layout == "in-root" and root_gib and root_gib < 20:
            raise PlanError("Raiz de tamanho fixo exige pelo menos 20 GiB; selecione 0 para usar o restante")
        if home_layout == "separate" and root_gib < 20:
            raise PlanError("/home separada exige tamanho da raiz / de pelo menos 20 GiB")
        if home_layout == "separate" and home_gib and home_gib < 10:
            raise PlanError("/home separada exige ao menos 10 GiB quando tamanho for definido")
        if disk:
            # Reserva 1 GiB de ESP no UEFI, folga para alinhamento/GPT,
            # e mínimo de 10 GiB para a partição /home quando usa o restante.
            usable = erase_usable_gib(disk["size"], boot_mode)
            if home_layout == "separate" and usable < 30:
                raise PlanError("Disco insuficiente: raiz mínima 20 GiB e /home mínima 10 GiB, além da reserva")
            if home_layout == "in-root" and usable < 20:
                raise PlanError("Disco insuficiente para instalação automática (mínimo 20 GiB disponíveis)")
            if home_layout == "separate" and root_gib + (home_gib or 10) > usable:
                raise PlanError("Disco insuficiente para raiz, /home e espaço de alinhamento")
            if home_layout == "in-root" and root_gib and root_gib > usable:
                raise PlanError("Raiz maior que a capacidade disponível do disco")
            if home_layout == "separate" and home_gib and root_gib + home_gib > usable:
                raise PlanError("Tamanhos de / e /home excedem o disco")
    if home_layout == "in-root" and (roles.get("home") is not None or formats.get("home")):
        raise PlanError("/home dentro da raiz não admite partição ou formatação própria")
    if not isinstance(roles, dict) or set(roles) != {"root", "esp", "home"}:
        raise PlanError("Papéis das partições inválidos")
    if not isinstance(formats, dict) or set(formats) != {"root", "esp", "home"} or not all(type(v) is bool for v in formats.values()):
        raise PlanError("Preferências de formatação inválidas")
    if mode == "erase" and (any(roles.values()) or any(formats.values())):
        raise PlanError("Apagar disco inteiro não admite partições ou flags individuais")
    if cleanup_home and (not roles.get("home") or formats.get("home")):
        raise PlanError("Limpeza exige partição /home selecionada e SEM formatação")
    if mode in ("reuse", "manual"):
        allowed = {p["path"] for p in (disk or {}).get("partitions", [])}
        if any(value is not None and (not isinstance(value, str) or value not in allowed) for value in roles.values()):
            raise PlanError("Partição não pertence ao disco selecionado")
        selected = [p for p in roles.values() if p is not None]
        if len(selected) != len(set(selected)):
            raise PlanError("Uma mesma partição não pode ter vários papéis")
        if any(formats[k] and not roles[k] for k in formats):
            raise PlanError("Formatação solicitada sem partição selecionada")
    warnings = []
    if cleanup_home:
        warnings.append("LIMPEZA DE CONFIGURAÇÕES: arquivos e pastas ocultos diretamente dentro de CADA usuário da /home preservada serão REMOVIDOS, incluindo possíveis chaves .ssh/.gnupg. Arquivos visíveis permanecem. Exige confirmação LIMPAR antes de formatar /.")
    if mode == "reuse" and not formats["root"]:
        warnings.append("BLOQUEIO: o Bash atual SEMPRE formata a raiz / em ext4 na reutilização; não existe opção de preservá-la")
    if mode in ("reuse", "manual") and formats["root"]:
        warnings.append("PERDA DE DADOS: formatar a raiz / apagará todo o conteúdo atual da partição raiz")
    if mode in ("reuse", "manual") and formats["home"]:
        warnings.append("PERDA DE DADOS: formatar /home apagará os arquivos pessoais da partição dedicada")
    if mode in ("reuse", "manual") and formats["esp"]:
        warnings.append("RISCO DE BOOT: formatar EFI apagará carregadores de inicialização existentes")
    if home_layout == "separate" and not roles["home"] and mode in ("reuse", "manual"):
        warnings.append("/home separado selecionado, mas nenhuma partição /home foi escolhida")
    if mode == "erase" and home_layout == "separate":
        warnings.append("APAGAR DISCO: criar partição /home ext4 SEPARADA; ambos / e /home perdem todos os dados anteriores")
    if home_layout == "in-root":
        warnings.append("/home será um DIRETÓRIO dentro de /; não haverá montagem específica de /home")
        if mode == "erase" or (mode == "reuse" and formats["root"]):
            warnings.append("ATENÇÃO: formatar/apagar a raiz também elimina qualquer /home antigo armazenado nela")
    if mode == "manual":
        warnings.append("Manual: em UEFI/GPT, selecione EFI FAT32 ou marque para formatar; em BIOS/MBR NÃO há EFI (GRUB é instalado no disco). BIOS/GPT com bios_grub fica bloqueado neste modo.")
        for role, label in (("esp", "EFI"), ("home", "/home")):
            chosen = roles.get(role)
            if chosen and formats[role]:
                part = next((q for d in disks for q in d["partitions"] if q["path"] == chosen), None)
                if part and part.get("fstype"):
                    warnings.append(f"ALERTA: {label} ({chosen}) tem filesystem {part['fstype']} detectado e será FORMATADA. Se quiser preservar os dados, escolha Reutilizar partições.")
    if disk is None:
        warnings.append("Selecione um disco antes de revisar o plano")
    if mode == "erase":
        warnings.append("APAGAR DISCO INTEIRO: todas as partições serão excluídas; EFI automática de 1 GiB em UEFI e NENHUMA EFI em BIOS")
        if erase_sizes["root_gib"]:
            warnings.append(f"Partição raiz /: {erase_sizes['root_gib']} GiB")
        else:
            warnings.append("Partição raiz /: restante do disco")
        if home_layout == "separate":
            warnings.append(f"Partição /home: {erase_sizes['home_gib']} GiB" if erase_sizes["home_gib"] else "Partição /home: restante do disco")
        if disk and erase_sizes["root_gib"] and (home_layout == "in-root" or erase_sizes["home_gib"]):
            warnings.append("ESPAÇO NÃO PARTICIONADO: o restante do disco ficará livre, pois foram definidos tamanhos fixos para as partições")
        if disk and disk["removable"]:
            warnings.append("ATENÇÃO: disco marcado como removível (pode ser a mídia Live)")
    if mode in ("reuse", "manual"):
        if not roles["root"]:
            warnings.append("Partição raiz / ainda não selecionada")
        if boot_mode == "UEFI" and not roles["esp"]:
            warnings.append("UEFI detectado: selecione a partição EFI antes de uma instalação futura")
        if any(formats.values()):
            warnings.append("A execução exige pré-validação independente e confirmação dupla")
    warnings.append("O JSON não autoriza execução: somente executor independente, com nova verificação e confirmação explícita")
    return {
        "schema": SCHEMA,
        "execution": "disabled",
        "boot_mode": boot_mode,
        "keyboard": keyboard,
        "identity": {"hostname": hostname, "username": username},
        "software": {"preset": preset, "stacks": list(stacks)},
        "storage": {
            "mode": mode,
            "home_layout": home_layout,
            "disk": ({k: disk[k] for k in ("path", "size", "maj_min", "model", "transport", "removable")} if disk else None),
            "partitions": roles,
            "format": formats,
            "cleanup_home": cleanup_home,
            "erase_sizes": erase_sizes,
        },
        "warnings": warnings,
    }


def validate_document(doc: dict, *, disks: list[dict]) -> dict:
    if not isinstance(doc, dict):
        raise PlanError("Documento deve ser um objeto JSON")
    if set(doc) != {"schema", "execution", "boot_mode", "keyboard", "identity", "software", "storage", "warnings"}:
        raise PlanError("Campos desconhecidos ou ausentes no documento")
    if doc["schema"] != SCHEMA or doc["execution"] != "disabled":
        raise PlanError("Versão ou permissão de execução inválida")
    ident, software, storage = doc["identity"], doc["software"], doc["storage"]
    if not all(isinstance(x, dict) for x in (ident, software, storage)):
        raise PlanError("Seções malformadas")
    if set(ident) != {"hostname", "username"} or set(software) != {"preset", "stacks"} or set(storage) != {"mode", "home_layout", "disk", "partitions", "format", "cleanup_home", "erase_sizes"}:
        raise PlanError("Campos de identidade/software/armazenamento inconsistentes")
    if not isinstance(doc["warnings"], list) or any(not isinstance(x, str) for x in doc["warnings"]):
        raise PlanError("Lista de avisos inválida")
    chosen = storage["disk"]
    if chosen is not None and (not isinstance(chosen, dict) or set(chosen) != {"path", "size", "maj_min", "model", "transport", "removable"}):
        raise PlanError("Identidade de disco inválida")
    canonical = build_preview(disks=disks, disk_path=chosen["path"] if chosen else "",
                              mode=storage["mode"], preset=software["preset"],
                              stacks=tuple(software["stacks"]), hostname=ident["hostname"],
                              username=ident["username"], keyboard=doc["keyboard"],
                              boot_mode=doc["boot_mode"], roles=storage["partitions"], formats=storage["format"],
                              home_layout=storage["home_layout"], cleanup_home=storage["cleanup_home"],
                              erase_sizes=storage["erase_sizes"])
    if canonical != doc:
        raise PlanError("Documento diferente do plano canônico/inventário atual; atualize a lista de discos")
    return canonical


def text_summary(doc: dict) -> str:
    st, sw, ident = doc["storage"], doc["software"], doc["identity"]
    disk = st["disk"]
    lines = ["WOLF LINUX — REVISÃO DO PLANO (SOMENTE LEITURA)",
             f"Schema: {doc['schema']}", "JSON: não concede permissão de execução",
             f"Boot: {doc['boot_mode']}",
             f"Teclado: {doc['keyboard']['layout']} ({doc['keyboard']['variant'] or 'padrão'})",
             f"Disco: {disk['path'] if disk else 'não selecionado'}" + (f"  {disk['size'] / 2**30:.1f} GiB" if disk else ""),
             f"Estratégia: {st['mode']}",
             f"/home: {'diretório dentro de /' if st['home_layout'] == 'in-root' else 'partição separada'}",
             f"Usuário/host: {ident['username']} / {ident['hostname']}",
             f"Perfil: {sw['preset']}",
             "Stacks selecionadas:"]
    lines.extend("  - " + stack for stack in sw["stacks"])
    if not sw["stacks"]:
        lines.append("  - nenhuma (minimal)")
    if st["mode"] == "erase":
        sizes = st["erase_sizes"]
        lines.append("/ (ext4): " + (f"{sizes['root_gib']} GiB" if sizes['root_gib'] else "restante do disco"))
        if st["home_layout"] == "separate":
            lines.append("/home (ext4 separada): " + (f"{sizes['home_gib']} GiB" if sizes['home_gib'] else "restante do disco"))
        lines.append("EFI: 1 GiB FAT32 (UEFI)" if doc["boot_mode"] == "UEFI" else "BIOS: NÃO necessita EFI")
    if st["mode"] in ("reuse", "manual"):
        for role in ("root", "esp", "home"):
            if role == "home" and st["home_layout"] == "in-root":
                continue
            lines.append(f"{role}: {st['partitions'][role] or '(não selecionado)'} " +
                         ("[FORMATAR na execução confirmada]" if st["format"][role] else "[preservar/não formatar]"))
    if st["mode"] == "reuse":
        lines.append("Limpeza dos ocultos de usuários: " + ("SIM, COM CONFIRMAÇÃO PRÓPRIA" if st["cleanup_home"] else "NÃO"))
    lines.append("\nAVISOS:")
    lines.extend("- " + item for item in doc["warnings"])
    return "\n".join(lines)





# Apenas dispositivos de disco reais, não caminhos arbitrários nem links /dev/disk/by-*.
# Discos USB/removíveis continuam protegidos para não apagar a própria mídia Live.
DISK_PATH_RE = re.compile(r"/dev/(?:vd[a-z]+|sd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)")

def require_install_disk_path(path: str) -> None:
    if not isinstance(path, str) or not DISK_PATH_RE.fullmatch(path):
        raise PlanError("Disco de destino não suportado; escolha um disco real SATA, NVMe, eMMC ou VirtIO")


def vm_erase_fields(doc: dict, *, disks: list[dict], active_boot: str | None = None,
                    check_device: bool = False) -> tuple[str, ...]:
    """Confere ALVO de instalação; não atribui autorização de escrita ao JSON.

    Aceita discos SATA/NVMe/eMMC/VirtIO não removíveis, conferidos via lsblk e kernel.
    O bash verifica também que estamos realmente em QEMU/KVM.
    """
    canonical = validate_document(doc, disks=disks)
    st = canonical["storage"]
    if st["mode"] != "erase":
        raise PlanError("Execução de apagar disco exige estratégia erase")
    if any(st["partitions"].values()) or any(st["format"].values()):
        raise PlanError("Papéis/formatações individuais não são permitidos no modo apagar disco")
    disk_info = st["disk"]
    if not disk_info:
        raise PlanError("Selecione o disco de destino")
    disk_path = disk_info["path"]
    require_install_disk_path(disk_path)
    actual = next((d for d in disks if d["path"] == disk_path), None)
    if actual is None or actual["removable"] or actual["transport"].lower() == "usb":
        raise PlanError("Disco inválido, removível ou USB")
    if any(actual.get("mountpoints") or []) or any(p.get("mountpoints") for p in actual["partitions"]):
        raise PlanError("Disco ou partição encontra-se montado; desmonte antes de APAGAR")
    if actual["size"] < VM_MIN_BYTES:
        raise PlanError("O disco deve ter pelo menos 32 GiB")
    if not re.fullmatch(r"[0-9]+:[0-9]+", actual["maj_min"]):
        raise PlanError("Identidade MAJ:MIN do disco indisponível")
    if canonical["boot_mode"] not in ("UEFI", "BIOS"):
        raise PlanError("Modo BIOS/UEFI desconhecido")
    if active_boot is not None and canonical["boot_mode"] != active_boot:
        raise PlanError("Modo BIOS/UEFI do plano não coincide com a sessão Live")
    keyboard = canonical["keyboard"]
    require_supported_keyboard(keyboard)
    if check_device:
        target = Path(disk_path)
        if target.is_symlink() or not target.exists() or not stat.S_ISBLK(target.stat().st_mode):
            raise PlanError("Dispositivo real não é um bloco válido (ou é um symlink)")
        st_device = target.stat()
        if f"{os.major(st_device.st_rdev)}:{os.minor(st_device.st_rdev)}" != actual["maj_min"]:
            raise PlanError("Identidade kernel do disco não coincide com MAJ:MIN do plano")
        # Descartar discos com montagens de qualquer descendente ou camadas
        # gerenciadas (LVM/RAID/LUKS). Evita afetar PVs que se estendem a
        # outros discos, ou a própria sessão Live.
        hierarchy = subprocess.run(['lsblk', '-nr', '-o', 'TYPE,MOUNTPOINTS', disk_path],
                                   capture_output=True, text=True, timeout=8, check=False)
        if hierarchy.returncode:
            raise PlanError('Não foi possível verificar montagens e camadas do disco.')
        for line in hierarchy.stdout.splitlines():
            fields = line.split(maxsplit=1)
            if not fields:
                continue
            if fields[0] in ('lvm', 'crypt', 'raid0', 'raid1', 'raid5', 'raid6', 'raid10', 'md'):
                raise PlanError('Apagar disco com volumes LVM/RAID/LUKS associados exige tratamento especializado.')
            if len(fields) > 1 and fields[1].strip():
                raise PlanError('Disco de destino contém um volume montado.')
        # util-linux wipefs: --noheadings (sem hífen interno), ou -i.
        # --no-headings não existe e fazia todo disco limpo ser recusado.
        try:
            sig = subprocess.run(
                ["wipefs", "--no-act", "--noheadings", "--output", "TYPE", disk_path],
                capture_output=True, text=True, timeout=8, check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise PlanError(f"Falha técnica ao inspecionar assinaturas de {disk_path}: {exc}") from exc
        if sig.returncode != 0:
            detail = (sig.stderr or sig.stdout).strip()[:350] or "sem detalhes"
            raise PlanError(f"wipefs não conseguiu verificar {disk_path} (código {sig.returncode}): {detail}")
        # APAGAR DISCO significa remover a tabela preexistente (GPT/MBR) e as
        # partições. Assinaturas são esperadas e NÃO são motivo para rejeição.
        # wipefs aqui apenas confirma que foi possível inspecionar o dispositivo.
        for source in [disk_path, *(p["path"] for p in actual["partitions"])]:
            if subprocess.run(["findmnt", "--source", source], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, check=False).returncode == 0:
                raise PlanError(f"Dispositivo montado / em uso: {source}")
        swap = subprocess.run(["swapon", "--show=NAME", "--noheadings"],
                              capture_output=True, text=True, check=False)
        if swap.returncode != 0:
            raise PlanError("Não foi possível verificar partições swap ativas")
        if any(path in set(swap.stdout.split()) for path in [disk_path, *(p["path"] for p in actual["partitions"])]):
            raise PlanError("Dispositivo de destino contém swap ativa")
    return (disk_path, str(actual["size"]), actual["maj_min"], canonical["boot_mode"],
            canonical["identity"]["hostname"], canonical["identity"]["username"],
            canonical["software"]["preset"], ",".join(canonical["software"]["stacks"]),
            keyboard["layout"], keyboard["variant"])



def vm_manual_fields(doc: dict, *, disks: list[dict], active_boot: str | None = None,
                     check_device: bool = False) -> tuple[str, ...]:
    """Manual UEFI/GPT ou BIOS/MBR: formatar raiz; ESP apenas no UEFI.

    Atribuir o papel EFI ajusta o tipo GPT para ESP na execução, quando necessário.
    Ainda não suporta BIOS/GPT, LVM ou partições de discos diferentes.
    """
    canonical = validate_document(doc, disks=disks)
    storage = canonical["storage"]
    if storage["mode"] != "manual":
        raise PlanError("Esta operação exige o modo Avançado/manual")
    if canonical["boot_mode"] not in ("UEFI", "BIOS") or (active_boot and active_boot != canonical["boot_mode"]):
        raise PlanError("Firmware atual diferente do plano UEFI/BIOS")
    disk = storage["disk"]
    if not disk:
        raise PlanError("Selecione o disco que contém as partições")
    require_install_disk_path(disk["path"])
    actual = next((d for d in disks if d["path"] == disk["path"]), None)
    if not actual or actual["removable"] or actual["transport"].lower() == "usb":
        raise PlanError("Disco ausente/removível/USB")
    if actual["size"] < VM_MIN_BYTES or not re.fullmatch(r"[0-9]+:[0-9]+", actual["maj_min"]):
        raise PlanError("Disco pequeno demais ou identidade do kernel desconhecida")
    root, esp, home = (storage["partitions"][k] for k in ("root", "esp", "home"))
    fmt = storage["format"]
    if not root or not fmt["root"]:
        raise PlanError("Particionamento manual exige partição raiz / com formatação ext4")
    if canonical["boot_mode"] == "UEFI" and not esp:
        raise PlanError("UEFI exige uma partição EFI selecionada")
    if canonical["boot_mode"] == "BIOS" and (esp or fmt["esp"]):
        raise PlanError("BIOS/Legacy NÃO usa partição EFI; deixe o campo EFI vazio")
    if fmt["home"] and storage["home_layout"] != "separate":
        raise PlanError("Não é possível formatar /home separadamente quando ela fica dentro de /")
    if storage["home_layout"] == "separate" and not home:
        raise PlanError("Escolha uma partição /home ou use /home dentro de /")
    part_by_path = {p["path"]: p for p in actual["partitions"]}
    if root not in part_by_path or (esp and esp not in part_by_path) or (home and home not in part_by_path):
        raise PlanError("Partição selecionada não existe mais no disco")
    root_part = part_by_path[root]
    esp_part = part_by_path[esp] if esp else None
    for selected in (root, esp, home):
        if selected and part_by_path[selected]['fstype'].lower() in ('lvm2_member', 'linux_raid_member', 'crypto_luks'):
            raise PlanError('Partições pertencentes a LVM, RAID ou LUKS não podem ser sobrescritas por este modo.')
    if root_part["size"] < 20 * 1024**3:
        raise PlanError("A raiz / precisa de pelo menos 20 GiB no piloto manual")
    # A raiz será formatada em ext4: seu formato anterior não é restrição.
    if esp_part and esp_part["size"] < 512 * 1024**2:
        raise PlanError("Partição EFI deve ter ao menos 512 MiB")
    if esp_part and not fmt["esp"] and esp_part["fstype"].lower() not in ("vfat", "fat32", "fat"):
        raise PlanError("Para preservar a EFI, ela precisa conter FAT32; marque FORMATAR EFI para inicializá-la")
    if home and not fmt["home"] and part_by_path[home]["fstype"].lower() != "ext4":
        raise PlanError("Para preservar /home, ela precisa ser ext4; marque FORMATAR /home para inicializá-la")
    # A seleção do papel EFI é suficiente: o backend ajustará o tipo GPT
    # para ESP, independentemente da flag configurada pelo GParted.
    if check_device:
        pt = subprocess.run(["lsblk", "-dnro", "PTTYPE", disk["path"]],
                            capture_output=True, text=True, timeout=8, check=False)
        expected_table = "gpt" if canonical["boot_mode"] == "UEFI" else "dos"
        if pt.returncode or pt.stdout.strip().lower() != expected_table:
            if canonical["boot_mode"] == "BIOS":
                raise PlanError("BIOS manual neste modo exige tabela MBR/DOS. GPT exige bios_grub e ainda NÃO é suportado")
            raise PlanError("Modo manual UEFI requer tabela GPT no disco. Crie GPT no GParted")
    for part_path in (root, esp, home):
        if part_path and part_by_path[part_path].get("mountpoints"):
            raise PlanError(f"Partição está montada: {part_path}")
    if check_device:
        for path, majmin in [(disk["path"], actual["maj_min"]),
                             *((part, part_by_path[part]["maj_min"]) for part in (root, esp, home) if part)]:
            device = Path(path)
            if device.is_symlink() or not device.exists() or not stat.S_ISBLK(device.stat().st_mode):
                raise PlanError(f"Dispositivo de bloco inválido: {path}")
            rdev = device.stat().st_rdev
            if not re.fullmatch(r"[0-9]+:[0-9]+", majmin) or f"{os.major(rdev)}:{os.minor(rdev)}" != majmin:
                raise PlanError(f"Identidade da partição mudou: {path}")
            if subprocess.run(["findmnt", "--source", path], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, check=False).returncode == 0:
                raise PlanError(f"Dispositivo está em uso: {path}")
        swap = subprocess.run(["swapon", "--show=NAME", "--noheadings"],
                              capture_output=True, text=True, check=False)
        if swap.returncode or any(x in set(swap.stdout.split()) for x in (root, esp, home) if x):
            raise PlanError("Partição selecionada com swap ativa ou impossibilidade de verificar")
    kb = canonical["keyboard"]
    require_supported_keyboard(kb)
    return (disk["path"], str(actual["size"]), actual["maj_min"], canonical["boot_mode"],
            canonical["identity"]["hostname"], canonical["identity"]["username"],
            canonical["software"]["preset"], ",".join(canonical["software"]["stacks"]),
            kb["layout"], kb["variant"], "manual", root, esp or "", home or "",
            "yes" if fmt["esp"] else "no", "yes" if fmt["home"] else "no")


def vm_reuse_fields(doc: dict, *, disks: list[dict], active_boot: str | None = None,
                    check_device: bool = False) -> tuple[str, ...]:
    """Reutilização UEFI/GPT ou BIOS/MBR: raiz nova, home preservada."""
    canonical = validate_document(doc, disks=disks)
    st = canonical["storage"]
    fmt = st["format"]
    if st["mode"] != "reuse" or st["home_layout"] != "separate":
        raise PlanError("Reutilização exige /home em partição dedicada")
    if not fmt["root"] or fmt["esp"] or fmt["home"]:
        raise PlanError("Reutilização FORMATA apenas raiz /; EFI e /home devem ser preservadas")
    needed = ("root", "esp", "home") if canonical["boot_mode"] == "UEFI" else ("root", "home")
    if not all(st["partitions"].get(key) for key in needed):
        raise PlanError("Reutilização exige raiz /, /home separada e EFI apenas em UEFI")
    if canonical["boot_mode"] == "BIOS" and st["partitions"].get("esp"):
        raise PlanError("Reutilizar em BIOS não aceita EFI")
    # Os mesmos guardrails de identidade, GPT, filesystem, firmware e mounts
    # do piloto manual são aplicados a um espelho canônico do plano.
    manual = build_preview(
        disks=disks, disk_path=st["disk"]["path"] if st["disk"] else "",
        mode="manual", preset=canonical["software"]["preset"],
        stacks=tuple(canonical["software"]["stacks"]),
        hostname=canonical["identity"]["hostname"],
        username=canonical["identity"]["username"],
        keyboard=canonical["keyboard"], boot_mode=canonical["boot_mode"],
        roles=st["partitions"], formats=fmt, home_layout="separate")
    fields = vm_manual_fields(manual, disks=disks, active_boot=active_boot,
                              check_device=check_device)
    return (*fields[:10], "reuse", *fields[11:16],
            "yes" if st["cleanup_home"] else "no", "0", "0")


def vm_execution_fields(doc: dict, *, disks: list[dict], active_boot: str | None = None,
                        check_device: bool = False) -> tuple[str, ...]:
    if doc.get("storage", {}).get("mode") == "reuse":
        return vm_reuse_fields(doc, disks=disks, active_boot=active_boot, check_device=check_device)
    if doc.get("storage", {}).get("mode") == "manual":
        return (*vm_manual_fields(doc, disks=disks, active_boot=active_boot, check_device=check_device), "no", "0", "0")
    base = vm_erase_fields(doc, disks=disks, active_boot=active_boot, check_device=check_device)
    size = doc["storage"]["erase_sizes"]
    layout = doc["storage"]["home_layout"]
    return (*base, "erase", "", "", "separate" if layout == "separate" else "", "yes", "no", "no",
            str(size["root_gib"]), str(size["home_gib"]))

def vm_preflight_file(path: Path, *, disks: list[dict] | None = None,
                      active_boot: str | None = None, check_device: bool = True) -> tuple[str, ...]:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 131072:
        raise PlanError("Plano ausente, symlink ou maior que o limite")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as exc:
        raise PlanError(f"JSON inválido: {exc}") from exc
    if active_boot is None:
        active_boot = "UEFI" if Path("/sys/firmware/efi").exists() else "BIOS"
    return vm_execution_fields(doc, disks=disks if disks is not None else inventory(),
                               active_boot=active_boot, check_device=check_device)


def simulate_document(doc: dict, *, disks: list[dict]) -> str:
    """Tradução declarativa do plano validado para etapas do Bash. Não executa nada."""
    canonical = validate_document(doc, disks=disks)
    st = canonical["storage"]
    roles, fmts = st["partitions"], st["format"]
    issues = []
    mode = st["mode"]
    if not st["disk"]:
        issues.append("Disco de referência não selecionado")
    if mode == "reuse":
        if st["home_layout"] != "separate":
            issues.append("Reutilização exige /home separada")
        if not roles["root"]:
            issues.append("Selecione a partição raiz /")
        if not fmts["root"]:
            issues.append("O modo reutilizar do Bash atual sempre formata a raiz em ext4")
        if fmts["esp"]:
            issues.append("Reutilização do Bash atual preserva a partição EFI; não formata ESP")
        if fmts["home"]:
            issues.append("O Bash atual não oferece formatação de /home em reutilização")
        if canonical["boot_mode"] == "UEFI" and not roles["esp"]:
            issues.append("Selecione EFI /boot/efi para instalação UEFI")
        if canonical["boot_mode"] == "BIOS":
            issues.append("BIOS exige tabela MBR/DOS neste modo; GRUB será instalado no DISCO, não em partição EFI")
        parts = {p["path"]: p for d in disks for p in d["partitions"]}
        if roles["esp"] and not fmts["esp"] and parts[roles["esp"]]["fstype"].lower() not in ("vfat", "fat32", "fat"):
            issues.append("EFI preservada precisa ter sistema de arquivos FAT/vfat")
    if mode == "manual":
        if not roles["root"] or not fmts["root"] or (canonical["boot_mode"] == "UEFI" and not roles["esp"]):
            issues.append("Manual exige raiz formatada; EFI apenas quando o boot é UEFI")
    if st["home_layout"] == "separate" and not roles["home"]:
        issues.append("Selecione a partição dedicada a /home")
    if canonical["boot_mode"] == "unknown":
        issues.append("Modo de firmware não identificado")
    lines = ["WOLF INSTALLER — SIMULAÇÃO DO BACKEND (NENHUM COMANDO EXECUTADO)",
             "Schema: " + SCHEMA, "EXECUÇÃO: DESABILITADA", "Nenhum processo de instalação, montagem, formatação ou reparo foi iniciado.",
             "", "INTERPRETAÇÃO DO MOTOR BASH:"]
    if mode == "erase":
        lines += ["1. O modo Bash correspondente seria: erase",
                  "2. Preparar partições no disco selecionado (intenção; não executar)",
                  "3. Apagar TODAS as partições existentes; em UEFI criar ESP FAT32 de 1 GiB; em BIOS SEM EFI",
                  "4. Criar / ext4: " + (f"{st['erase_sizes']['root_gib']} GiB" if st['erase_sizes']['root_gib'] else "restante"),
                  "5. /home ext4 separada: " + (f"{st['erase_sizes']['home_gib']} GiB" if st['erase_sizes']['home_gib'] else "restante") if st['home_layout'] == 'separate' else "5. /home será diretório dentro de /"]
    elif mode == "reuse":
        lines += ["1. O modo Bash correspondente seria: reuse-manual",
                  "2. Raiz /: " + (roles["root"] or "NÃO SELECIONADA") + " (Bash formata como ext4)",
                  "3. " + (("EFI: " + (roles["esp"] or "NÃO SELECIONADA") + " (preservar; montar em /boot/efi)") if canonical["boot_mode"] == "UEFI" else "BIOS: nenhuma partição EFI; GRUB no MBR do disco"),
                  "4. /home: " + (roles["home"] if st["home_layout"] == "separate" and roles["home"] else "diretório dentro de /"),
                  "5. Limpar configs ocultas de TODOS os usuários da /home: " + ("SIM, exigir LIMPAR" if st["cleanup_home"] else "NÃO"),
                  "6. Preservar os demais arquivos visíveis e instalar o sistema"]
    else:
        lines += ["1. O modo Bash correspondente seria: manual",
                  "2. Crie as partições no GParted: UEFI exige GPT+EFI, BIOS manual exige MBR sem EFI",
                  "3. Raiz /: formatada ext4. " + (("EFI: formatada FAT32" if fmts["esp"] else "EFI: preservada FAT32") if canonical["boot_mode"] == "UEFI" else "BIOS: SEM EFI"),
                  "4. /home separada: " + ("formatada ext4" if fmts["home"] else "preservada ext4") if roles["home"] else "4. /home ficará dentro da raiz /",
                  "5. O backend ajusta automaticamente o tipo GPT da partição EFI escolhida"]
    lines += ["", "INTEGRIDADE DO PLANO: OK (comparado a lsblk atual)"]
    if issues:
        lines += ["ESTADO: INCOMPLETO / AINDA NÃO SUPORTADO", *["BLOQUEIO: " + m for m in issues]]
    else:
        lines += ["ESTADO: PLANO COERENTE; executor exige revalidação e confirmação"]
    lines += ["", "Esta simulação não inicia a rotina main do instalador. O executor independente exige confirmação."]
    return "\n".join(lines)


def simulate_file(path: Path, *, disks: list[dict] | None = None) -> str:
    if not path.is_file() or path.stat().st_size > 131072:
        raise PlanError("Arquivo ausente ou excede tamanho permitido")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as exc:
        raise PlanError(f"Arquivo JSON inválido: {exc}") from exc
    return simulate_document(doc, disks=disks if disks is not None else inventory())


def write_private(doc: dict, destination: Path | None = None) -> Path:
    destination = destination or (Path.home() / ".local/state/wolf-linux/live-installer/preview.json")
    folder = destination.parent
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    if folder.is_symlink():
        raise PlanError("Diretório do plano não pode ser symlink")
    os.chmod(folder, 0o700)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=folder,
                                     prefix=".wolf-plan-", suffix=".json", delete=False) as temp:
        tmp = Path(temp.name)
        os.chmod(tmp, 0o600)
        json.dump(doc, temp, ensure_ascii=False, indent=2)
        temp.write("\n")
    os.replace(tmp, destination)
    return destination


def review_file(path: Path, *, disks: list[dict] | None = None) -> str:
    if not path.is_file() or path.stat().st_size > 131072:
        raise PlanError("Arquivo ausente ou excede tamanho permitido")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as exc:
        raise PlanError(f"Arquivo JSON inválido: {exc}") from exc
    canonical = validate_document(doc, disks=disks if disks is not None else inventory())
    return text_summary(canonical)


def main() -> int:
    parser = argparse.ArgumentParser(description="Wolf Installer — apenas revisão de pré-plano")
    parser.add_argument("action", choices=["review", "simulate", "vm-preflight", "vm-export"])
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        if args.action in ("vm-preflight", "vm-export"):
            fields = vm_preflight_file(args.path)
            if args.action == "vm-export":
                sys.stdout.buffer.write(("\0".join(fields) + "\0").encode("utf-8"))
            else:
                print("[OK] Plano de instalação validado (ainda SEM escrever no disco).")
                print(f"Destino: {fields[0]} ({int(fields[1]) / 2**30:.1f} GiB) | MAJ:MIN={fields[2]}")
                print(f"Boot: {fields[3]} | Usuário: {fields[5]} | Perfil: {fields[6]} | Modo: {fields[10]}")
                print("AVISO: a execução real exige outro comando, confirmação e validação renovada.")
        else:
            print(simulate_file(args.path) if args.action == "simulate" else review_file(args.path))
    except (PlanError, TypeError, KeyError, AttributeError, OSError) as exc:
        print(f"[ERRO] Plano recusado: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
