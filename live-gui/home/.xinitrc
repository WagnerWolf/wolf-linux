#!/usr/bin/env bash
export XDG_CURRENT_DESKTOP=OPENBOX
export XDG_SESSION_DESKTOP=openbox
export QT_QPA_PLATFORM=xcb
exec dbus-run-session -- openbox-session
