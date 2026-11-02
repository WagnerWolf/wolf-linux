#!/usr/bin/env python3
"""Preferências compartilhadas Wolf LXQt: MIME, Konsole, Zsh e ação VS Code.

Usado no sistema alvo (sysroot) durante instalação. Não inicia watchers.
"""
import argparse
import json
import os
import pwd
import shutil
import sys
from pathlib import Path


def set_key(filename: Path, section: str, key: str, value: str) -> None:
    """Atualiza uma chave INI sem reformatar as demais entradas."""
    filename.parent.mkdir(parents=True, exist_ok=True)
    lines = filename.read_text(encoding="utf-8").splitlines(keepends=True) if filename.exists() else []
    header = f"[{section}]"
    start = next((i for i, line in enumerate(lines) if line.strip() == header), None)
    if start is None:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        lines.extend((header + "\n", f"{key}={value}\n"))
    else:
        end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
        matches = [i for i in range(start + 1, end)
                   if lines[i].split("=", 1)[0].strip() == key and "=" in lines[i]]
        if matches:
            lines[matches[0]] = f"{key}={value}\n"
            for i in reversed(matches[1:]):
                del lines[i]
        else:
            lines.insert(end, f"{key}={value}\n")
    filename.write_text("".join(lines), encoding="utf-8")


def apply_mime(config: Path, daily: bool) -> None:
    mime = {
        "inode/directory": "pcmanfm-qt.desktop",
        "application/pdf": "org.kde.okular.desktop",
        "text/plain": "org.kde.kate.desktop",
        "text/markdown": "org.kde.kate.desktop",
        "text/x-log": "org.kde.kate.desktop",
        "text/x-readme": "org.kde.kate.desktop",
        "application/json": "org.kde.kate.desktop",
        "application/xml": "org.kde.kate.desktop",
        "text/xml": "org.kde.kate.desktop",
        "application/x-shellscript": "org.kde.kate.desktop",
        "text/x-python": "org.kde.kate.desktop",
        # Gwenview incluído na base LXQt (inclusive Minimal).
        "image/png": "org.kde.gwenview.desktop",
        "image/jpeg": "org.kde.gwenview.desktop",
        "image/webp": "org.kde.gwenview.desktop",
        "image/gif": "org.kde.gwenview.desktop",
        "image/svg+xml": "org.kde.gwenview.desktop",
        "image/bmp": "org.kde.gwenview.desktop",
        "image/x-ms-bmp": "org.kde.gwenview.desktop",
        "image/tiff": "org.kde.gwenview.desktop",
        "image/avif": "org.kde.gwenview.desktop",
        "image/heif": "org.kde.gwenview.desktop",
        "image/heic": "org.kde.gwenview.desktop",
        "image/x-xcf": "org.kde.gwenview.desktop",
    }
    if daily:
        for item in (
            "video/mp4", "video/x-matroska", "application/x-matroska", "video/webm",
            "video/mpeg", "video/quicktime", "video/x-msvideo", "video/x-ms-wmv",
            "video/x-flv", "video/ogg", "video/3gpp",
        ):
            mime[item] = "io.github.mpc_qt.mpc-qt.desktop"
        for item in (
            "audio/mpeg", "audio/mp4", "audio/aac", "audio/flac", "audio/x-flac",
            "audio/ogg", "audio/vorbis", "audio/x-vorbis+ogg", "audio/x-wav",
            "audio/wav", "audio/x-mpegurl", "audio/x-scpls", "application/xspf+xml",
            "application/vnd.apple.mpegurl",
        ):
            mime[item] = "audacious.desktop"
        mime.update({
            "application/vnd.oasis.opendocument.text": "libreoffice-writer.desktop",
            "application/vnd.oasis.opendocument.spreadsheet": "libreoffice-calc.desktop",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "libreoffice-writer.desktop",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "libreoffice-calc.desktop",
            "application/msword": "libreoffice-writer.desktop",
            "application/vnd.ms-excel": "libreoffice-calc.desktop",
            "x-scheme-handler/http": "google-chrome.desktop",
            "x-scheme-handler/https": "google-chrome.desktop",
            "text/html": "google-chrome.desktop",
        })
    for typ, desktop in mime.items():
        set_key(config, "Default Applications", typ, desktop + ";")
        # Explicitly keep player/office entries out of directory and text ownership.
        set_key(config, "Added Associations", typ, desktop + ";")
    set_key(config, "Removed Associations", "inode/directory", "io.github.mpc_qt.mpc-qt.desktop;")
    set_key(config, "Removed Associations", "text/plain", "libreoffice-writer.desktop;")


