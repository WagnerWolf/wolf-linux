#!/usr/bin/env python3
"""Wolf Linux profile tests; no Archiso, Plasma or network required."""
from pathlib import Path
from tempfile import TemporaryDirectory
import runpy
import sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
configure = runpy.run_path(str(HERE / "wolf-configure-user-defaults.py"))["configure"]


def fake_root(path: Path) -> Path:
    (path / "etc").mkdir()
    (path / "etc" / "passwd").write_text("wolf:x:1000:1000:Wolf:/home/wolf:/usr/bin/zsh\n", encoding="utf-8")
    home = path / "home" / "wolf"
    home.mkdir(parents=True)
    return home


def check_expected(home: Path, relative: str, needles: list[str]) -> None:
    text = (home / relative).read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise AssertionError(f"Faltou {needle!r} em {relative}")


def main() -> None:
    with TemporaryDirectory() as tmp:
        root = Path(tmp)
        home = fake_root(root)
        (home / ".config").mkdir()
        (root / "usr/bin").mkdir(parents=True)
        (home / ".config" / "kwinrc").write_text("[Windows]\nMyOwnValue=yes\n", encoding="utf-8")
        configure(root, "wolf", PROJECT / "assets", True, True, True)
        check_expected(home, ".config/kwinrc", ["MyOwnValue=yes"])
        assert "MultiScreenMode" not in (home / ".config/kwinrc").read_text(), "KWin não deve ser configurado no LXQt"
        assert not (home / ".config/kcminputrc").exists(), "Não gerar preferências KDE de mouse no LXQt"
        check_expected(home, ".config/mimeapps.list", [
            "inode/directory=pcmanfm-qt.desktop;",
            "video/mp4=io.github.mpc_qt.mpc-qt.desktop;",
            "audio/mpeg=audacious.desktop;",
            "text/plain=org.kde.kate.desktop;",
            "text/markdown=org.kde.kate.desktop;",
            "image/png=org.kde.gwenview.desktop;",
            "image/jpeg=org.kde.gwenview.desktop;",
            "image/webp=org.kde.gwenview.desktop;",
            "image/svg+xml=org.kde.gwenview.desktop;",
            "image/gif=org.kde.gwenview.desktop;",
            "image/tiff=org.kde.gwenview.desktop;",
            "application/pdf=org.kde.okular.desktop;",
            "io.github.mpc_qt.mpc-qt.desktop;",
        ])
        check_expected(home, ".local/share/konsole/Wolf Linux.profile", ["MesloLGS Nerd Font", "HistorySize=10000", "TerminalColumns=120", "TerminalRows=30"])
        assert not (home / ".config/autostart/wolf-first-login-plasma.desktop").exists(), "Autostart Plasma inesperado no LXQt"
        check_expected(home, ".local/share/file-manager/actions/wolf-open-vscode.desktop", ["MimeTypes=inode/directory", "Exec=wolf-open-vscode-monitor %f"])
        check_expected(home, ".vscode/argv.json", ['"password-store": "gnome-libsecret"'])
        check_expected(home, ".zshrc", ["powerlevel10k.zsh-theme", "oh-my-zsh.sh"])
        assert not (home / ".config/autostart/octopi-notifier.desktop").exists(), "Octopi não deve ser configurado"
        check_expected(home, ".zshrc", ["zsh-autosuggestions.zsh", "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE"])

        check_expected(home, ".p10k.zsh", ["POWERLEVEL9K_"])
        check_expected(home, ".config/fastfetch/config.jsonc", ["/usr/share/wolf-linux/fastfetch/wolf-linux.txt"])
        before = (home / ".config/kwinrc").read_text(encoding="utf-8")
        configure(root, "wolf", PROJECT / "assets", True, True, True)
        after = (home / ".config/kwinrc").read_text(encoding="utf-8")
        assert before == after, "O perfil LXQt não deve modificar configurações KWin antigas"
    print("[OK] Perfil Full: preferências, MIME, Zsh/Konsole, VSCode e idempotência")
    with TemporaryDirectory() as tmp:
        root = Path(tmp)
        home = fake_root(root)
        configure(root, "wolf", PROJECT / "assets", False, False)
        assert not (home / ".zshrc").exists(), "Minimal instalou Zsh"
        assert not (home / ".local/share/file-manager/actions/wolf-open-vscode.desktop").exists(), "Minimal instalou VSCode"
        assert not (home / ".vscode/argv.json").exists(), "Minimal criou configurações VS Code"
        assert "video/mp4" not in (home / ".config/mimeapps.list").read_text(encoding="utf-8"), "Minimal configurou MPC-QT"
        check_expected(home, ".config/mimeapps.list", [
            "image/png=org.kde.gwenview.desktop;",
            "image/jpeg=org.kde.gwenview.desktop;",
            "image/svg+xml=org.kde.gwenview.desktop;",
            "text/plain=org.kde.kate.desktop;",
        ])
    print("[OK] Perfil Minimal: mantém stacks opcionais ausentes")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[ERRO] Teste de preferências: {e}", file=sys.stderr)
        raise
