#!/usr/bin/env python3
"""Contrato de PREVIEW (read-only) Wolf GUI <-> instalador Bash.

Nenhuma operação de montagem, formatação, particionamento ou instalação aqui.
O documento é intencionalmente não executável; outro modo futuro deve exigir
novo schema, nova revisão de segurança e consentimento explícito.
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

SCHEMA = "wolf.install.preview.v2"
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


def build_preview(*, disks: list[dict], disk_path: str, mode: str,
                  preset: str, stacks: tuple[str, ...], hostname: str, username: str,
                  keyboard: dict, boot_mode: str, roles: dict | None = None,
                  formats: dict | None = None, home_layout: str = "in-root") -> dict:
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
    if mode == "erase" and home_layout != "in-root":
        raise PlanError("Apagar disco inteiro usa /home dentro da raiz na implementação atual")
    if home_layout == "in-root" and (roles.get("home") is not None or formats.get("home")):
        raise PlanError("/home dentro da raiz não admite partição ou formatação própria")
    if not isinstance(roles, dict) or set(roles) != {"root", "esp", "home"}:
        raise PlanError("Papéis das partições inválidos")
    if not isinstance(formats, dict) or set(formats) != {"root", "esp", "home"} or not all(type(v) is bool for v in formats.values()):
        raise PlanError("Preferências de formatação inválidas")
    if mode == "erase" and (any(roles.values()) or any(formats.values())):
        raise PlanError("Apagar disco inteiro não admite partições ou flags individuais")
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
    if home_layout == "in-root":
        warnings.append("/home será um DIRETÓRIO dentro de /; não haverá montagem específica de /home")
        if mode == "erase" or (mode == "reuse" and formats["root"]):
            warnings.append("ATENÇÃO: formatar/apagar a raiz também elimina qualquer /home antigo armazenado nela")
    if mode == "manual":
        warnings.append("Manual VM (piloto): use GParted para CRIAR a ESP FAT32 e a raiz; a GUI montará partições selecionadas SOMENTE após confirmação no Bash. BIOS e formatação da ESP não estão habilitados.")
    if disk is None:
        warnings.append("Selecione um disco antes de revisar o plano")
    if mode == "erase":
        warnings.append("APAGAR DISCO INTEIRO: todas as partições serão excluídas; /home será criado dentro da raiz /")
        if disk and disk["removable"]:
            warnings.append("ATENÇÃO: disco marcado como removível (pode ser a mídia Live)")
    if mode in ("reuse", "manual"):
        if not roles["root"]:
            warnings.append("Partição raiz / ainda não selecionada")
        if boot_mode == "UEFI" and not roles["esp"]:
            warnings.append("UEFI detectado: selecione a partição EFI antes de uma instalação futura")
        if any(formats.values()):
            warnings.append("Formatação selecionada: a execução em VM depende de preflight específico e confirmação adicional")
    warnings.append("O JSON não autoriza execução: somente comando VM independente, com nova verificação e confirmação explícita")
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
    if set(ident) != {"hostname", "username"} or set(software) != {"preset", "stacks"} or set(storage) != {"mode", "home_layout", "disk", "partitions", "format"}:
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
                              home_layout=storage["home_layout"])
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
    if st["mode"] in ("reuse", "manual"):
        for role in ("root", "esp", "home"):
            if role == "home" and st["home_layout"] == "in-root":
                continue
            lines.append(f"{role}: {st['partitions'][role] or '(não selecionado)'} " +
                         ("[FORMATAR na execução confirmada]" if st["format"][role] else "[preservar/não formatar]"))
    lines.append("\nAVISOS:")
    lines.extend("- " + item for item in doc["warnings"])
    return "\n".join(lines)





def vm_erase_fields(doc: dict, *, disks: list[dict], active_boot: str | None = None,
                    check_device: bool = False) -> tuple[str, ...]:
    """Confere ALVO de teste VM; não atribui autorização de escrita ao JSON.

    Aceita SOMENTE disco VirtIO vazio /dev/vd[a-z] para reduzir o risco de
    escolher discos reais pass-through, USB, imagens em outros sistemas etc.
    O bash verifica também que estamos realmente em QEMU/KVM.
    """
    canonical = validate_document(doc, disks=disks)
    st = canonical["storage"]
    if st["mode"] != "erase" or st["home_layout"] != "in-root":
        raise PlanError("Execução experimental aceita somente APAGAR DISCO com /home dentro de /")
    if any(st["partitions"].values()) or any(st["format"].values()):
        raise PlanError("Papéis/formatações individuais não são permitidos no modo apagar disco")
    disk_info = st["disk"]
    if not disk_info:
        raise PlanError("Selecione o disco descartável da VM")
    disk_path = disk_info["path"]
    if not re.fullmatch(r"/dev/vd[a-z]", disk_path):
        raise PlanError("Execução VM limitada a discos VirtIO /dev/vda, /dev/vdb... (nunca discos físicos)")
    actual = next((d for d in disks if d["path"] == disk_path), None)
    if actual is None or actual["removable"] or actual["transport"].lower() == "usb":
        raise PlanError("Disco inválido, removível ou USB")
    if any(actual.get("mountpoints") or []) or any(p.get("mountpoints") for p in actual["partitions"]):
        raise PlanError("Disco ou partição encontra-se montado; desmonte antes de APAGAR")
    if actual["size"] < VM_MIN_BYTES:
        raise PlanError("Use um disco virtual de pelo menos 32 GiB")
    if not re.fullmatch(r"[0-9]+:[0-9]+", actual["maj_min"]):
        raise PlanError("Identidade MAJ:MIN do disco indisponível")
    if canonical["boot_mode"] not in ("UEFI", "BIOS"):
        raise PlanError("Modo BIOS/UEFI desconhecido")
    if active_boot is not None and canonical["boot_mode"] != active_boot:
        raise PlanError("Modo BIOS/UEFI do plano não coincide com a sessão Live")
    keyboard = canonical["keyboard"]
    if keyboard["layout"] != "br" or keyboard["variant"] not in ("", "abnt2", "thinkpad"):
        raise PlanError("A execução VM inicial suporta apenas layouts br, br(abnt2), br(thinkpad)")
    if check_device:
        target = Path(disk_path)
        if target.is_symlink() or not target.exists() or not stat.S_ISBLK(target.stat().st_mode):
            raise PlanError("Dispositivo real não é um bloco válido (ou é um symlink)")
        st_device = target.stat()
        if f"{os.major(st_device.st_rdev)}:{os.minor(st_device.st_rdev)}" != actual["maj_min"]:
            raise PlanError("Identidade kernel do disco não coincide com MAJ:MIN do plano")
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
    """Piloto manual VM: usar partições existentes, sem formatar ESP ou /home.

    A raiz escolhida SERÁ FORMATADA em ext4; a ESP deve existir em FAT32.
    Não suporta instalações físicas, BIOS, LVM, Windows ou volumes em outro disco.
    """
    canonical = validate_document(doc, disks=disks)
    storage = canonical["storage"]
    if storage["mode"] != "manual":
        raise PlanError("Esta operação exige o modo Avançado/manual")
    if canonical["boot_mode"] != "UEFI" or (active_boot and active_boot != "UEFI"):
        raise PlanError("Manual experimental habilitado apenas no boot UEFI da VM")
    disk = storage["disk"]
    if not disk or not re.fullmatch(r"/dev/vd[a-z]", disk["path"]):
        raise PlanError("Manual VM exige disco VirtIO selecionado (/dev/vda...)")
    actual = next((d for d in disks if d["path"] == disk["path"]), None)
    if not actual or actual["removable"] or actual["transport"].lower() == "usb":
        raise PlanError("Disco ausente/removível/USB")
    if actual["size"] < VM_MIN_BYTES or not re.fullmatch(r"[0-9]+:[0-9]+", actual["maj_min"]):
        raise PlanError("Disco pequeno demais ou identidade do kernel desconhecida")
    root, esp, home = (storage["partitions"][k] for k in ("root", "esp", "home"))
    fmt = storage["format"]
    if not root or not esp or not fmt["root"] or fmt["esp"] or fmt["home"]:
        raise PlanError("Manual VM exige / selecionada PARA FORMATAR; ESP obrigatória PRESERVADA; /home não pode ser formatada")
    if storage["home_layout"] == "separate" and not home:
        raise PlanError("Escolha uma partição /home ou use /home dentro de /")
    part_by_path = {p["path"]: p for p in actual["partitions"]}
    if root not in part_by_path or esp not in part_by_path or (home and home not in part_by_path):
        raise PlanError("Partição selecionada não existe mais no disco")
    root_part, esp_part = part_by_path[root], part_by_path[esp]
    if root_part["size"] < 20 * 1024**3:
        raise PlanError("A raiz / precisa de pelo menos 20 GiB no piloto manual")
    if root_part["fstype"].lower() not in ("", "ext4"):
        raise PlanError("Raiz manual VM deve estar vazia ou ser ext4 (será formatada)")
    if esp_part["size"] < 512 * 1024**2 or esp_part["fstype"].lower() not in ("vfat", "fat32", "fat"):
        raise PlanError("ESP existente precisa ser FAT32 e ter pelo menos 512 MiB; formate no GParted ANTES")
    if esp_part.get("parttype", "").lower() != "c12a7328-f81f-11d2-ba4b-00a0c93ec93b":
        raise PlanError("ESP deve ter o tipo GPT EFI System (flag esp no GParted). Configure a flag esp antes de instalar")
    if home and part_by_path[home]["fstype"].lower() != "ext4":
        raise PlanError("/home separada deve ser ext4, criada previamente no GParted (será PRESERVADA)")
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
    if kb["layout"] != "br" or kb["variant"] not in ("", "abnt2", "thinkpad"):
        raise PlanError("Layout do teclado ainda não suportado no executor experimental")
    return (disk["path"], str(actual["size"]), actual["maj_min"], "UEFI",
            canonical["identity"]["hostname"], canonical["identity"]["username"],
            canonical["software"]["preset"], ",".join(canonical["software"]["stacks"]),
            kb["layout"], kb["variant"], "manual", root, esp, home or "")


def vm_execution_fields(doc: dict, *, disks: list[dict], active_boot: str | None = None,
                        check_device: bool = False) -> tuple[str, ...]:
    if doc.get("storage", {}).get("mode") == "manual":
        return vm_manual_fields(doc, disks=disks, active_boot=active_boot, check_device=check_device)
    base = vm_erase_fields(doc, disks=disks, active_boot=active_boot, check_device=check_device)
    return (*base, "erase", "", "", "")

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
            issues.append("Instalação BIOS necessita confirmação separada do disco de destino do GRUB")
        parts = {p["path"]: p for d in disks for p in d["partitions"]}
        if roles["esp"] and not fmts["esp"] and parts[roles["esp"]]["fstype"].lower() not in ("vfat", "fat32", "fat"):
            issues.append("EFI preservada precisa ter sistema de arquivos FAT/vfat")
    if mode == "manual":
        if not roles["root"] or not roles["esp"] or not fmts["root"] or fmts["esp"] or fmts["home"]:
            issues.append("Piloto manual UEFI: raiz formatada, ESP FAT32 preservada, /home separada ext4 preservada (opcional)")
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
                  "3. Apagar TODAS as partições existentes e criar raiz ext4; em UEFI criar ESP FAT32",
                  "4. /home será um diretório DENTRO da raiz / (não será criada partição /home)"]
    elif mode == "reuse":
        lines += ["1. O modo Bash correspondente seria: reuse-manual",
                  "2. Raiz /: " + (roles["root"] or "NÃO SELECIONADA") + " (Bash formata como ext4)",
                  "3. EFI: " + (roles["esp"] or "nenhuma") + " (preservar; montar em /boot/efi)",
                  "4. /home: " + (roles["home"] if st["home_layout"] == "separate" and roles["home"] else "diretório dentro de /"),
                  "5. Aplicar stacks e identidade somente após confirmação de instalação futura"]
    else:
        lines += ["1. O modo Bash correspondente seria: manual",
                  "2. Prepare partições no GParted ANTES, selecione raiz e EFI FAT32",
                  "3. No piloto VM, o Bash formatará e montará apenas a raiz /; ESP e /home serão PRESERVADAS",
                  "4. Partições serão montadas em /mnt, /mnt/boot/efi e /mnt/home conforme a escolha"]
    lines += ["", "INTEGRIDADE DO PLANO: OK (comparado a lsblk atual)"]
    if issues:
        lines += ["ESTADO: INCOMPLETO / AINDA NÃO SUPORTADO", *["BLOQUEIO: " + m for m in issues]]
    else:
        lines += ["ESTADO: COMPATÍVEL COM O PLANEJADOR BASH CONHECIDO (execução não habilitada)"]
    lines += ["", "Esta simulação não inicia a rotina main do instalador."]
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
                print("[OK] Plano de instalação VM validado (ainda SEM escrever no disco).")
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
