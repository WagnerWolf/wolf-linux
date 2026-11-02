# Wolf Linux 2.2.0 · Integrações Wolf Preview 3

- Qt: aplicar Fusion globalmente à sessão LXQt (Qt estilo e QT_STYLE_OVERRIDE), preservando paleta Wolf-dark e GTK Breeze-Dark.
- Atualizar o botão de reaplicação do Control Center para não voltar ao Breeze no Qt.
- Instalador opt-in e backup reversível para o sistema físico atual.
- Corrigida a documentação da geração do patch libfm-qt 2.4.0 a partir do diretório clonado.
- O patch C++ permanece experimental: não compila, instala, substitui biblioteca ou altera Pacman nesta prévia.

Para testar na instalação existente: `bash experimental/integracoes-wolf/ativar-fusion-wolf.sh --apply`.
Após reiniciar a sessão, verifique o PCManFM-Qt e o LXQt Archiver.
