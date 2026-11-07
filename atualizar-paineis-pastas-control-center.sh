#!/usr/bin/env bash
# Hotfix opcional da instalação existente. Apenas componentes Wolf; não altera
# configurações de monitores, pastas nem painéis até o usuário pedir na GUI.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
usage(){ echo 'Uso: bash atualizar-paineis-pastas-control-center.sh [--check|--apply]'; }
[[ $# -eq 1 ]] || { usage; exit 2; }
case "$1" in --check|--apply) mode="$1";; *) usage; exit 2;; esac
[[ "$(id -u)" != 0 ]] || { echo 'Execute como seu usuário normal (sem sudo).' >&2; exit 2; }
for f in tools/lxqt/wolf_lxqt_monitors.py tools/lxqt/wolf-user-dirs-ptbr.py tools/lxqt/wolf-appearance-dark tools/lxqt/wolf-gtk-xsettings tools/lxqt/wolf-format-removable tools/lxqt/wolf-removable-tray tools/lxqt/configurar.py tools/control-center/main.py; do
  [[ -r "$ROOT/$f" ]] || { echo "Faltando: $f" >&2; exit 1; }
done
GLOBAL_CC=/usr/local/lib/wolf-linux/control-center/main.py
GLOBAL_PANEL=/usr/local/bin/wolf-lxqt-monitors
GLOBAL_DIRS=/usr/local/bin/wolf-user-dirs-ptbr
GLOBAL_THEME=/usr/local/bin/wolf-appearance-dark
GLOBAL_XSETTINGS=/usr/local/bin/wolf-gtk-xsettings
GLOBAL_FORMAT=/usr/local/bin/wolf-format-removable
GLOBAL_TRAY=/usr/local/bin/wolf-removable-tray
GLOBAL_CONFIGURAR=/usr/local/lib/wolf-linux/lxqt/configurar.py
LOCAL_CC="${XDG_DATA_HOME:-$HOME/.local/share}/wolf-linux/control-center/main.py"
if [[ "$mode" == --check ]]; then
  for target in "$GLOBAL_CC" "$GLOBAL_PANEL" "$GLOBAL_DIRS" "$GLOBAL_THEME" "$GLOBAL_XSETTINGS" "$GLOBAL_FORMAT" "$GLOBAL_TRAY" "$GLOBAL_CONFIGURAR" "$LOCAL_CC"; do
    if [[ -f "$target" ]]; then printf '[EXISTE] %s\n' "$target"; else printf '[AUSENTE] %s\n' "$target"; fi
  done
  echo 'Nenhuma configuração alterada. --apply instala somente scripts e integra a UI.'
  exit 0
