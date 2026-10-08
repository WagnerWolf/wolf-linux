#!/usr/bin/env python3
"""Wolf Linux alpha13: declarative, one-shot Plasma user profile for installed sysroot.

Run from live installer after pacstrap; no background daemons or watchers.
Create a self-removing per-user autostart for initial Plasma configuration.
"""
import argparse
import os
import pwd
import shutil
import sys
from pathlib import Path


def set_key(filename: Path, section: str, key: str, value: str) -> None:
    """Upsert a KDE INI key without reformatting the rest of the file."""
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
        "inode/directory": "org.kde.dolphin.desktop",
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
        # Gwenview no KDE baseline (inclui instalações Minimal).
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

    kwinrc = config / "kwinrc"
    set_key(kwinrc, "TabBox", "MultiScreenMode", "1")  # filter by screen under pointer
    set_key(kwinrc, "Windows", "Placement", "UnderMouse")
    set_key(kwinrc, "Windows", "ActiveMouseScreen", "true")
    mouse = config / "kcminputrc"
    set_key(mouse, "Libinput][Defaults", "PointerAccelerationProfile", "1")  # libinput flat
    set_key(mouse, "Mouse", "XLbInptAccelProfileFlat", "true")
    set_key(mouse, "Mouse", "X11LibInputXAccelProfileFlat", "true")
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

    # User-specific first login, never a global/system-wide login action.
    autostart = config / "autostart" / "wolf-first-login-plasma.desktop"
    autostart.parent.mkdir(parents=True, exist_ok=True)
    autostart.write_text("""[Desktop Entry]
Type=Application
Name=Wolf Linux — Configuração inicial do Plasma
Comment=Aplica uma única vez o Branding e o MultiMonitor
Exec=/usr/local/bin/wolf-first-login-plasma
TryExec=/usr/local/bin/wolf-first-login-plasma
OnlyShowIn=KDE;
Terminal=false
X-KDE-autostart-phase=2
""", encoding="utf-8")

    octopi_autostart = config / "autostart" / "octopi-notifier.desktop"
    if extras and (root / "usr/bin/octopi-notifier").is_file():
        octopi_autostart.write_text("""[Desktop Entry]
Type=Application
Name=Octopi Notifier
Comment=Avisos de atualizações no Plasma
Exec=/usr/bin/octopi-notifier
TryExec=/usr/bin/octopi-notifier
Icon=octopi
Terminal=false
OnlyShowIn=KDE;
Hidden=false
X-KDE-autostart-phase=2
""", encoding="utf-8")
    elif extras:
        print("[AVISO] Octopi Notifier indisponível; autostart não criado.", file=sys.stderr)

    if development:
        service_dir = home / ".local" / "share" / "kio" / "servicemenus"
        copy_profile(assets / "kde" / "wolf-open-vscode.desktop", service_dir / "wolf-open-vscode.desktop")
        (service_dir / "wolf-open-vscode.desktop").chmod(0o755)

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
        targets = [kwinrc, mouse, config / "mimeapps.list", config / "konsolerc", autostart,
                   konsole / "WolfLinux.colorscheme", konsole / "Wolf Linux.profile"]
        if daily:
            targets += [home / ".zshrc", home / ".p10k.zsh",
                        config / "fastfetch" / "config.jsonc", config / "fastfetch" / "config-tty.jsonc"]
        if development:
            targets.append(home / ".local" / "share" / "kio" / "servicemenus" / "wolf-open-vscode.desktop")
        if octopi_autostart.is_file() and extras:
            targets.append(octopi_autostart)
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
    print(f"[OK] Preferências Plasma aplicadas a {args.user}: KWin, mouse, MIME, Konsole, Zsh={args.daily}, VSCode={args.development}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as exc:
        print(f"[ERRO] {exc}", file=sys.stderr)
        sys.exit(1)
