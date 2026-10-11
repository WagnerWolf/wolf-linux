#!/usr/bin/env python3
"""Mapa de discos e fstab para o Wolf Rescue. Somente leitura; nenhuma ação de sistema.

Reconstrói relações físicas dos nós lsblk (inclusive LVs repetidos sob PVs
em discos diferentes) e correlaciona UUID/PARTUUID do fstab ao inventário.
"""
from __future__ import annotations

import json
import re
from collections import defaultdict
from dataclasses import dataclass

ROLE_MOUNTS = ('/', '/boot/efi', '/home')
UUID_RE = re.compile(r'^[A-Za-z0-9._:+-]{1,128}$')


@dataclass(frozen=True)
class FstabEntry:
    source: str
    target: str
    fstype: str
    options: str


def parse_fstab(content: str) -> list[FstabEntry]:
    entries: list[FstabEntry] = []
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        cols = line.split()
        if len(cols) < 4:
            continue
        source, target, fs_type, opts = cols[:4]
        entries.append(FstabEntry(source, target.replace(r'\040', ' '), fs_type, opts))
    return entries


def scan_lsblk_json(raw: str) -> dict[str, dict]:
    """Deduplica o mesmo LV visto sob mais de um PV; preserva todos os ancestrais."""
    doc = json.loads(raw)
    nodes: dict[str, dict] = {}

    def walk(node: dict, parent: str | None = None) -> None:
        path = str(node.get('path') or '')
        if not path.startswith('/dev/'):
            return
        saved = nodes.setdefault(path, {'path': path, 'parents': set()})
        for key in ('name', 'type', 'fstype', 'uuid', 'partuuid', 'model', 'tran', 'size', 'rm', 'maj:min', 'mountpoints', 'parttype'):
            val = node.get(key)
            if val is not None and (saved.get(key) is None or saved.get(key) == ''):
                saved[key] = val
        if parent and parent != path:
            saved['parents'].add(parent)
        for child in node.get('children') or []:
            walk(child, path)

    for root in doc.get('blockdevices', []):
        walk(root)
    return nodes


def parent_disks(nodes: dict[str, dict], path: str) -> tuple[list[str], list[str]]:
    """Retorna discos ancestrais e PVs LVM associados a um nó, sem modificá-los."""
    disk_paths, pv_paths, seen = set(), set(), set()

    def visit(p: str):
        if p in seen:
            return
        seen.add(p)
        node = nodes.get(p, {})
        if node.get('type') == 'disk':
            disk_paths.add(p)
        if str(node.get('fstype') or '').lower() == 'lvm2_member':
            pv_paths.add(p)
        for ancestor in node.get('parents') or ():
            visit(ancestor)

    visit(path)
    return sorted(disk_paths), sorted(pv_paths)


def _find_for_source(nodes: dict[str, dict], source: str) -> list[str]:
    if source.startswith('UUID=') and UUID_RE.fullmatch(source[5:]):
        return [p for p, node in nodes.items() if str(node.get('uuid') or '') == source[5:]]
    if source.startswith('PARTUUID=') and UUID_RE.fullmatch(source[9:]):
        return [p for p, node in nodes.items() if str(node.get('partuuid') or '') == source[9:]]
    if source.startswith('/dev/'):
        if source in nodes:
            return [source]
        # /dev/vg/lv usa o mesmo nó que pode aparecer em lsblk como /dev/mapper/vg-lv.
        # Não adivinhar mapeamentos via substituição de '-' no nome; só reportar falta.
    return []


def build_map(fstab_text: str, lsblk_raw: str) -> tuple[str, list[str]]:
    """Relatório textual e avisos. Nunca realiza comandos ou operações de disco."""
    nodes = scan_lsblk_json(lsblk_raw)
    entries = parse_fstab(fstab_text)
    lines = [
        'WOLF RESCUE — MAPA DE MONTAGENS (SOMENTE LEITURA)',
        'Fonte: fstab selecionado e inventário lsblk atual.',
        'Comentários do fstab não são considerados identificação de dispositivo.',
        '',
    ]
    warnings = []
    roles: dict[str, str] = {}
    for mountpoint in ROLE_MOUNTS:
        candidates = [entry for entry in entries if entry.target == mountpoint]
        lines.append(f'{mountpoint} — ' + ('NENHUMA ENTRADA' if not candidates else candidates[0].source))
        if not candidates:
            if mountpoint == '/':
                warnings.append('Raiz / não definida no fstab selecionado.')
            else:
                lines.append('  Não há entrada separada para este ponto de montagem.')
            continue
        if len(candidates) != 1:
            warnings.append(f'{mountpoint}: múltiplas entradas no fstab; análise ambígua.')
            continue
        entry = candidates[0]
        matches = _find_for_source(nodes, entry.source)
        lines.append(f'  Sistema: {entry.fstype} | Opções: {entry.options}')
        if len(matches) != 1:
            warnings.append(f'{mountpoint}: UUID/dispositivo não encontrado ou ambíguo no lsblk ({entry.source}).')
            lines.append(f'  Identificação: NÃO CONFIRMADA ({len(matches)} correspondências)')
            continue
        path = matches[0]
        roles[mountpoint] = path
        node = nodes[path]
        actual_fs = str(node.get('fstype') or '')
        if actual_fs and actual_fs != entry.fstype and not (actual_fs == 'vfat' and entry.fstype in ('fat', 'fat32')):
            warnings.append(f'{mountpoint}: tipo de filesystem difere: fstab={entry.fstype}, lsblk={actual_fs}.')
        disks, pvs = parent_disks(nodes, path)
        lines.append(f'  Dispositivo encontrado: {path}')
        lines.append('  Disco(s) físico(s): ' + (', '.join(disks) if disks else 'não resolvidos'))
        if pvs:
            lines.append('  PVs LVM envolvidos: ' + ', '.join(pvs))
            if len(pvs) > 1:
                lines.append('  ATENÇÃO: volume LVM distribuído em vários PVs; preservar TODOS.')
                warnings.append(f'{mountpoint}: volume lógico depende de {len(pvs)} PVs.')
        lines.append('')

    if '/' in roles and '/boot/efi' in roles:
        root_disks, _ = parent_disks(nodes, roles['/'])
        efi_disks, _ = parent_disks(nodes, roles['/boot/efi'])
        if root_disks and efi_disks and not set(root_disks).intersection(efi_disks):
            lines.append('TOPOLOGIA MULTIDISCO: EFI e RAIZ / estão em discos diferentes.')
            warnings.append('EFI e / em SSDs diferentes: exige preflight físico e confirmação da topologia.')

    lines.extend(['', 'RESTRIÇÕES DE SEGURANÇA:',
                  '- Este mapa NÃO é plano executável e não altera discos.',
                  '- Não formatar EFI, volumes LVM ou partições Windows existentes.',
                  '- Conferir backups, efibootmgr e identificação real antes de qualquer instalação.',
                  '- Instalação física somente pelo executor específico, após revalidação UUID/LVM.'])
    if warnings:
        lines.extend(['', 'AVISOS:'] + [f'! {warning}' for warning in warnings])
    return '\n'.join(lines) + '\n', warnings