fi
[[ -f "$GLOBAL_CC" ]] || { echo "Control Center global não encontrado: $GLOBAL_CC" >&2; exit 1; }
# Solicitar privilégio antes das alterações; tudo instalado atomicamente por install.
sudo -v
BACKUP="$HOME/wolf-backups/control-center-paineis-ptbr/$(date +%Y%m%d-%H%M%S-%N)"
mkdir -p "$BACKUP"
for target in "$GLOBAL_CC" "$GLOBAL_PANEL" "$GLOBAL_DIRS" "$GLOBAL_THEME" "$GLOBAL_XSETTINGS" "$GLOBAL_FORMAT" "$GLOBAL_TRAY" "$GLOBAL_CONFIGURAR" "$LOCAL_CC"; do
  if [[ -f "$target" ]]; then
    if [[ "$target" == /usr/local/* ]]; then
      sudo cp -p -- "$target" "$BACKUP/$(basename "$target").$(echo "$target" | tr '/' '_')"
    else
      cp -p -- "$target" "$BACKUP/main.py.local"
    fi
  fi
done
sudo install -m 0644 "$ROOT/tools/control-center/main.py" "$GLOBAL_CC"
# Se houver Control Center instalado por usuário, atualizar também a mesma cópia,
# sem trocar o launcher ou o conjunto de módulos do editor de monitores.
if [[ -f "$LOCAL_CC" && ! -L "$LOCAL_CC" ]]; then
  install -m 0644 "$ROOT/tools/control-center/main.py" "$LOCAL_CC"
fi
sudo install -m 0755 "$ROOT/tools/lxqt/wolf_lxqt_monitors.py" "$GLOBAL_PANEL"
sudo install -m 0755 "$ROOT/tools/lxqt/wolf-user-dirs-ptbr.py" "$GLOBAL_DIRS"
sudo install -m 0755 "$ROOT/tools/lxqt/wolf-appearance-dark" "$GLOBAL_THEME"
sudo install -m 0755 "$ROOT/tools/lxqt/wolf-gtk-xsettings" "$GLOBAL_XSETTINGS"
sudo install -m 0755 "$ROOT/tools/lxqt/wolf-format-removable" "$GLOBAL_FORMAT"
# Consulta de integrações (somente leitura) para Control Center e Package Manager.
sudo install -m 0755 "$ROOT/tools/package-manager/wolf-integrations-check.py" /usr/local/bin/wolf-integrations-check
# Integrações Wolf: alinhar o módulo global do Wolf Package Manager quando presente.
PKGMOD=/usr/local/lib/wolf-linux/package-manager/wolfpkg
if [[ -d "$PKGMOD" && ! -L "$PKGMOD" ]]; then
  if [[ -f "$PKGMOD/integrations.py" ]]; then
    sudo cp -p "$PKGMOD/integrations.py" "$BACKUP/package-manager-integrations.py.before"
  fi
  sudo install -m 0644 "$ROOT/tools/package-manager/wolfpkg/integrations.py" "$PKGMOD/integrations.py"
fi

sudo install -m 0755 "$ROOT/tools/lxqt/wolf-removable-tray" "$GLOBAL_TRAY"
sudo install -m 0644 "$ROOT/tools/lxqt/configurar.py" "$GLOBAL_CONFIGURAR"
# Remover a entrada redundante anterior, preservando a cópia em backup.
if [[ -f /usr/share/applications/wolf-disks.desktop ]]; then
  sudo cp -p /usr/share/applications/wolf-disks.desktop "$BACKUP/wolf-disks.desktop"
  sudo rm /usr/share/applications/wolf-disks.desktop
fi
sudo install -d /usr/local/share/applications
cat > "$BACKUP/wolf-format-removable.desktop" <<'EOWOLF_USB_APP'
[Desktop Entry]
Type=Application
Name=Formatar unidade USB (Wolf Linux)
Exec=/usr/local/bin/wolf-format-removable --browse
Icon=drive-removable-media
Terminal=false
Categories=System;Utility;
OnlyShowIn=LXQt;
EOWOLF_USB_APP
sudo install -m 0644 "$BACKUP/wolf-format-removable.desktop" /usr/local/share/applications/wolf-format-removable.desktop
# O menu de contexto do PCManFM-Qt fica no HOME, não em /usr/share/applications.
# Eliminar somente a ação antiga de pastas Wolf, com backup.
ACTION_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/file-manager/actions"
ACTION="$ACTION_DIR/wolf-format-removable.desktop"
if [[ -f "$ACTION" && ! -L "$ACTION" ]] && \
   grep -Fq 'wolf-format-removable --format %f' "$ACTION" && \
   grep -Fq 'Folders=/run/media/*;/media/*;' "$ACTION"; then
  cp -p -- "$ACTION" "$BACKUP/wolf-format-removable.desktop.before"
  rm -- "$ACTION"
  echo '[OK] Ação antiga de pastas removida; backup preservado.'
fi
# O Udiskie não oferece um menu pt_BR consistente; substituir somente seu
# autostart Wolf por indicador Qt. Outras autostarts do usuário são preservadas.
UDISKIE_AUTOSTART="$HOME/.config/autostart/wolf-udiskie.desktop"
[[ -f "$UDISKIE_AUTOSTART" ]] && cp -p "$UDISKIE_AUTOSTART" "$BACKUP/wolf-udiskie.desktop.before"
install -d "$HOME/.config/autostart"
for f in wolf-removable-tray.desktop wolf-xsettingsd.desktop; do
  if [[ -f "$HOME/.config/autostart/$f" ]]; then
    cp -p "$HOME/.config/autostart/$f" "$BACKUP/$f.before"
  fi
done
cat > "$UDISKIE_AUTOSTART" <<'EOF_WOLF_UDISKIE_OFF'
[Desktop Entry]
Type=Application
Name=Udiskie antigo desativado
Hidden=true
EOF_WOLF_UDISKIE_OFF
cat > "$HOME/.config/autostart/wolf-removable-tray.desktop" <<'EOF_WOLF_TRAY'
[Desktop Entry]
Type=Application
Name=Dispositivos removíveis (Wolf Linux)
Exec=/usr/local/bin/wolf-removable-tray
TryExec=/usr/local/bin/wolf-removable-tray
OnlyShowIn=LXQt;
X-LXQt-Need-Tray=true
NoDisplay=true
EOF_WOLF_TRAY
cat > "$HOME/.config/autostart/wolf-xsettingsd.desktop" <<'EOF_WOLF_XSETTINGS'
[Desktop Entry]
Type=Application
Name=Wolf - Tema GTK/X11
Exec=/usr/local/bin/wolf-gtk-xsettings
TryExec=/usr/local/bin/wolf-gtk-xsettings
OnlyShowIn=LXQt;
NoDisplay=true
EOF_WOLF_XSETTINGS
if ! command -v xsettingsd >/dev/null 2>&1; then
  echo '[AVISO] Para tema GTK/X11 uniforme, instale xsettingsd e breeze-gtk com atualização completa do Arch:'
  echo '         sudo pacman -Syu --needed xsettingsd breeze-gtk'
fi
# Para aplicar, o usuário deve reabrir o PCManFM-Qt e iniciar nova sessão LXQt.
# Quem instalou o Control Center localmente também deve receber a UI nova;
# caso contrário ~/.local/bin/wolf-control-center abriria a versão anterior.
if [[ -f "$LOCAL_CC" ]]; then
  install -m 0644 "$ROOT/tools/control-center/main.py" "$LOCAL_CC"
fi
printf '[OK] Integrado. Backup: %s\n' "$BACKUP"
echo 'Feche e reabra Wolf Control Center > Monitores > Aplicar painéis aos monitores.'
echo 'Para as pastas: Sistema > Pré-visualizar migração XDG; depois confirme Migração.'
echo 'Painéis: use diagnóstico detalhado antes de forçar; se não aparecer, compartilhe a saída.'
echo 'Nenhuma pasta nem painel foi alterado por este instalador.'
echo 'Após iniciar nova sessão, execute Wolf Control Center > Monitores > Aplicar painéis.'
echo 'Em Aparência e atalhos, reaplique Wolf-dark e reinicie Blueman.'
echo 'No PCManFM-Qt, reinicie o aplicativo para ver Formatar unidade USB no menu da raiz montada.'
