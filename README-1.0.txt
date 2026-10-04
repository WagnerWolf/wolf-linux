WOLF LINUX 1.0
================

STATUS
------
Release final candidate for ISO validation.

Final MATE/X11 behavior:
- Super + middle click on a Marco titlebar -> next monitor.
- Super + middle click on the top 64 px of Chrome/Electron/CSD -> next monitor.
- Plain middle click on a Marco titlebar -> native "lower".
- Daemon is single-instance through flock.
- Robust restart uses the full process command, not pkill -x.

The historical unused Button2/XInput2 path was removed from production code.
The production mover now uses Xlib only and links only against libX11.

GNOME / LIBHANDY DARK MODE
--------------------------
MATE uses:
  xdg-desktop-portal
  xdg-desktop-portal-gtk
  org.gnome.desktop.interface color-scheme = prefer-dark

Expected portal value:
  org.freedesktop.appearance/color-scheme = uint32 1

AUDIO
-----
PipeWire + WirePlumber + RTKit.

REMOVABLE MEDIA
---------------
udiskie smart tray for safe unmount/eject.
GNOME Disks formatting action integrated with Caja.

FINAL PROJECT UPDATE
--------------------
If ~/wolf-linux already exists, prefer:

  ./wolf-upgrade-project-to-1.0.sh

This updates scripts/manifests and re-customizes the ISO profile WITHOUT
overwriting assets/. This preserves the transparent Plymouth logo already
validated on the real machine.

FINAL BUILD / VM TEST
---------------------
  cd ~/wolf-linux
  ./tests/wolf-build-iso.sh
  ./tests/wolf-run-arch-test.sh uefi

wolf-run-arch-test.sh now automatically selects the newest ISO from out/.
For an additional legacy BIOS test:

  ./tests/wolf-run-arch-test.sh bios

1.0.5:
- Corrige condição de corrida do Chrome/CSD ao mover janelas maximizadas entre monitores.
- Reenvia _NET_MOVERESIZE_WINDOW até confirmar o monitor de destino.

1.0.6:
- Remove o daemon experimental Super+botão do meio para mover janelas.
- Restaura o comportamento nativo do Marco para middle-click na barra.
- Mantém as barreiras de borda entre monitores.
- Mantém correções do mouse flat e do fundo GRUB BIOS da ISO.
