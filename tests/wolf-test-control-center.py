#!/usr/bin/env python3
"""Backend tests that never alter host state or launch real GUI."""
from pathlib import Path
from tempfile import TemporaryDirectory
import sys
import os

SOURCE = Path(__file__).resolve().parents[1] / "tools" / "control-center"
sys.path.insert(0, str(SOURCE))
import backend  # noqa: E402


def main() -> None:
    with TemporaryDirectory() as td:
        root = Path(td)
        fakehelpers = root / "helpers"
        assert backend.helper_file("monitor", fakehelpers) == fakehelpers / "experimental/wolf-plasma-multimonitor-0.3.sh"
        try:
            backend.helper_file("../../etc/shadow", fakehelpers)
        except ValueError:
            pass
        else:
            raise AssertionError("Bad helper name must be denied")
        home = root / "home"
        home.mkdir()
        assert backend.notifier_status(home, root / "missing") == "Wolf Package Manager não instalado"
        notifier = root / "wolf-package-manager"
        notifier.write_text("#!/bin/sh\n", encoding="utf-8")
        notifier.chmod(0o755)
        assert backend.notifier_status(home, notifier) == "Autostart ainda não configurado"
        result = backend.enable_notifier(home, notifier)
        assert result == home / ".config/autostart/wolf-package-manager.desktop"
        assert "Hidden=false" in result.read_text(encoding="utf-8")
        assert "OnlyShowIn=KDE;" in result.read_text(encoding="utf-8")
        # Idempotency and backup for prior user configuration
        backend.enable_notifier(home, notifier)
        assert not result.with_suffix(result.suffix + ".wolf-backup").exists()
        result.write_text("[Desktop Entry]\nExec=custom\n", encoding="utf-8")
        backend.enable_notifier(home, notifier)
        assert "Exec=custom" in result.with_suffix(result.suffix + ".wolf-backup").read_text(encoding="utf-8")
        plugin = root / "autosuggestions.zsh"
        plugin.write_text("# plugin\n", encoding="utf-8")
        (home / ".zshrc").write_text('source /somewhere/zsh-autosuggestions.zsh\n', encoding="utf-8")
        assert "instalado e carregamento" in backend.autosuggestions_status(home, plugin)
        disabled = backend.disable_notifier(home, notifier)
        assert "Hidden=true" in disabled.read_text(encoding="utf-8")
        assert "desativado" in backend.notifier_status(home, notifier)
        backend.enable_notifier(home, notifier)
        assert "Hidden=false" in disabled.read_text(encoding="utf-8")
        assert "configurado" in backend.notifier_status(home, notifier)
        assert "ausente" in backend.autosuggestions_status(home, root / "non-existent")
        rc, out = backend.command_output(["/bin/echo", "Wolf OK"])
        assert rc == 0 and out == "Wolf OK"
    print("[OK] Control Center backend 0.2.0: helpers allowlist, Package Manager enable/disable, backup e Zsh")


if __name__ == "__main__":
    main()
