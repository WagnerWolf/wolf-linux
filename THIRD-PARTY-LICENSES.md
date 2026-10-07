# Third-party theme

## sddm-astronaut-theme

Wolf Linux uses the SDDM framework from:

https://github.com/Keyitdev/sddm-astronaut-theme

Copyright (C) 2022-2025 Keyitdev and contributors.

License: GPL-3.0-or-later.

The installer clones the upstream repository and preserves its LICENSE file.
Wolf Linux adds its own configuration and background artwork.


## Sunrise GTK Themes

Wolf Linux MATE theme `Wolf-Sunrise-Dark` is based on `Sunrise-Dark` from:

https://github.com/i-mint/sunrise

The upstream project declares GPLv3 licensing and includes GTK2, GTK3 and
Metacity theme components. The installer preserves the upstream COPYING file
inside `/usr/share/themes/Wolf-Sunrise-Dark/`.

Wolf Linux adds a grayscale/silver CSS override while retaining the upstream
layout and theme structure.

## CinnVIIStarkMenu

Wolf Linux Cinnamon can install `CinnVIIStarkMenu@NikoKrause` from the official
Linux Mint Cinnamon Spices collection:

https://github.com/linuxmint/cinnamon-spices-applets/tree/master/CinnVIIStarkMenu%40NikoKrause

CinnVIIStarkMenu is distributed under the GNU General Public License, version 2
or later. The applet is downloaded from upstream during installation; Wolf Linux
only configures it as the default Cinnamon menu.


## alttab

Wolf Linux XFCE can install `alttab`, the standalone X11 task switcher from:

https://github.com/sagb/alttab

Copyright (C) Alexander Kulak and contributors.

License: GPL-3.0.

The package is installed from the configured Arch/Chaotic-AUR/AUR sources;
Wolf Linux only configures its XFCE integration and startup arguments.
