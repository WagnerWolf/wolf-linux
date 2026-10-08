#!/usr/bin/env python3
"""Remove o Discover APENAS da lista de launchers dos layouts padrão Plasma.

Executado uma única vez durante a instalação, sem autostart ou watcher.
"""
from pathlib import Path
import re
import sys

# Só valores literais dentro de arrays launchers/launcherUrls.
DISCOVER_URL = re.compile(
    r"(?P<quote>['\"])(?:applications:)?(?:org\.kde\.)?discover\.desktop(?P=quote)",
    re.IGNORECASE,
)
LAUNCHER_ARRAY = re.compile(r"\b(?:launchers|launcherUrls)['\"]?\s*[,=:]\s*\[(?P<items>[^\]]*)\]", re.DOTALL)


def prune_layout(text: str) -> str:
    def replace_array(match: re.Match) -> str:
        items = match.group('items')
        previous = None
        while items != previous:
            previous = items
            # Preserve the rest of the array and all other launcher values.
            items = re.sub(r",\s*" + DISCOVER_URL.pattern, "", items, flags=re.IGNORECASE)
            items = re.sub(DISCOVER_URL.pattern + r"\s*,?\s*", "", items, flags=re.IGNORECASE)
        return match.group(0).replace(match.group('items'), items, 1)
    return LAUNCHER_ARRAY.sub(replace_array, text)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Uso: {sys.argv[0]} /mnt", file=sys.stderr)
        return 2
    root = Path(sys.argv[1])
    if not root.is_dir():
        print(f"[ERRO] Raiz inexistente: {root}", file=sys.stderr)
        return 1
    plasma = root / 'usr/share/plasma'
    count = 0
    if plasma.exists():
        for file in sorted(plasma.rglob('*.js')):
            if 'layout' not in file.name.lower() and 'layout' not in str(file.parent).lower():
                continue
            data = file.read_text(encoding='utf-8')
            result = prune_layout(data)
            if result != data:
                file.write_text(result, encoding='utf-8')
                print(f"[OK] Discover removido do layout: {file.relative_to(root)}")
                count += 1
    print(f"[OK] Layout(s) ajustado(s): {count}; sem autostart Wolf.")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
