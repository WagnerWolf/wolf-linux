#!/usr/bin/env python3
"""Ensaio físico, SEM ESCRITA: um relatório sobre o contrato multidisco.

Não carrega/sourça funções Bash de instalação. Lê apenas a lista de `stage`
do main() e imprime intenções; rejeita etapas inesperadas para evitar divergência
silenciosa entre o ensaio e o executor. NÃO homologa sucesso de pacstrap/GRUB.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import sys

import wolf_discovery as wd

# Funcionalidade suportada nesta revisão: UEFI, raiz ext4 em uma unidade,
# ESP FAT32 noutra e /home em LV com >=2 PVs. Nenhuma execução física aqui.
STAGE_LABELS = {
    '10-preparar-disco': 'Verificaria reutilização de partições; NÃO recriaria tabela GPT nem alteraria PVs.',
    '20-formatar-montar': 'Formataria SOMENTE {root} em ext4; montaria em /mnt; montaria ESP {esp} em /mnt/boot/efi SEM FORMATAR e {home} em /mnt/home SEM FORMATAR.',
    '22-limpar-home': 'Se o usuário selecionar entradas ocultas, validaria lista e backup opcional antes da exclusão; /home LVM preservada.',
    '25-repositorios-live': 'Prepararia os repositórios da Live para o pacstrap (sem alterar discos neste ensaio).',
    '27-validar-pacotes': 'Validaria disponibilidade das listas de pacotes e grupos (não consultada/executada aqui).',
    '30-pacstrap': 'Instalaria os pacotes base, KDE Plasma/Wayland, kernel linux-zen e dependências em /mnt via pacstrap -K (NÃO TESTADO aqui).',
    '40-fstab': 'Geraria /mnt/etc/fstab por UUID, raiz {root}, ESP {esp}, /home {home}, com genfstab -U.',
    '50-multilib': 'Habilitaria multilib no sistema alvo.',
    '55-completar-pacotes-base': 'Completaria pacotes base e componentes do sistema no chroot.',
    '60-sistema-base': 'Configuraria locale pt_BR, fuso America/Santarem, teclado e hostname.',
    '61-identidade-wolf': 'Aplicaria a identidade visual do Wolf Linux no alvo.',
    '62-usuario-sudo': 'Criaria/configuraria a conta {username}, sudo e UID/GID da /home preservada; testaria escrita real.',
    '63-chaotic-aur': 'Configuraria Chaotic-AUR no alvo quando existirem stacks opcionais.',
    '64-resolver-stacks': 'Instalaria stacks na ordem Arch oficial -> Chaotic-AUR -> AUR fallback.',
    '67-servicos': 'Ativaria serviços do sistema (sem iniciar serviços do alvo neste ensaio).',
    '68-android-flutter': 'Instalaria Android/Flutter apenas se selecionados; caso contrário a rotina ignora a stack.',
    '69-video': 'Selecionaria e instalaria o driver de vídeo de acordo com a GPU detectada.',
    '69b-validar-video': 'Validaria os componentes gráficos do alvo após instalação.',
    '69c-branding-boot': 'Aplicaria branding Wolf e geraria initramfs quando necessário.',
    '69c2-painel-sem-discover': 'Aplicaria layout do painel Plasma sem Discover.',
    '69c3-preferencias-kde': 'Aplicaria preferências KDE do perfil selecionado.',
    '69d-helpers-primeiro-login': 'Instalaria helpers first-login para execução no primeiro acesso.',
    '69e-grub-manager': 'Disponibilizaria Wolf GRUB Manager no sistema alvo.',
    '70-bootloader': 'Instalaria GRUB UEFI com --bootloader-id=WolfLinux em ESP {esp}, criaria grub.cfg; preservaria EFI/Microsoft e EFI/GRUB, sem fallback removível. No executor físico protegido: --no-nvram para preservar BootOrder.',
    '72-validar-boot': 'Procuraria kernel, initramfs, grub.cfg e carregador UEFI WolfLinux no alvo (NÃO TESTADO).',
    '80-finalizar': 'Concluiria instalação e limparia montagens/checkpoints do alvo (NÃO EXECUTADO).',
}

class RehearsalDenied(ValueError):
    pass


def stage_names(install_script: str) -> list[str]:
    match = re.search(r'^main\(\)\s*\{\s*\n(?P<body>.*?)^\}', install_script, re.M | re.S)
    if not match:
        raise RehearsalDenied('Não foi possível identificar main() do instalador. Ensaio interrompido.')
    stages = re.findall(r'^\s*stage\s+"([^"]+)"\s+\w+', match['body'], re.M)
    if not stages or len(stages) != len(set(stages)) or set(stages) != set(STAGE_LABELS):
        missing = sorted(set(stages) - set(STAGE_LABELS))
        obsolete = sorted(set(STAGE_LABELS) - set(stages))
        raise RehearsalDenied(f'Divergência de etapas Bash/ensaio. Novas: {missing}. Ausentes: {obsolete}. Não homologar.')
    return stages


def evaluate(doc: dict, *, mounts: bool = False) -> dict:
    """Barreira pura, adicional à validação por UUID/fstab em wolf_discovery."""
    roles = doc['roles']
    root, esp, home = (roles[k] for k in ('root', 'esp', 'home'))
    if doc['boot_mode'] != 'UEFI' or not all((root, esp, home)):
        raise RehearsalDenied('Este ensaio físico exige UEFI com raiz, EFI e /home dedicada.')
    if doc['acknowledge_override']:
        raise RehearsalDenied('Este ensaio não autoriza divergências manuais em relação ao fstab existente.')
    if doc['actions'] != {'root': 'format_ext4', 'esp': 'preserve', 'home': 'preserve'}:
        raise RehearsalDenied('Ações do plano incompatíveis com preservação de EFI e /home.')
    if root['type'] != 'part' or root['fstype'] != 'ext4' or esp['type'] != 'part' or esp['fstype'] != 'vfat':
        raise RehearsalDenied('Raiz deve ser partição ext4 e EFI deve ser partição vfat.')
    if home['type'] != 'lvm' or home['fstype'] != 'ext4':
        raise RehearsalDenied('/home deste ensaio exige LV LVM ext4.')
    if len(root['parent_disks']) != 1 or len(esp['parent_disks']) != 1 or root['parent_disks'] == esp['parent_disks']:
        raise RehearsalDenied('Este ensaio exige ESP e raiz em unidades físicas diferentes.')
    if len(home['lvm_pvs']) < 2 or not set(root['parent_disks'] + esp['parent_disks']).issubset(set(home['parent_disks'])):
        raise RehearsalDenied('Não confirmou /home LVM utilizando PVs dos dois discos.')
    if any(d.get('usb_ancestor') for d in (root, esp, home)):
        # usb_ancestor faz parte do inventário live, não das identidades no JSON.
        raise RehearsalDenied('Dispositivo USB recusado.')
    if mounts:
        raise RehearsalDenied('Uma partição/LV envolvido está montado, ou /mnt ocupado. Desmonte antes de avaliar prontidão.')
    return {'root': root['path'], 'esp': esp['path'], 'home': home['path'],
            'pvs': tuple(sorted(home['lvm_pvs'])), 'disks': tuple(sorted(home['parent_disks'])),
            'username': doc['identity']['username']}


def mount_guard(snapshot: dict, doc: dict) -> bool:
    devices = snapshot.get('devices', {})
    paths = {doc['roles'][r]['path'] for r in ('root', 'esp', 'home')}
    paths.update(doc['roles']['home']['lvm_pvs'])
    for path in paths:
        mps = (devices.get(path, {}).get('mountpoints') or [])
        if any(isinstance(p, str) and p.strip() for p in mps):
            return True
    return Path('/mnt').is_mount()


def report(doc: dict, stages: list[str], *, mounts: bool = False) -> str:
    a = evaluate(doc, mounts=mounts)
    lines = [
        'WOLF LINUX — ENSAIO FÍSICO INTEGRAL — 100% SEM EXECUÇÃO',
        'STATUS: PLANO REVALIDADO / EXECUÇÃO FÍSICA CONTINUA BLOQUEADA',
        'ATENÇÃO: Nenhum comando de instalação, fsck, mkfs, mount rw, pacstrap, chroot, GRUB ou alteração NVRAM foi executado.',
        'Verificações: contrato JSON, origem fstab, UUID, PARTUUID, tamanho, dispositivos e LVM via inventário atual.',
        '',
        f'RAIZ (única operação destrutiva hipotética): {a["root"]}',
        f'EFI A PRESERVAR: {a["esp"]}',
        f'/home LVM A PRESERVAR: {a["home"]}',
        'PVs A PRESERVAR: ' + ', '.join(a['pvs']),
        'Discos relacionados: ' + ', '.join(a['disks']),
        f'Perfil: {doc["software"]["preset"]} | stacks: {", ".join(doc["software"]["stacks"]) or "nenhuma"}',
        f'Usuário: {a["username"]} | hostname: {doc["identity"]["hostname"]}',
        '',
        'ROTEIRO DO BASH REAL — CADA ETAPA ABAIXO É APENAS DESCRITA:',
    ]
    for stage in stages:
        if stage in ('63-chaotic-aur', '64-resolver-stacks') and not doc['software']['stacks']:
            lines.append(f'[NÃO APLICÁVEL] {stage}: Minimal não solicita stacks opcionais.')
            continue
        description = STAGE_LABELS[stage].format(**a)
        lines.append(f'[NÃO EXECUTADO] {stage}: {description}')
    lines.extend([
        '', 'NÃO EXECUTADO: formatação da raiz, pacotes, /etc/fstab novo, montagem rw, configuração no chroot e GRUB.',
        'NÃO VALIDADO POR ESTE ENSAIO: integridade do backup, rede/mirrors em instalação, sucesso de pacstrap,',
        '  comportamento NVRAM/UEFI do GRUB e boot físico pós-reinstalação.',
        'PROTEÇÃO: preservar EFI Microsoft/GRUB, todos os PVs e /home, salvo itens ocultos explicitamente selecionados.',
        'ANTES DE QUALQUER INSTALAÇÃO REAL: recomendamos backup externo. Sem backup geral: aceite explícito de perda da raiz e risco residual.',
        'RESULTADO: ENSAIO DE PLANO APROVADO; NÃO EQUIVALE A INSTALAÇÃO FÍSICA HOMOLOGADA.',
    ])
    return '\n'.join(lines) + '\n'


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print('Uso: wolf-install --rehearse-multidisk-physical plano.json', file=sys.stderr)
        return 2
    try:
        if os.geteuid() != 0:
            raise RehearsalDenied('Execute como root na Live Wolf.')
        if not Path('/run/archiso/airootfs').is_dir():
            raise RehearsalDenied('Ensaio requer a ISO Live Wolf/Archiso, não o sistema instalado.')
        project = Path(__file__).resolve().parents[1]
        stages = stage_names((project/'install/wolf-install.sh').read_text(encoding='utf-8'))
        snap = wd.discover()
        doc = wd.validate_plan(wd._load_plan(argv[0]), snap)
        # Reusa o dispositivo certificado pelo scan, não o caminho editado no JSON.
        blocked = mount_guard(snap, doc)
        print(report(doc, stages, mounts=blocked), end='')
        return 0
    except (RehearsalDenied, wd.DiscoveryError, OSError, ValueError, KeyError, TypeError) as exc:
        print('[ENSAIO FÍSICO BLOQUEADO] ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
