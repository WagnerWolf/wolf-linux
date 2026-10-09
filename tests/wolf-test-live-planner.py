#!/usr/bin/env python3
"""Contract tests for GUI read-only planner and boot branding, without Qt."""
from __future__ import annotations
import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def load(name: str, source: Path):
    spec = importlib.util.spec_from_file_location(name, source)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module

ui = load("wolf_gui", ROOT / "live-gui/main.py")
boot = load("wolf_boot", ROOT / "tests/wolf-brand-live-boot.py")

ui.self_test()
assert len(ui.disk_inventory('{"blockdevices":[{"type":"disk","path":"/dev/nvme0n1",'
                             '"size":20000000000,"children":[{"type":"part",'
                             '"path":"/dev/nvme0n1p1","size":1000000000}]},'
                             '{"type":"loop","path":"/dev/loop0"}]}')) == 1
for v in ("evil,foo", "/dev/not-inventory"):
    try:
        ui.build_summary(v, "erase", (), "wolf", "wolf", {"/dev/sda"})
    except ValueError:
        pass
    else:
        raise AssertionError("not-inventory disk was accepted")

with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    (p / "grub").mkdir()
    (p / "syslinux").mkdir()
    (p / "efiboot/loader/entries").mkdir(parents=True)
    (p / "grub/grub.cfg").write_text('menuentry "Arch Linux install medium" --id archlinux {\n'
                                     ' linux /arch/boot/vmlinuz-linux archisobasedir=arch\n}\n')
    (p / "syslinux/archiso_sys.cfg").write_text('MENU LABEL Arch Linux install medium\n'
                                                 'APPEND archisobasedir=%INSTALL_DIR% archisolabel=%ARCHISO_LABEL%\n')
    (p / "efiboot/loader/entries/archiso-x86_64.conf").write_text('title Arch Linux install medium\n'
                                                                 'options archisolabel=%ARCHISO_LABEL%\n')
    original = (p / "grub/grub.cfg").read_text()
    changed = boot.brand(p)
    assert len(changed) == 3, changed
    assert 'Wolf Linux install medium' in (p / "grub/grub.cfg").read_text()
    assert '--id archlinux' in (p / "grub/grub.cfg").read_text()
    assert 'archisobasedir=arch' in (p / "grub/grub.cfg").read_text()
    assert 'archisolabel=%ARCHISO_LABEL%' in (p / "syslinux/archiso_sys.cfg").read_text()
    assert 'title Wolf Linux' in (p / "efiboot/loader/entries/archiso-x86_64.conf").read_text()
    assert boot.brand(p) == []  # idempotent
    assert (p / "grub/grub.cfg").read_text() != original
print("[OK] GUI planner: inventário real, entradas inválidas e pré-plano read-only")
print("[OK] Boot: GRUB, Syslinux e loader, preservando IDs/parâmetros e idempotência")
