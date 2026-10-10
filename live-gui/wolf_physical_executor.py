#!/usr/bin/env python3
"""Wolf alpha47: *barreira independente* para reutilização multidisco física.

A saída export é SOMENTE dados NUL para o Bash; não executa escritas.
Ela não habilita o JSON: execution=disabled continua obrigatório.
"""
from __future__ import annotations

import os
from pathlib import Path
import sys

import wolf_discovery as wd
import wolf_physical_rehearsal as rehearsal


class PhysicalDenied(ValueError):
    pass


def validated(doc, snap, *, physical=True, live=True):
    if physical and (not Path('/sys/firmware/efi').is_dir()):
        raise PhysicalDenied('Executor físico exige boot UEFI.')
    if live and not Path('/run/archiso/airootfs').is_dir():
        raise PhysicalDenied('Executor físico exige a Live Wolf (Archiso).')
    # Reconstrução por UUID, fstab, PARTUUID, tamanho e topologia LVM.
    wd.validate_plan(doc, snap)
    if not doc['confirmed'] or doc['acknowledge_override']:
        raise PhysicalDenied('Confirmações incompletas ou desvio do fstab recusado.')
    if rehearsal.mount_guard(snap, doc):
        raise PhysicalDenied('Há volumes protegidos montados ou /mnt está em uso.')
    topology = rehearsal.evaluate(doc)
    if any(not path.startswith('/dev/nvme') for path in topology['disks']):
        raise PhysicalDenied('Esta revisão permite somente topologia de dois NVMe físicos.')
    if len(topology['disks']) != 2 or len(topology['pvs']) != 2:
        raise PhysicalDenied('Topologia deve conter exatamente dois discos e dois PVs.')
    root = doc['roles']['root']
    esp = doc['roles']['esp']
    home = doc['roles']['home']
    for item in (root, esp, home):
        if not item['uuid'] or item['size'] <= 0:
            raise PhysicalDenied('Volume com UUID ou tamanho inválido.')
    if root['parttype'] != '0fc63daf-8483-4772-8e79-3d69d8477de4':
        raise PhysicalDenied('Raiz não possui parttype GPT Linux.')
    if esp['parttype'] != 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b':
        raise PhysicalDenied('Partição EFI não possui GUID ESP.')
    # Papel LVM não pode coincidir com um PV nem com uma partição real.
    if home['path'] in topology['pvs'] or root['path'] in topology['pvs'] or esp['path'] in topology['pvs']:
        raise PhysicalDenied('Partições de sistema coincidem com PV LVM.')
    if any((snap['devices'].get(path) or {}).get('mountpoints') for path in topology['pvs']):
        raise PhysicalDenied('Um PV está montado; interrupção preventiva.')
    return topology


def export_fields(doc, snap) -> tuple[str, ...]:
    validated(doc, snap)
    kb = doc['keyboard']
    if kb['layout'] != 'br' or kb['model'] not in ('abnt2', 'pc105') or kb['variant'] not in ('', 'abnt2', 'thinkpad'):
        raise PhysicalDenied('Perfil de teclado inesperado.')
    preset = doc['software']['preset']
    stacks = ','.join(doc['software']['stacks']) if preset == 'custom' else ''
    return (doc['roles']['root']['path'], doc['roles']['esp']['path'],
            doc['roles']['home']['path'], doc['roles']['root']['uuid'],
            doc['roles']['esp']['uuid'], doc['roles']['home']['uuid'],
            doc['identity']['hostname'], doc['identity']['username'], preset,
            stacks, kb['layout'], kb['variant'])


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[0] not in ('check', 'export'):
        print('Uso: wolf_physical_executor.py check|export plano.json', file=sys.stderr)
        return 2
    try:
        if os.geteuid() != 0:
            raise PhysicalDenied('Execute apenas com root na Live.')
        doc = wd._load_plan(argv[1])
        snap = wd.discover()
        fields = export_fields(doc, snap)
        if argv[0] == 'export':
            sys.stdout.buffer.write(('\0'.join(fields) + '\0').encode())
        else:
            print('APTO PARA CONFIRMAÇÃO HUMANA — NENHUMA ESCRITA EXECUTADA')
            print(f'FORMATARIA SOMENTE: {fields[0]} (UUID {fields[3]})')
            print(f'PRESERVARIA EFI: {fields[1]} (UUID {fields[4]})')
            print(f'PRESERVARIA /home: {fields[2]} (UUID {fields[5]})')
            print('PVs preservados: ' + ', '.join(doc['roles']['home']['lvm_pvs']))
            print('BACKUP GERAL NÃO EXIGIDO: perda dos dados da raiz será confirmada.')
        return 0
    except (ValueError, KeyError, TypeError, OSError, wd.DiscoveryError) as exc:
        print('[BLOQUEADO] ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
