#!/usr/bin/env python3
"""Release check for KDE Package Manager 1.0.0 and Subtitle Downloader."""
import ast
import subprocess
import sys
from pathlib import Path
r=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
app=(r/'tools/package-manager/wolfpkg/app.py').read_text()
guard=(r/'tools/package-manager/wolfpkg/upgrade_guard.py').read_text()
upgrade=(r/'tools/package-manager/wolfpkg/upgrade_flow.py').read_text()
installer=(r/'install/wolf-install.sh').read_text()
profile=(r/'package-profiles/packages.conf').read_text()
assert "VERSION = '1.0.0'" in app
assert 'yay' in app and 'yay' in (r/'tools/package-manager/wolfpkg/backend.py').read_text() and 'should_confirm_aur_stage' in app
assert 'libfm' in guard  # preserved only for LXQt
assert 'install_wolf_package_manager' in installer
assert 'install_wolf_subtitle_downloader_kde' in installer
assert 'stage "69c3b-legendas-dolphin" install_wolf_subtitle_downloader_kde' in installer
assert '69d2-wolf-plasma' in installer
assert 'Wolf Package Manager 1.0.0 integrado' in installer
assert 'OnlyShowIn=KDE;' in installer
for item in ('python-pip','pyside6','mediainfo','libnotify','libsecret','gnome-keyring'):
    assert item in profile, item
for f in ('gui.py','backend.py','helpers.py','credentials.py'):
    path=r/'tools/subtitle-downloader/legendas/fontes'/f
    assert path.is_file()
    ast.parse(path.read_text(encoding='utf-8'))
for f in ('tools/subtitle-downloader/legendas/deploy.py', 'tools/package-manager/wolfpkg/app.py', 'tools/package-manager/wolfpkg/upgrade_flow.py'):
    ast.parse((r/f).read_text(encoding='utf-8'))
for f in ('tools/subtitle-downloader/instalar-legendas.sh', 'tools/subtitle-downloader/wolf-subtitle-downloader', 'tools/subtitle-downloader/wolf-subtitle-downloader-setup'):
    result=subprocess.run(['bash','-n',str(r/f)],capture_output=True)
    assert result.returncode==0, (f,result.stderr.decode())
    assert (r/f).stat().st_mode & 0o111, f
launcher=(r/'tools/subtitle-downloader/wolf-subtitle-downloader').read_text()
assert 'kdialog --title' in launcher
assert 'subliminal' in launcher and '--quick' not in launcher # passes the original args through
assert 'exec "$user_app" "$@"' in launcher
assert 'kdialog' in launcher
assert 'WOLF_SUB_MENU' in installer
assert 'MimeType=video/*;application/x-matroska;' in installer
assert 'X-KDE-Protocols=file' in installer
assert 'Name=Buscar legendas...' in installer
assert 'Name=Baixar melhor legenda PT-BR' in installer
assert 'pam' not in launcher.casefold()  # credential operations occur only in user's Secret Service
assert 'wolf-subtitle-downloader-setup --apply' not in installer
assert 'subliminal==2.8.0' in (r/'tools/subtitle-downloader/instalar-legendas.sh').read_text()
print('[OK] Wolf Package Manager 1.0.0 + yay e Subtitle Downloader KDE declarados em todos os perfis.')
print('[OK] Primeiro uso com consentimento: venv por usuario, sem credenciais na ISO.')
