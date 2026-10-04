WOLF LINUX DEVKIT v0.36
==========================

NOVIDADES DE DESKTOP
--------------------

1. WOLF EDGE BARRIER (MATE/X11)
- usa XFixes pointer barriers;
- protege os primeiros 36 px da divisa vertical entre monitores;
- o restante da borda continua livre;
- detecta mudanças do xrandr a cada 2 segundos;
- autostart somente no MATE.

Objetivo:
permitir movimentos rápidos para o canto superior (por exemplo fechar
uma janela) sem o ponteiro escapar imediatamente para o monitor vizinho.

2. CAJA + VISUAL STUDIO CODE
Pacote:
  python-caja

Extensão:
  /usr/share/caja-python/extensions/wolf_vscode.py

Menu no botão direito:
  Abrir pasta no VS Code
  Abrir esta pasta no VS Code

Funciona tanto numa pasta selecionada quanto no fundo da pasta atual.

3. APLICATIVOS PADRÃO
Vídeo:
  smplayer.desktop

Áudio:
  audacious.desktop

Aplicado no primeiro login com xdg-mime.

4. MINIATURAS / PREVIEWS
Adicionados:
  ffmpegthumbnailer
  webp-pixbuf-loader
  glycin
  libheif
  libopenraw
  libwmf
  gnome-epub-thumbnailer
  libgsf
  poppler-glib
  icoextract
  python-pillow
  freetype2

Cobertura prática:
- vídeos e capas de áudio;
- WebP;
- HEIF/HEIC/AVIF;
- RAW de câmeras;
- WMF/APM;
- EPUB/MOBI;
- ODF;
- PDF;
- ícones de EXE/DLL do Windows/Wine;
- formatos modernos de imagem suportados por glycin/gdk-pixbuf.

Caja:
  show-image-thumbnails = always
  thumbnail-limit = 64 GiB

5. PAINEL / TEMA
NÃO ALTERADOS.

Mantidos:
  Materia-dark + Wolf-Sunrise-Border
  Brisk | apps abertos | apps fixos | tray | data/hora | desktop

FIX DA INSTALAÇÃO ATUAL
-----------------------
Executar dentro da sessão MATE/X11:

  wolf-desktop-extras-v0.36.sh
