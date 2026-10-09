#!/usr/bin/env python3
"""Troca exclusivamente textos exibidos nos bootmenus do perfil Archiso.

Preserva ids, classes GRUB, parâmetros archiso, caminhos de kernel e UUIDs.
Compatível com GRUB, Syslinux e systemd-boot/loader quando presentes.
"""
from __future__ import annotations
import argparse
import re
from pathlib import Path

CONFIG_GLOBS = (
    "grub/*.cfg", "syslinux/*.cfg", "efiboot/loader/entries/*.conf",
    "efiboot/loader/loader.conf", "loader/entries/*.conf", "loader/loader.conf",
)

# Somente os textos humanos. Não renomear identificadores técnicos archiso.
REPLACEMENTS = (
    (re.compile(r"\bArch Linux\b"), "Wolf Linux"),
    (re.compile(r"\bArchlinux\b"), "Wolf Linux"),
)


def transform(text: str) -> str:
    for pattern, replacement in REPLACEMENTS:
        text = pattern.sub(replacement, text)
    return text


def brand(profile: Path, asset_dir: Path | None = None) -> list[str]:
    changed = []
    for pattern in CONFIG_GLOBS:
        for source in sorted(profile.glob(pattern)):
            if not source.is_file():
                continue
            original = source.read_text(encoding="utf-8")
            result = transform(original)
            if result != original:
                source.write_text(result, encoding="utf-8")
                changed.append(str(source.relative_to(profile)))

    # Somente substituir o splash existente. Não criar referencia nova que um
    # bootloader possa não conseguir localizar; arquivo 800x600 do DevKit.
    if asset_dir is not None:
        splash = asset_dir / "syslinux" / "splash.png"
        existing = profile / "syslinux" / "splash.png"
        if splash.is_file() and existing.is_file():
            existing.write_bytes(splash.read_bytes())
            changed.append("syslinux/splash.png")
    return changed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("profile", type=Path)
    parser.add_argument("--assets", type=Path)
    args = parser.parse_args()
    if not args.profile.is_dir():
        parser.error("perfil Archiso inexistente")
    changed = brand(args.profile, args.assets)
    print("[OK] Branding do boot Wolf: " + (", ".join(changed) if changed else "sem rótulos Arch a alterar"))


if __name__ == "__main__":
    main()
