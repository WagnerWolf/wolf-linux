#!/usr/bin/env python3
"""Wolf installer: descoberta semiautomática multidisco, SOMENTE LEITURA.

Executar scan/review/simulate via sudo no Live. Um plano desta API não é
aceito pelo executor de instalação: execution=disabled e schema diferente.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

from wolf_storage_map import scan_lsblk_json, parse_fstab, _find_for_source, parent_disks

SCHEMA = 'wolf.install.multidisk.preview.v1'
SNAPSHOT_SCHEMA = 'wolf.install.discovery.v1'
ALLOWED_ROLES = ('root', 'esp', 'home')
MOUNTS = {'root': '/', 'esp': '/boot/efi', 'home': '/home'}
MIN_ROOT = 20 * 1024**3
MAX_FSTAB = 131072
# Inspeção de superbloco EXCLUSIVAMENTE de leitura. Nunca chama fsck automaticamente.
EXT4_RECOVERY_FEATURES = frozenset(('needs_recovery', 'orphan_present'))

class DiscoveryError(ValueError):
    pass


def lsblk_snapshot(raw: str | None = None) -> dict:
    if raw is None:
        result = subprocess.run(['lsblk', '--json', '-b', '-o',
             'NAME,PATH,TYPE,SIZE,FSTYPE,UUID,PARTUUID,MODEL,TRAN,RM,MAJ:MIN,MOUNTPOINTS,PARTTYPE'],
            capture_output=True, text=True, check=False, timeout=12)
        if result.returncode:
            raise DiscoveryError(f'lsblk falhou: {result.stderr[:300]}')
        raw = result.stdout
    try:
        nodes = scan_lsblk_json(raw)
        src = json.loads(raw)
    except (ValueError, TypeError) as exc:
        raise DiscoveryError('Inventário lsblk inválido') from exc
    # Rejeitar inventário sem discos para não gerar plano falso.
    disks = {p for p, n in nodes.items() if n.get('type') == 'disk'}
    if not disks:
        raise DiscoveryError('Nenhum disco encontrado')
    device_info = {}
    for path, node in nodes.items():
        disk_paths, pvs = parent_disks(nodes, path)
        top_disks = [nodes.get(p, {}) for p in disk_paths]
        usb = any(str(d.get('tran') or '').lower() == 'usb' or
                  str(d.get('rm') or '').lower() in ('1', 'true') for d in top_disks)
        if node.get('type') not in ('part', 'lvm', 'crypt'):
            continue
        if not path.startswith('/dev/'):
            continue
        device_info[path] = {
            'path': path, 'size': int(node.get('size') or 0),
            'fstype': str(node.get('fstype') or '').lower(),
            'uuid': str(node.get('uuid') or ''),
            'partuuid': str(node.get('partuuid') or ''),
            'majmin': str(node.get('maj:min') or ''),
            'parent_disks': disk_paths,
            'lvm_pvs': pvs, 'usb_ancestor': usb,
            'type': node.get('type'),
            'parttype': str(node.get('parttype') or '').lower(),
            'mountpoints': [m for m in (node.get('mountpoints') or []) if isinstance(m, str) and m],
        }
    return {'raw': raw, 'nodes': nodes, 'devices': device_info}


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def _candidate(root: str, fstab_text: str, snap: dict) -> dict | None:
    # fstab da raiz DEVE apontar inequivocamente ao volume que o contém.
    entries = parse_fstab(fstab_text)
    matching_root = [e for e in entries if e.target == '/']
    if len(matching_root) != 1 or _find_for_source(snap['nodes'], matching_root[0].source) != [root]:
        return None
    detected, messages = {'root': root, 'esp': None, 'home': None}, []
    for role in ('esp', 'home'):
        arr = [e for e in entries if e.target == MOUNTS[role]]
        if not arr:
            messages.append(f'{MOUNTS[role]}: sem entrada dedicada no fstab')
            continue
        if len(arr) != 1:
            messages.append(f'{MOUNTS[role]}: entradas duplicadas; escolha manualmente')
            continue
        matches = _find_for_source(snap['nodes'], arr[0].source)
        if len(matches) == 1:
            detected[role] = matches[0]
        else:
            messages.append(f'{MOUNTS[role]}: UUID ausente ou ambíguo ({arr[0].source})')
    return {'root': root, 'fstab_sha256': _sha(fstab_text),
            'suggestions': detected, 'notes': messages}


def _fstab_read(mountpoint: Path) -> str | None:
    fstab = mountpoint / 'etc' / 'fstab'
    if fstab.is_symlink() or not fstab.is_file() or fstab.stat().st_size > MAX_FSTAB:
        return None
    raw = fstab.read_bytes()
    if len(raw) > MAX_FSTAB:
        return None
    return raw.decode('utf-8', errors='replace')


def parse_ext4_health(report: str) -> dict:
    """Interpreta a saída `tune2fs -l` sem confiar em comentários do fstab."""
    def field(name: str) -> str:
        match = re.search(r'^' + re.escape(name) + r':\s*(.*)$', report, re.MULTILINE)
        return match.group(1).strip() if match else ''

    features = field('Filesystem features').split()
    state = field('Filesystem state')
    pending = sorted(EXT4_RECOVERY_FEATURES.intersection(features))
    return {'features': features, 'state': state, 'pending': pending}


def _ext4_health(path: str) -> dict:
    """Inspeciona flags do ext4, sem montar nem recuperar journal."""
    try:
        proc = subprocess.run(['tune2fs', '-l', path], capture_output=True,
                              text=True, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {'features': [], 'state': '', 'pending': [], 'error': f'tune2fs indisponível: {exc}'}
    if proc.returncode:
        return {'features': [], 'state': '', 'pending': [],
                'error': ('tune2fs não conseguiu consultar o superbloco: ' +
                          (proc.stderr or '').strip())[:250]}
    result = parse_ext4_health(proc.stdout)
    if not result['features']:
        result['error'] = 'tune2fs não retornou as features do ext4'
    return result


def _ext4_recovery_message(path: str, health: dict) -> str:
    flags = ', '.join(health['pending'])
    return (f'EXT4 COM RECUPERAÇÃO PENDENTE ({flags}) em {path}. '
            'Não montado com ro,noload, não reparado. Faça backup dos dados, '
            'confirme que o volume está DESMONTADO e examine com '
            f'`sudo e2fsck -f -n {path}`. Reparação exige decisão separada; '
            'não execute fsck no volume montado.')


def _read_candidate_root(path: str, info: dict) -> str | None:
    """Montagem efêmera ext4 ro,noload; sem fsck, sem ativar LVM, sem escrita."""
    # Se já estiver montado, não alterar estado; apenas ler o fstab dali.
    for mountpoint in info.get('mountpoints') or []:
        try:
            result = _fstab_read(Path(mountpoint))
            if result is not None:
                return result
        except (OSError, UnicodeError):
            pass
    if os.geteuid() != 0:
        raise DiscoveryError('A descoberta precisa rodar como root para montar candidatos somente leitura')
    st = os.stat(path)
    if not stat.S_ISBLK(st.st_mode):
        raise DiscoveryError(f'O destino não é um dispositivo de blocos: {path}')
    # Em volumes não montados, ler primeiro o superbloco; um ext4 com
    # needs_recovery/orphan_present não deve ser ocultado como candidato vazio.
    # Não usar mount sem noload (isso poderia reproduzir o journal e escrever).
    health = _ext4_health(path)
    if health['pending']:
        raise DiscoveryError(_ext4_recovery_message(path, health))
    with tempfile.TemporaryDirectory(prefix='wolf-scan-', dir='/run') as tmp:
        proc = subprocess.run(['mount', '-t', 'ext4', '-o', 'ro,noload,nosuid,nodev,noexec',
                               '--', path, tmp], capture_output=True, text=True, timeout=15)
        if proc.returncode:
            detail = (proc.stderr or proc.stdout or '').strip().replace('\n', ' ')
            detail = detail[:220] or f'mount retornou código {proc.returncode}'
            extra = (f' ({health["error"]})' if health.get('error') else '')
            raise DiscoveryError(
                f'Não foi possível ler o ext4 por montagem ro,noload em {path}: {detail}{extra}. '
                'Consulte `dmesg` e verifique SEM reparação automática com '
                f'`sudo e2fsck -f -n {path}` SOMENTE se estiver desmontado.')
        try:
            return _fstab_read(Path(tmp))
        finally:
            unmount = subprocess.run(['umount', '--', tmp], capture_output=True, text=True, timeout=15)
            if unmount.returncode:
                raise DiscoveryError(f'Falha ao desmontar leitura temporária {tmp}; não continuar')


def discover(*, raw: str | None = None, fstab_by_root: dict[str, str] | None = None,
             boot_mode: str | None = None) -> dict:
    snap = lsblk_snapshot(raw)
    candidates, errors = [], []
    for path, info in sorted(snap['devices'].items()):
        if info['fstype'] != 'ext4' or info['usb_ancestor'] or info['size'] < MIN_ROOT:
            continue
        # Nunca montar partições protegidas/externas além dos candidatos ext4.
        try:
            text = (fstab_by_root.get(path) if fstab_by_root is not None else _read_candidate_root(path, info))
            if not text:
                continue
            entry = _candidate(path, text, snap)
            if entry:
                candidates.append(entry)
        except (OSError, subprocess.TimeoutExpired, DiscoveryError) as exc:
            errors.append(f'{path}: {exc}')
    firmware = boot_mode or ('UEFI' if Path('/sys/firmware/efi').exists() else 'BIOS')
    if firmware not in ('UEFI', 'BIOS'):
        raise DiscoveryError('Firmware inválido')
    return {'schema': SNAPSHOT_SCHEMA, 'execution': 'disabled', 'boot_mode': firmware,
            'devices': snap['devices'], 'candidates': candidates, 'errors': errors}


def _device_identity(device: dict) -> dict:
    return {k: device[k] for k in ('path', 'size', 'fstype', 'uuid', 'partuuid',
                                 'majmin', 'parent_disks', 'lvm_pvs', 'type', 'parttype')}


def build_plan(snapshot: dict, *, root: str, esp: str | None, home: str | None,
               confirmed: bool, acknowledge_override: bool, username: str,
               hostname: str, preset: str, stacks: tuple[str, ...] = (),
               keyboard: dict | None = None, home_cleanup: dict | None = None) -> dict:
    if snapshot.get('schema') != SNAPSHOT_SCHEMA or snapshot.get('execution') != 'disabled':
        raise DiscoveryError('Inventário inválido')
    if not confirmed:
        raise DiscoveryError('Confirme explicitamente as atribuições antes de revisar o plano')
    if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', username):
        raise DiscoveryError('Usuário inválido')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,62}', hostname) or hostname.endswith('-'):
        raise DiscoveryError('Hostname inválido')
    try:
        from wolf_plan import STACKS, PRESETS
    except ImportError as exc:
        raise DiscoveryError('Contrato de perfis ausente') from exc
    if preset not in ('minimal', 'basic', 'test', 'full', 'custom'):
        raise DiscoveryError('Perfil inválido')
    if len(stacks) != len(set(stacks)) or any(stack not in STACKS for stack in stacks):
        raise DiscoveryError('Lista de stacks inválida')
    if preset in PRESETS and tuple(stacks) != PRESETS[preset]:
        raise DiscoveryError('Stacks incompatíveis com preset')
    from wolf_home_cleanup import validate_spec
    home_cleanup = validate_spec(home_cleanup)
    keyboard = keyboard or {'layout': 'br', 'model': 'abnt2', 'variant': ''}
    if not isinstance(keyboard, dict) or set(keyboard) != {'layout', 'model', 'variant'} or not all(
            isinstance(v, str) and re.fullmatch(r'[a-z0-9]{0,16}', v) for v in keyboard.values()):
        raise DiscoveryError('Teclado inválido')
    candidate = next((c for c in snapshot['candidates'] if c['root'] == root), None)
    if candidate is None:
        raise DiscoveryError('Raiz escolhida não identificada como instalação existente')
    all_roles = {'root': root, 'esp': esp, 'home': home}
    if snapshot['boot_mode'] == 'UEFI' and not esp:
        raise DiscoveryError('UEFI exige a identificação de uma partição EFI')
    if snapshot['boot_mode'] == 'BIOS' and esp:
        raise DiscoveryError('BIOS não utiliza EFI neste planejador')
    if len([p for p in all_roles.values() if p]) != len(set(p for p in all_roles.values() if p)):
        raise DiscoveryError('Uma partição/volume não pode exercer dois papéis')
    devices = snapshot['devices']
    for role, path in all_roles.items():
        if not path:
            continue
        if path not in devices or devices[path]['usb_ancestor']:
            raise DiscoveryError(f'{role}: dispositivo não disponível ou pertence à mídia USB')
        expected_fs = 'vfat' if role == 'esp' else 'ext4'
        if devices[path]['fstype'] != expected_fs:
            raise DiscoveryError(f'{role}: requer {expected_fs}, mas {path} contém {devices[path]["fstype"]}')
    if esp and devices[esp]['parttype'] != 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b':
        raise DiscoveryError('EFI escolhida não possui o tipo GPT ESP esperado')
    if devices[root]['size'] < MIN_ROOT:
        raise DiscoveryError('Raiz menor que 20 GiB')
    mismatch = [r for r in ('esp', 'home') if all_roles[r] != candidate['suggestions'][r]]
    if mismatch and not acknowledge_override:
        raise DiscoveryError('Divergência do fstab em ' + ', '.join(mismatch) +
                             ': marque a confirmação separada das alterações')
    roles = {r: _device_identity(devices[p]) if p else None for r, p in all_roles.items()}
    warnings = [f'FORMATAR RAIZ {root} EM EXT4 APAGARIA TODOS OS SEUS DADOS.',
                'EFI e /home existentes serão preservadas e NUNCA formatadas por este plano.',
                'A execução depende de verificação física independente e confirmação dupla.']
    if not home:
        warnings.append('/home não possui volume separado: quaisquer dados anteriores dentro de / seriam perdidos.')
    if mismatch:
        warnings.append('ALTERAÇÕES MANUAIS DIVERGEM DO FSTAB: ' + ', '.join(mismatch))
    home_pvs = devices[home]['lvm_pvs'] if home else []
    if len(home_pvs) > 1:
        warnings.append('LVM multidisco: preservar obrigatoriamente TODOS os PVs ' + ', '.join(home_pvs))
    return {'schema': SCHEMA, 'execution': 'disabled', 'mode': 'multidisk-reuse-preview',
            'boot_mode': snapshot['boot_mode'], 'source': {
                'root': root, 'fstab_sha256': candidate['fstab_sha256'],
            }, 'roles': roles, 'actions': {
                'root': 'format_ext4', 'esp': 'preserve', 'home': 'preserve',
            }, 'identity': {'username': username, 'hostname': hostname},
            'software': {'preset': preset, 'stacks': list(stacks)}, 'keyboard': keyboard,
            'confirmed': True, 'acknowledge_override': acknowledge_override,
            'home_cleanup': home_cleanup, 'warnings': warnings}


def validate_plan(doc: dict, snapshot: dict) -> dict:
    if not isinstance(doc, dict) or doc.get('schema') != SCHEMA or doc.get('execution') != 'disabled':
        raise DiscoveryError('Schema incorreto ou tentativa de habilitar execução')
    if set(doc) != {'schema', 'execution', 'mode', 'boot_mode', 'source', 'roles', 'actions',
                    'identity', 'software', 'keyboard', 'confirmed', 'acknowledge_override', 'home_cleanup', 'warnings'}:
        raise DiscoveryError('Campos desconhecidos no plano')
    if doc['mode'] != 'multidisk-reuse-preview' or doc['boot_mode'] != snapshot['boot_mode']:
        raise DiscoveryError('Modo ou firmware incompatível')
    if not isinstance(doc['source'], dict) or not isinstance(doc['roles'], dict):
        raise DiscoveryError('Fonte ou papéis precisam ser objetos')
    if set(doc['source']) != {'root', 'fstab_sha256'} or set(doc['roles']) != set(ALLOWED_ROLES):
        raise DiscoveryError('Fonte ou papéis inválidos')
    if doc['actions'] != {'root': 'format_ext4', 'esp': 'preserve', 'home': 'preserve'}:
        raise DiscoveryError('Ações desconhecidas / formatação indevida')
    if not isinstance(doc['identity'], dict) or not isinstance(doc['software'], dict):
        raise DiscoveryError('Identidade e software inválidos')
    if set(doc['identity']) != {'username', 'hostname'} or set(doc['software']) != {'preset', 'stacks'}:
        raise DiscoveryError('Identidade inválida')
    if type(doc['confirmed']) is not bool or type(doc['acknowledge_override']) is not bool:
        raise DiscoveryError('Confirmações devem ser booleanas')
    roles = doc['roles']
    if any(role is not None and (not isinstance(role, dict) or 'path' not in role) for role in roles.values()):
        raise DiscoveryError('Identidade de dispositivo incompleta')
    choices = {key: (roles[key]['path'] if roles[key] else None) for key in ALLOWED_ROLES}
    rebuilt = build_plan(snapshot, root=doc['source']['root'],
                        esp=choices['esp'], home=choices['home'],
                        confirmed=doc['confirmed'], acknowledge_override=doc['acknowledge_override'],
                        **doc['identity'], preset=doc['software']['preset'],
                        stacks=tuple(doc['software']['stacks']), keyboard=doc['keyboard'],
                        home_cleanup=doc['home_cleanup'])
    if rebuilt != doc:
        raise DiscoveryError('Plano alterado ou inventário/fstab mudou; refaça a detecção')
    return rebuilt


def render_plan(doc: dict, *, simulated: bool = False) -> str:
    prefix = 'SIMULAÇÃO ESTRUTURAL — SEM EXECUTAR' if simulated else 'REVISÃO MULTIDISCO — SOMENTE LEITURA'
    lines = ['WOLF INSTALLER — ' + prefix,
             'REVISÃO SOMENTE LEITURA; execução requer executor independente e consentimento',
             'Fonte: instalação identificada pelo fstab, UUIDs revalidados via lsblk.',
             f'Firmware: {doc["boot_mode"]} | Perfil: {doc["software"]["preset"]}',
             'Stacks: ' + (', '.join(doc['software']['stacks']) or 'nenhuma (Minimal)'),
             f'Usuário: {doc["identity"]["username"]} | hostname: {doc["identity"]["hostname"]}', '']
    for role, label in [('root', 'RAIZ /'), ('esp', 'EFI /boot/efi'), ('home', 'HOME /home')]:
        d = doc['roles'][role]
        lines.append(f'{label}: {d["path"] if d else "(integrada à raiz / ou não aplicável)"}')
        if d:
            lines += [f'  UUID: {d["uuid"] or "sem UUID"} | filesystem: {d["fstype"]}',
                      '  Discos envolvidos: ' + ', '.join(d['parent_disks']),
                      '  PV(s) LVM: ' + (', '.join(d['lvm_pvs']) or 'nenhum')]
    cleanup = doc['home_cleanup']
    lines += ['', 'LIMPEZA OPCIONAL DO /home:',
              '  Dotfiles imediatos do usuário: ' + ('TODOS (.local, .steam, .ssh etc.)' if cleanup.get('enabled') else ('SELEÇÃO LEGADA: ' + ', '.join(cleanup['items']) if cleanup.get('items') else 'nenhum (preservar tudo)')),
              '  Backup dos itens: ' + ('SIM, consome espaço adicional' if cleanup['backup'] else 'NÃO'),
              '', 'ROTEIRO DE OPERAÇÕES — ESTA REVISÃO NÃO EXECUTA:', 
              '1. Revalidar UUID, tamanho, caminho e dependências de TODOS os dispositivos.',
              '2. Confirmar especificamente a formatação da raiz /; backup geral recomendado, não obrigatório.',
              '3. O executor físico, quando apto, formata SOMENTE a raiz / em ext4.',
              '4. Preservaria EFI' + (' e /home dedicada, inclusive todos os PVs do LVM.' if doc['roles']['home'] else '; /home integrada à raiz NÃO seria preservada.'),
              '5. Verificaria o carregador WolfLinux sem apagar entradas Windows/GRUB.',
              '6. Bloquearia qualquer mudança no destino entre planejamento e execução.',
              '', 'AVISOS:', *['- ' + w for w in doc['warnings']],
              '', 'ESTADO: revisão coerente; NÃO É autorização de instalação.']
    return '\n'.join(lines) + '\n'


def _load_plan(path: str) -> dict:
    p = Path(path)
    if p.is_symlink() or not p.is_file() or p.stat().st_size > MAX_FSTAB:
        raise DiscoveryError('Arquivo JSON ausente, symlink ou muito grande')
    return json.loads(p.read_text(encoding='utf-8'))


def cli() -> int:
    parser = argparse.ArgumentParser(description='Descoberta e planejamento de reutilização, SOMENTE leitura')
    parser.add_argument('action', choices=('scan', 'review', 'simulate'))
    parser.add_argument('file', nargs='?')
    args = parser.parse_args()
    try:
        if os.geteuid() != 0:
            raise DiscoveryError('Execute este diagnóstico como root na Live')
        if args.action in ('review', 'simulate') and not args.file:
            raise DiscoveryError('Informe o JSON para revisar/simular')
        snap = discover()
        if args.action == 'scan':
            print(json.dumps(snap, ensure_ascii=False))
            return 0
        doc = _load_plan(args.file)
        validated = validate_plan(doc, snap)
        print(render_plan(validated, simulated=args.action == 'simulate'))
        return 0
    except (DiscoveryError, OSError, ValueError, TypeError, KeyError, subprocess.TimeoutExpired) as exc:
        print('[ERRO] ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(cli())
