#!/usr/bin/env python3
"""Modelo read-only para o protótipo da interface Wolf Installer.

NENHUMA função altera discos, partições, montagens ou bootloader.
Não é compatível com os contratos executáveis do Wolf Installer.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import json
import os
import subprocess
from typing import Any

GIB = 1024 ** 3
ELIGIBLE_TYPES = {"part", "lvm", "crypt", "md", "raid0", "raid1", "raid4", "raid5", "raid6", "raid10"}


class PreviewError(ValueError):
    pass


def human_size(n: int) -> str:
    n = int(n or 0)
    return f"{n / GIB:.1f} GiB" if n >= GIB else f"{n / (1024**2):.0f} MiB"


@dataclass
class Device:
    path: str
    kind: str
    size: int
    fstype: str = ""
    label: str = ""
    model: str = ""
    tran: str = ""
    rm: bool = False
    ro: bool = False
    mountpoints: tuple[str, ...] = ()
    parents: set[str] = field(default_factory=set)
    uuid: str = ""

    @property
    def mounted(self) -> bool:
        return bool(self.mountpoints)


@dataclass
class Inventory:
    nodes: dict[str, Device]
    firmware: str
    illustrative: bool = False

    @property
    def disks(self) -> list[Device]:
        return sorted((d for d in self.nodes.values() if d.kind == "disk"), key=lambda x: x.path)

    @property
    def volumes(self) -> list[Device]:
        return sorted((d for d in self.nodes.values() if d.kind in ELIGIBLE_TYPES), key=lambda x: x.path)

    def get(self, path: str) -> Device | None:
        return self.nodes.get(path)

    def disk_ancestors(self, path: str) -> set[str]:
        result, visited = set(), set()
        def walk(p: str) -> None:
            if p in visited:
                return
            visited.add(p)
            obj = self.get(p)
            if not obj:
                return
            if obj.kind == 'disk':
                result.add(obj.path)
            for parent in obj.parents:
                walk(parent)
        walk(path)
        return result

    def descendants(self, path: str) -> list[Device]:
        # Follow graph edges in reverse; a multi-PV LV appears only once.
        found = {path}
        result = []
        modified = True
        while modified:
            modified = False
            for dev in self.nodes.values():
                if dev.path not in found and dev.parents.intersection(found):
                    found.add(dev.path)
                    result.append(dev)
                    modified = True
        return sorted(result, key=lambda d: (len(d.parents), d.path))


def parse_lsblk(text: str, firmware: str = "UEFI", illustrative: bool = False) -> Inventory:
    try:
        parsed = json.loads(text)
        roots = parsed['blockdevices']
        if not isinstance(roots, list):
            raise ValueError('blockdevices')
    except (ValueError, KeyError, TypeError) as exc:
        raise PreviewError('Inventário lsblk inválido ou indisponível.') from exc
    devices: dict[str, Device] = {}

    def walk(raw: dict, parent: str | None = None):
        path = raw.get('path') or ('/dev/' + str(raw.get('name') or ''))
        if not path.startswith('/dev/') or path == '/dev/':
            return
        def txt(name: str) -> str:
            return str(raw.get(name) or '')
        try:
            size = int(raw.get('size') or 0)
        except (TypeError, ValueError):
            size = 0
        mps = raw.get('mountpoints') or []
        if not isinstance(mps, list):
            mps = [mps]
        mps = tuple(str(p) for p in mps if p)
        previous = devices.get(path)
        if previous is None:
            previous = Device(path=path, kind=txt('type'), size=size,
                              fstype=txt('fstype'), label=txt('label'),
                              model=txt('model'), tran=txt('tran'),
                              rm=str(raw.get('rm', '0')).lower() in ('1', 'true'),
                              ro=str(raw.get('ro', '0')).lower() in ('1', 'true'),
                              mountpoints=mps, uuid=txt('uuid'))
            devices[path] = previous
        else:
            # The same LVM LV may occur under two or more PVs.
            previous.mountpoints = tuple(sorted(set(previous.mountpoints) | set(mps)))
        if parent and parent != path:
            previous.parents.add(parent)
        for child in raw.get('children') or []:
            walk(child, path)
    for root in roots:
        walk(root)
    return Inventory(devices, firmware, illustrative)


def detect_inventory() -> Inventory:
    # No sudo, no scanning mounts, and no filesystem writes.
    command = ['lsblk', '--json', '--bytes', '--paths', '--output',
               'PATH,NAME,TYPE,SIZE,FSTYPE,LABEL,MODEL,TRAN,RM,RO,MOUNTPOINTS,UUID']
    try:
        run = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, timeout=12, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise PreviewError(f'Não foi possível consultar os dispositivos: {exc}') from exc
    if run.returncode:
        raise PreviewError(f'lsblk falhou: {run.stderr.strip()[:240]}')
    return parse_lsblk(run.stdout, firmware='UEFI' if Path('/sys/firmware/efi').exists() else 'BIOS')


def demo_inventory() -> Inventory:
    """Inventário ilustrativo; nenhum identificador aqui é usado para operações reais."""
    raw = {'blockdevices': [
        {'path':'/dev/sda','type':'disk','size':512*GIB,'model':'Unidade SATA ilustrativa','children':[
            {'path':'/dev/sda1','type':'part','size':1*GIB,'fstype':'vfat'},
            {'path':'/dev/sda2','type':'part','size':120*GIB,'fstype':'ext4'},
            {'path':'/dev/sda3','type':'part','size':390*GIB,'fstype':'ntfs'}]},
        {'path':'/dev/nvme0n1','type':'disk','size':1024*GIB,'model':'SSD NVMe ilustrativo','children':[
            {'path':'/dev/nvme0n1p1','type':'part','size':512*GIB,'fstype':'lvm2_member','children':[
                {'path':'/dev/mapper/volume-home','type':'lvm','size':700*GIB,'fstype':'ext4'}]}]},
        {'path':'/dev/sdb','type':'disk','size':512*GIB,'model':'Disco adicional ilustrativo','children':[
            {'path':'/dev/sdb1','type':'part','size':500*GIB,'fstype':'lvm2_member','children':[
                {'path':'/dev/mapper/volume-home','type':'lvm','size':700*GIB,'fstype':'ext4'}]}]},
    ]}
    return parse_lsblk(json.dumps(raw), firmware='UEFI', illustrative=True)


# Orçamento ilustrativo para o layout automático. A margem de 1 GiB cobre
# alinhamento/espaço reservado. NÃO é contrato de execução do instalador.
@dataclass(frozen=True)
class EraseBudget:
    disk_gib: int
    boot_gib: int
    margin_gib: int
    usable_gib: int


@dataclass(frozen=True)
class EraseAllocation:
    budget: EraseBudget
    root_gib: int
    home_gib: int
    unallocated_gib: int


def erase_budget(inv: Inventory, path: str) -> EraseBudget:
    disk = inv.get(path)
    if not disk or disk.kind != 'disk':
        raise PreviewError('Selecione uma unidade física válida para apagar.')
    if disk.ro:
        raise PreviewError('Unidade somente leitura; não pode receber instalação.')
    disk_gib = disk.size // GIB
    if disk_gib < 30:
        raise PreviewError('O disco precisa ter pelo menos 30 GiB neste esboço.')
    boot_gib = 1 if inv.firmware == 'UEFI' else 0
    margin_gib = 1
    usable_gib = disk_gib - boot_gib - margin_gib
    if usable_gib < 25:
        raise PreviewError('Espaço útil insuficiente para a partição raiz.')
    return EraseBudget(disk_gib, boot_gib, margin_gib, usable_gib)


def erase_allocation(inv: Inventory, choices: 'Choices') -> EraseAllocation:
    budget = erase_budget(inv, choices.erase_disk)
    home_minimum = 10 if choices.erase_home_separate else 0
    root = choices.erase_root_gib
    if not 25 <= root <= budget.usable_gib - home_minimum:
        raise PreviewError('O tamanho da raiz excede o espaço disponível; reserve no mínimo 25 GiB para / e 10 GiB para /home separada.')
    if choices.erase_home_separate:
        home = budget.usable_gib - root if choices.erase_home_gib is None else choices.erase_home_gib
        if not 10 <= home <= budget.usable_gib - root:
            raise PreviewError('O tamanho da /home excede o espaço disponível após reservar a raiz e o boot.')
    else:
        if choices.erase_home_gib is not None:
            raise PreviewError('Tamanho independente de /home exige partição /home separada.')
        home = 0
    return EraseAllocation(budget, root, home, budget.usable_gib - root - home)


@dataclass
class Choices:
    mode: str = 'reuse'               # erase, reuse, manual
    erase_disk: str = ''
    erase_home_separate: bool = False
    erase_root_gib: int = 60
    erase_home_gib: int | None = None  # None = usar espaço restante para /home
    root: str = ''
    efi: str = ''
    home: str = ''
    bios_disk: str = ''
    format_efi: bool = False          # manual only
    format_home: bool = False         # manual only
    clean_dotfiles: bool = False      # reuse only
    backup_dotfiles: bool = False     # reuse only


@dataclass(frozen=True)
class Operation:
    target: str
    action: str
    impact: str
    destructive: bool

    def as_dict(self):
        return {"target":self.target, "action":self.action,
                "impact":self.impact, "destructive":self.destructive}


def describe_device(d: Device) -> str:
    desc = f'{d.path}  ·  {human_size(d.size)}'
    if d.fstype:
        desc += f'  ·  {d.fstype}'
    if d.model:
        desc += f'  ·  {d.model.strip()}'
    if d.mountpoints:
        desc += f'  ·  montado em {", ".join(d.mountpoints)}'
    return desc


def validate_plan(inv: Inventory, c: Choices) -> list[Operation]:
    """Pure model; no executor or shell. Never means real backend support."""
    if c.mode not in ('erase', 'manual', 'reuse'):
        raise PreviewError('Escolha uma modalidade de instalação.')
    ops: list[Operation] = []
    if c.mode == 'erase':
        allocation = erase_allocation(inv, c)
        disk = inv.get(c.erase_disk)
        ops.append(Operation(disk.path, 'Apagar unidade inteira',
                             'EXCLUIR todas as partições e os dados existentes', True))
        for child in inv.descendants(disk.path):
            if child.kind in ELIGIBLE_TYPES and disk.path in inv.disk_ancestors(child.path):
                ops.append(Operation(child.path, 'Remover volume existente',
                                     'Dados apagados no disco selecionado; verificar dependências LVM', True))
        # Cross-disk LVM is dangerous to treat as local; do not claim the other PV survives unaffected.
        affected_shared = [d for d in inv.descendants(disk.path)
                           if d.kind == 'lvm' and len(inv.disk_ancestors(d.path)) > 1]
        if affected_shared:
            ops.append(Operation('LVM em múltiplos discos', 'Verificação especial necessária',
                                 'Um volume lógico utiliza também outros discos; não é seguro apagar isoladamente sem um plano específico', True))
        ops.append(Operation(disk.path, 'Criar tabela de partições',
                             'GPT' if inv.firmware == 'UEFI' else 'Layout BIOS compatível (a definir)', False))
        if inv.firmware == 'UEFI':
            ops.append(Operation('Nova partição EFI', 'Criar e formatar FAT32', f'{allocation.budget.boot_gib} GiB reservados para EFI', False))
        ops.append(Operation('Nova partição /', 'Criar e formatar ext4',
                             f'{allocation.root_gib} GiB', False))
        if c.erase_home_separate:
            ops.append(Operation('Nova partição /home', 'Criar e formatar ext4', f'{allocation.home_gib} GiB', False))
        if allocation.unallocated_gib:
            ops.append(Operation('Espaço não alocado', 'Manter sem partição',
                                 f'{allocation.unallocated_gib} GiB permanecerão livres', False))
        return ops

    root = inv.get(c.root)
    if not root or root.kind not in ELIGIBLE_TYPES:
        raise PreviewError('Escolha a partição ou volume da raiz (/).')
    if root.ro:
        raise PreviewError('O volume da raiz é somente leitura.')
    if inv.firmware == 'UEFI':
        esp = inv.get(c.efi)
        if not esp or esp.kind != 'part':
            raise PreviewError('Em UEFI, escolha uma partição EFI válida.')
        if c.mode == 'reuse' or not c.format_efi:
            if esp.fstype.lower() not in ('vfat', 'fat', 'fat32'):
                raise PreviewError('A EFI preservada precisa ser FAT32/vfat.')
    elif not inv.get(c.bios_disk) or inv.get(c.bios_disk).kind != 'disk':
        raise PreviewError('Em BIOS, selecione o disco de instalação do bootloader.')
    home = inv.get(c.home) if c.home else None
    if c.home and (not home or home.kind not in ELIGIBLE_TYPES):
        raise PreviewError('Selecione um volume válido para /home.')
    keys = [c.root] + ([c.efi] if inv.firmware == 'UEFI' else []) + ([c.home] if home else [])
    if len(keys) != len(set(keys)):
        raise PreviewError('Um mesmo volume não pode receber duas funções (/, EFI, /home).')
    if c.mode == 'reuse':
        if c.format_efi or c.format_home:
            raise PreviewError('A reutilização não pode formatar EFI nem /home.')
        if c.clean_dotfiles and not home:
            raise PreviewError('A limpeza exige uma partição /home separada e preservada.')
        if c.backup_dotfiles and not c.clean_dotfiles:
            raise PreviewError('Backup sem limpeza não é uma opção aplicável.')
    elif c.clean_dotfiles or c.backup_dotfiles:
        raise PreviewError('A limpeza de dotfiles pertence somente à reutilização.')
    ops.append(Operation(root.path, 'Formatar / em ext4', 'APAGAR o conteúdo anterior da partição raiz', True))
    if inv.firmware == 'UEFI':
        if c.mode == 'manual' and c.format_efi:
            ops.append(Operation(c.efi, 'Formatar EFI em FAT32', 'APAGAR carregadores existentes, inclusive de outros sistemas', True))
        else:
            ops.append(Operation(c.efi, 'Reaproveitar EFI', 'Preservar arquivos existentes; integrar bootloader futuramente', False))
    else:
        ops.append(Operation(c.bios_disk, 'Instalar bootloader BIOS', 'Alterar área de inicialização do disco; validar GPT/MBR previamente', True))
    if home:
        if c.mode == 'manual' and c.format_home:
            ops.append(Operation(c.home, 'Formatar /home em ext4', 'APAGAR todos os arquivos pessoais deste volume', True))
        else:
            ops.append(Operation(c.home, 'Preservar /home', 'Manter volume, sistema de arquivos e arquivos pessoais', False))
    else:
        ops.append(Operation('/home', 'Criar diretório na raiz', 'Não haverá volume separado; conteúdo anterior em / será perdido', False))
    if c.mode == 'reuse' and c.clean_dotfiles:
        ops.append(Operation('/home/<usuário>/.…', 'Remover entradas ocultas',
                             'APAGAR entradas ocultas diretamente em cada pasta pessoal; arquivos visíveis permanecem', True))
        if c.backup_dotfiles:
            ops.append(Operation('/home', 'Salvar backup opcional',
                                 'Cópia das entradas ocultas antes da exclusão (a validar espaço disponível)', False))
    return ops


def preview_dotfiles(inv: Inventory, home_path: str) -> tuple[list[str], str]:
    """Reads filenames only when selected volume is already mounted exactly at /home.

    Never mounts, recursively scans or reads credentials.
    """
    dev = inv.get(home_path)
    if not dev or '/home' not in dev.mountpoints:
        return [], 'A lista de arquivos será calculada na Live quando o volume /home selecionado estiver montado e conferido.'
    home = Path('/home')
    try:
        if not home.is_dir():
            raise OSError('home unavailable')
        names: list[str] = []
        for account in home.iterdir():
            if not account.is_dir() or account.is_symlink():
                continue
            for item in account.iterdir():
                if item.name.startswith('.') and item.name not in ('.','..'):
                    names.append(f'{account.name}/{item.name}')
                    if len(names) >= 500:
                        return sorted(names), 'Lista limitada a 500 entradas para manter a interface responsiva.'
        return sorted(names), 'Leitura dos nomes diretamente no /home já montado. Nenhuma alteração realizada.'
    except OSError:
        return [], 'Não foi possível listar /home sem alterar suas montagens.'


def safe_export(c: Choices, inv: Inventory, ops: list[Operation]) -> dict[str, Any]:
    return {
        'schema': 'wolf.interface.preview.v1', 'execution': 'DISABLED',
        'source': 'local-read-only', 'firmware': inv.firmware,
        'illustrative': inv.illustrative,
        'choices': dict(vars(c)),
        'operations': [op.as_dict() for op in ops],
        'notice': 'Arquivo de revisão não executável. O instalador real deverá revalidar os dispositivos antes de qualquer operação.',
    }
