# Wolf Linux DevKit 2.0.0-alpha23 — Planejamento JSON experimental

- Interface Wolf Installer GUI 0.4 produz pré-plano estruturado versionado `wolf.install.preview.v1`.
- Seleção opcional dos papéis raiz/EFI/home ao reutilizar partições, com flags de intenção de formatação.
- Validação independente `wolf-install --review-gui-plan /caminho/preview.json` usando inventário de discos atualizado.
- Documento privado em `~/.local/state/wolf-linux/live-installer/preview.json` (diretório 0700, arquivo 0600).
- Recusa documento com pedidos de execução, campos estranhos, disco trocado, partições de outro disco ou stacks inválidas.
- **Nenhuma alteração de disco, instalação ou montagem é autorizada pelo JSON.** O planejamento CLI tradicional segue independente.
- Mantém Live Openbox, rede NetworkManager, seleção de teclado ABNT2/ThinkPad e configurações estáveis da alpha22.
- A alpha18 permanece a baseline estável congelada.
