#!/usr/bin/env python3
"""Wolf Control Center: helpers and read-only diagnostics without Qt dependency."""
from __future__ import annotations

from pathlib import Path
import os
import shutil
import subprocess

VERSION = "0.1.2"
HELPERS_DIR = Path("/usr/local/lib/wolf-linux/helpers")
HELPER_NAMES = {
    "monitor": "experimental/wolf-plasma-multimonitor-0.3.sh",
    "branding": "experimental/wolf-plasma-branding-0.2.sh",
    "gamepad": "stable/wolf-gamepad-setup-0.3.sh",
    "grub": "stable/wolf-grub-manager-0.3.sh",
}
NOTIFIER_BIN = Path("/usr/bin/octopi-notifier")
AUTOSTART_NAME = "octopi-notifier.desktop"
AUTOSTART_TEXT = """[Desktop Entry]
Type=Application
Name=Octopi Notifier
Comment=Avisos de atualizações de pacotes
Exec=/usr/bin/octopi-notifier
TryExec=/usr/bin/octopi-notifier
Icon=octopi
Terminal=false
OnlyShowIn=KDE;
Hidden=false
X-KDE-autostart-phase=2
X-Wolf-Control-Center=true
"""


def helper_file(key: str, root: Path = HELPERS_DIR) -> Path:
    if key not in HELPER_NAMES:
        raise ValueError(f"Helper desconhecido: {key}")
    return root / HELPER_NAMES[key]


def command_output(args: list[str], timeout: int = 7) -> tuple[int, str]:
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, str(exc)
    data = (p.stdout + ("\n" if p.stdout and p.stderr else "") + p.stderr).strip()
    return p.returncode, data


def program_exists(name: str) -> bool:
    return shutil.which(name) is not None


def user_autostart(home: Path | None = None) -> Path:
    base = home if home is not None else Path.home()
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", str(base / ".config"))) if home is None else base / ".config"
    return config_home / "autostart" / AUTOSTART_NAME


def notifier_installed(binary: Path = NOTIFIER_BIN) -> bool:
    return binary.is_file() and os.access(binary, os.X_OK)


def notifier_status(home: Path | None = None, binary: Path = NOTIFIER_BIN) -> str:
    if not notifier_installed(binary):
        return "Octopi Notifier não instalado"
    user_file = user_autostart(home)
    system_file = Path("/etc/xdg/autostart") / AUTOSTART_NAME
    if user_file.is_file():
        text = user_file.read_text(encoding="utf-8", errors="replace")
        if any(line.strip() in ("Hidden=true", "X-GNOME-Autostart-enabled=false")
               for line in text.splitlines()):
            config = "Autostart desativado neste usuário"
        else:
            config = "Autostart do usuário configurado"
    elif system_file.is_file():
        config = "Autostart global configurado"
    else:
        config = "Autostart ainda não configurado"
    # Consulta sob demanda, nunca cria watcher nem atualizador automático.
    if home is None:
        result, _ = command_output(["pgrep", "-u", str(os.getuid()), "-x", "octopi-notifier"], 2)
        config += " | processo: " + ("em execução" if result == 0 else "não detectado")
    return config


def _save_previous_autostart(target: Path, new_text: str) -> None:
    if target.is_file() and target.read_text(encoding="utf-8") != new_text:
        backup = target.with_suffix(target.suffix + ".wolf-backup")
        if not backup.exists():
            shutil.copy2(target, backup)


def enable_notifier(home: Path | None = None, binary: Path = NOTIFIER_BIN) -> Path:
    if not notifier_installed(binary):
        raise RuntimeError("Octopi Notifier não encontrado. Instale o Octopi antes de ativar.")
    target = user_autostart(home)
    target.parent.mkdir(parents=True, exist_ok=True)
    _save_previous_autostart(target, AUTOSTART_TEXT)
    target.write_text(AUTOSTART_TEXT, encoding="utf-8")
    return target


def disable_notifier(home: Path | None = None, binary: Path = NOTIFIER_BIN) -> Path:
    if not notifier_installed(binary):
        raise RuntimeError("Octopi Notifier não instalado.")
    target = user_autostart(home)
    target.parent.mkdir(parents=True, exist_ok=True)
    disabled = AUTOSTART_TEXT.replace("Hidden=false", "Hidden=true")
    _save_previous_autostart(target, disabled)
    target.write_text(disabled, encoding="utf-8")
    # Não mata um processo em execução; terá efeito no próximo login.
    return target


def autosuggestions_status(home: Path | None = None, plugin: Path = Path("/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh")) -> str:
    base = home if home is not None else Path.home()
    if not plugin.is_file():
        return "Plugin ausente: sudo pacman -S zsh-autosuggestions"
    rc = base / ".zshrc"
    if not rc.is_file() or "zsh-autosuggestions.zsh" not in rc.read_text(encoding="utf-8", errors="replace"):
        return "Plugin instalado; falta carregá-lo no ~/.zshrc"
    return "Plugin instalado e carregamento configurado"


def autosuggestions_runtime_status() -> str:
    """Verifica uma nova sessão Zsh; não é uma inspeção do Konsole já aberto."""
    if not program_exists("zsh"):
        return "Zsh indisponível"
    script = ('print -r -- "WOLF_ZSH_DIAG:${+functions[_zsh_autosuggest_start]}:'
              '${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-unset}"')
    # Evita Fastfetch durante o teste; nada é escrito em .zshrc ou histórico.
    try:
        env = os.environ.copy()
        env["WOLF_FASTFETCH"] = "0"
        proc = subprocess.run(["zsh", "-ic", script], capture_output=True,
                              text=True, timeout=6, check=False, env=env)
        diag = next((line.split("WOLF_ZSH_DIAG:", 1)[1] for line in proc.stdout.splitlines()
                     if "WOLF_ZSH_DIAG:" in line), None)
        if diag is None:
            return "Não foi possível confirmar carregamento em nova sessão interativa"
        loaded, _, color = diag.partition(":")
        return f"Nova sessão Zsh: {'plugin ativo' if loaded == '1' else 'plugin não ativo'}; cor: {color}"
    except (OSError, subprocess.TimeoutExpired):
        return "Não foi possível testar uma nova sessão Zsh"


def status_text() -> str:
    lines = ["Wolf Control Center", f"Versão: {VERSION}",
             f"Sessão: {os.environ.get('XDG_SESSION_TYPE', '?')} | Desktop: {os.environ.get('XDG_CURRENT_DESKTOP', '?')}"]
    for key, name in [("monitor", "MultiMonitor"), ("branding", "Branding"), ("gamepad", "Gamepad"), ("grub", "GRUB Manager")]:
        path = helper_file(key)
        lines.append(f"{name}: {'disponível' if path.is_file() and os.access(path, os.X_OK) else 'não encontrado'}")
    lines.append("Octopi: " + notifier_status())
    lines.append("Zsh: " + autosuggestions_status())
    lines.append("Zsh runtime: " + autosuggestions_runtime_status())
    marker = Path.home() / ".local/state/wolf-linux/first-login-plasma/completed"
    lines.append("Configuração inicial do Plasma: " + ("concluída" if marker.is_file() else "não marcada como concluída"))
    return "\n".join(lines)


if __name__ == "__main__":
    print(status_text())