def copy_profile(source: Path, target: Path) -> None:
    if not source.is_file():
        raise RuntimeError(f"Perfil ausente: {source}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def configure_vscode_keyring(home: Path) -> Path | None:
    """Backend Secret Service, sem sobrescrever um argv.json JSONC do usuário."""
    file = home / '.vscode' / 'argv.json'
    if file.is_file():
        try:
            obj = json.loads(file.read_text(encoding='utf-8'))
        except (UnicodeError, json.JSONDecodeError):
            print(f'[AVISO] VS Code: argv.json com comentários ou inválido; preservado: {file}')
            return None
        if not isinstance(obj, dict):
            print(f'[AVISO] VS Code: argv.json inesperado; preservado: {file}')
            return None
    else:
        obj = {}
    if obj.get('password-store') == 'gnome-libsecret':
        return file
    obj['password-store'] = 'gnome-libsecret'
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return file


def configure(root: Path, user: str, assets: Path, daily: bool, development: bool, extras: bool = False) -> None:
    if not root.is_dir():
        raise RuntimeError(f"Sysroot não encontrado: {root}")
    if not user or "/" in user or user in (".", ".."):
        raise RuntimeError("Nome de usuário inválido")
    home = root / "home" / user
    if not home.is_dir():
        raise RuntimeError(f"Home do usuário ausente: {home}")
    config = home / ".config"
    config.mkdir(parents=True, exist_ok=True)

    apply_mime(config / "mimeapps.list", daily)

    konsole = home / ".local" / "share" / "konsole"
    konsole.mkdir(parents=True, exist_ok=True)
    (konsole / "WolfLinux.colorscheme").write_text("""[Background]\nColor=0,0,0\n
[BackgroundIntense]\nColor=0,0,0\n
[Foreground]\nColor=255,255,255\n
[ForegroundIntense]\nColor=255,255,255\n
[General]\nDescription=Wolf Linux - Preto e branco\nOpacity=1\n""", encoding="utf-8")
    (konsole / "Wolf Linux.profile").write_text("""[Appearance]\nColorScheme=WolfLinux\nFont=MesloLGS Nerd Font,11,-1,5,50,0,0,0,0,0\n
[General]\nName=Wolf Linux\nParent=FALLBACK/\nTerminalColumns=120\nTerminalRows=30\n
[Scrolling]\nHistoryMode=2\nHistorySize=10000\nScrollBarPosition=2\n""", encoding="utf-8")
    set_key(config / "konsolerc", "Desktop Entry", "DefaultProfile", "Wolf Linux.profile")

    if daily:
        copy_profile(assets / "zsh" / "zshrc", home / ".zshrc")
        copy_profile(assets / "zsh" / "p10k.zsh", home / ".p10k.zsh")
        copy_profile(assets / "zsh" / "fastfetch.jsonc", config / "fastfetch" / "config.jsonc")
        tty_config = config / "fastfetch" / "config-tty.jsonc"
        tty_config.write_text('''{\n  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",\n  "logo": {"type": "file-raw", "source": "/usr/share/wolf-linux/fastfetch/wolf-linux-ascii.txt"},\n  "display": {"separator": " : "},\n  "modules": ["title", "separator", "os", "host", "kernel", "uptime", "packages", "shell", "cpu", "gpu", "memory", "disk", "localip"]\n}\n''', encoding="utf-8")

    if development:
        action_dir = home / ".local" / "share" / "file-manager" / "actions"
        copy_profile(assets / "pcmanfm-qt" / "wolf-open-vscode.desktop", action_dir / "wolf-open-vscode.desktop")
        vscode_argv = configure_vscode_keyring(home)

    # Set ownership of files we create, not of arbitrary preexisting home content.
    if os.geteuid() == 0:
        passwd_file = root / "etc" / "passwd"
        uid = gid = None
        if passwd_file.exists():
            for line in passwd_file.read_text(encoding="utf-8").splitlines():
                fields = line.split(":")
                if len(fields) >= 4 and fields[0] == user:
                    uid, gid = int(fields[2]), int(fields[3])
                    break
        if uid is None:
            raise RuntimeError(f"Não encontrei {user} em {passwd_file}; não posso definir permissões")
        targets = [config / "mimeapps.list", config / "konsolerc",
                   konsole / "WolfLinux.colorscheme", konsole / "Wolf Linux.profile"]
        if daily:
            targets += [home / ".zshrc", home / ".p10k.zsh",
                        config / "fastfetch" / "config.jsonc", config / "fastfetch" / "config-tty.jsonc"]
        if development:
            targets.append(home / ".local" / "share" / "file-manager" / "actions" / "wolf-open-vscode.desktop")
            if vscode_argv is not None:
                targets.append(vscode_argv)
        for p in targets:
            os.chown(p, uid, gid)
            parent = p.parent
            while parent != home and parent != root:
                if parent.is_dir() and (parent.stat().st_uid == 0):
                    os.chown(parent, uid, gid)
                parent = parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--daily", action="store_true")
    parser.add_argument("--development", action="store_true")
    parser.add_argument("--extras", action="store_true")
    args = parser.parse_args()
    configure(args.root, args.user, args.assets, args.daily, args.development, args.extras)
    print(f"[OK] Preferências LXQt para {args.user}: MIME, Konsole, Zsh={args.daily}, VSCode={args.development}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as exc:
        print(f"[ERRO] {exc}", file=sys.stderr)
        sys.exit(1)
