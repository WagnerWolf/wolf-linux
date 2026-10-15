#!/usr/bin/env python3
"""GUI -> contrato CANÔNICO de instalação, com revalidação independente.

Não concede permissão de escrita; chama as barreiras independentes de wolf_plan.
O executor Bash realiza preflight novamente antes de operações destrutivas.
"""
from __future__ import annotations
import os
import tempfile
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import wolf_plan


class BridgeError(ValueError):
    pass


def _virt_type():
    try:
        proc = subprocess.run(['systemd-detect-virt'], capture_output=True, text=True, timeout=5)
        return proc.stdout.strip() if proc.returncode == 0 else 'none'
    except (OSError, subprocess.TimeoutExpired):
        return 'none'


def build_vm_plan(inv, choice, username, hostname, preset, keyboard, *, disks=None):
    """Pure conversion of three GUI modes into the existing VM contract."""
    if inv.illustrative:
        raise BridgeError('Dados de demonstração não podem gerar uma instalação real.')
    if inv.firmware not in ('UEFI', 'BIOS'):
        raise BridgeError('Firmware não identificado.')
    if preset not in wolf_plan.PRESETS:
        raise BridgeError('Selecione um perfil válido.')
    if not isinstance(keyboard, tuple) or len(keyboard) != 3:
        raise BridgeError('Seleção do teclado inválida.')
    if (keyboard[0], keyboard[1], keyboard[2]) not in (
        ('br', 'abnt2', ''), ('br', 'abnt2', 'thinkpad'),
        ('us', 'pc105', ''), ('pt', 'pc105', ''), ('es', 'pc105', ''),
        ('fr', 'pc105', ''), ('de', 'pc105', ''), ('it', 'pc105', ''),
    ):
        raise BridgeError('Teclado fora da lista autorizada.')
    disks = wolf_plan.inventory() if disks is None else disks
    if not disks:
        raise BridgeError('Não foi possível conferir discos e identificadores pelo lsblk.')
    keyboard_doc = dict(zip(('layout', 'model', 'variant'), keyboard))
    roles = {'root': None, 'esp': None, 'home': None}
    formats = {'root': False, 'esp': False, 'home': False}
    size = {'root_gib': 0, 'home_gib': 0}
    disk_path = ''
    home_layout = 'in-root'
    clean = False
    if choice.mode == 'erase':
        disk_path = choice.erase_disk
        home_layout = 'separate' if choice.erase_home_separate else 'in-root'
        size = {'root_gib': int(choice.erase_root_gib),
                'home_gib': int(choice.erase_home_gib or 0)}
    else:
        if choice.backup_dotfiles:
            raise BridgeError('O backup de dotfiles ainda não está disponível neste modo. Desmarque essa opção para continuar.')
        if choice.mode == 'reuse' and not choice.home:
            raise BridgeError('Reutilização requer /home separada. Selecione a partição /home ou use o modo Manual.')
        if inv.firmware == 'BIOS' and not choice.bios_disk:
            raise BridgeError('Selecione o disco do GRUB para instalações BIOS.')
        # O executor de VM atual aceita APENAS partições pertencentes ao MESMO
        # disco VirtIO. Não tentar degradar LVM/multidisco em /dev/sd*.
        root_disks = inv.disk_ancestors(choice.root)
        if len(root_disks) != 1:
            raise BridgeError('Este modo aceita uma partição raiz comum em um único disco. Volumes LVM requerem o fluxo especializado.')
        disk_path = next(iter(root_disks))
        if inv.firmware == 'BIOS' and choice.bios_disk != disk_path:
            raise BridgeError('O disco de inicialização deve ser o mesmo da raiz neste modo.')
        for path in (choice.root, choice.efi if inv.firmware == 'UEFI' else '', choice.home):
            if path and inv.disk_ancestors(path) != {disk_path}:
                raise BridgeError('Neste modo, raiz, EFI e /home precisam pertencer ao mesmo disco; não é possível misturar discos ou LVM.')
            if path and (not inv.get(path) or inv.get(path).kind != 'part'):
                raise BridgeError('Neste modo são aceitas apenas partições comuns; volumes LVM precisam do instalador especializado.')
        roles['root'] = choice.root
        roles['esp'] = choice.efi if inv.firmware == 'UEFI' else None
        roles['home'] = choice.home or None
        home_layout = 'separate' if choice.home else 'in-root'
        formats = {'root': True,
                   'esp': bool(choice.format_efi) if choice.mode == 'manual' else False,
                   'home': bool(choice.format_home) if choice.mode == 'manual' else False}
        clean = bool(choice.clean_dotfiles) if choice.mode == 'reuse' else False
    try:
        doc = wolf_plan.build_preview(disks=disks, disk_path=disk_path, mode=choice.mode,
                                     preset=preset, stacks=wolf_plan.PRESETS[preset],
                                     hostname=hostname, username=username, keyboard=keyboard_doc,
                                     boot_mode=inv.firmware, roles=roles, formats=formats,
                                     home_layout=home_layout, cleanup_home=clean, erase_sizes=size)
        wolf_plan.vm_execution_fields(doc, disks=disks, active_boot=inv.firmware, check_device=False)
    except (wolf_plan.PlanError, KeyError, ValueError, TypeError) as exc:
        raise BridgeError(str(exc)) from exc
    return doc


def _is_live_archiso() -> bool:
    return Path('/run/archiso').exists()


def check_vm_plan(doc):
    """Preflight real SOMENTE leitura, pelo executor privilegiado da ISO.

    lsblk e as regras de plano podem ser executados sem privilégio. A leitura
    de assinaturas (wipefs) e de tabelas de partição requer root. Não elevar
    o PySide6: chamar APENAS a ação --preflight-gui-plan-vm do Bash e nunca
    interpretar o seu sucesso como autorização para instalar sem novo teste.
    """
    if not _is_live_archiso():
        raise BridgeError('Execução real exige inicialização pela ISO Live Wolf/Archiso.')
    disks = wolf_plan.inventory()
    if not disks:
        raise BridgeError('Não foi possível atualizar o inventário de discos.')
    try:
        # Checagem sem escrita, antes de atravessar a fronteira de privilégios.
        wolf_plan.vm_execution_fields(doc, disks=disks,
                                      active_boot='UEFI' if Path('/sys/firmware/efi').exists() else 'BIOS',
                                      check_device=False)
        # Nome temporário privado, não um JSON reutilizável entre instalações.
        # O comando root confere novamente hardware e documento por conta própria.
        with tempfile.TemporaryDirectory(prefix='wolf-gui-preflight-') as folder:
            plan = wolf_plan.write_private(doc, Path(folder) / 'preview.json')
            proc = subprocess.run(
                ['sudo', '-n', 'wolf-install', '--preflight-gui-plan-vm', str(plan)],
                capture_output=True, text=True, timeout=35, check=False)
    except (wolf_plan.PlanError, ValueError, KeyError, OSError,
            subprocess.TimeoutExpired) as exc:
        raise BridgeError('Não foi possível completar a pré-validação: ' + str(exc)) from exc
    if proc.returncode != 0:
        output = (proc.stderr or proc.stdout).strip()
        if 'password is required' in output.lower() or 'a password is required' in output.lower():
            raise BridgeError('O preflight privilegiado não está autorizado nesta Live. Confira as permissões de sudo da ISO. Nenhum disco foi alterado.')
        raise BridgeError('Validação de segurança recusou a instalação: ' + (output[:900] or f'código {proc.returncode}'))
    return True


def write_vm_plan(doc):
    return wolf_plan.write_private(doc)
