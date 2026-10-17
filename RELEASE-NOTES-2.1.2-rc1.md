# Wolf Linux DevKit 2.1.2-rc1 — prévia

Esta versão experimental parte da 2.1.1 SmokeFix 2 já testada em VM e hardware real.

**Perfil Basic:** LibreOffice Fresh em português, Google Chrome (Arch/Chaotic; AUR apenas como fallback), MPV/FFmpeg/Audacious, Okular (já na base KDE) e utilitários diários. Gaming, Development, Android, Containers e Extras não são selecionados. O Test e o Full continuam com OBS Studio, GIMP e Transmission via Extras.

**Ferramentas Live:** linhas com nomes das ferramentas legíveis e botões uniformes.

**Cache:** o instalador verifica a posse e escrita de ~/.cache e ~/.cache/wolf-linux. Corrige somente os diretórios com dono root pertencentes à home selecionada. Não faz chown recursivo nem manipula pastas de outros usuários.

A ISO deve ser compilada e testada em VM antes de utilizar em hardware físico. Não há mudanças nos executores de formatação, proteção de PVs LVM, EFI ou GRUB.
