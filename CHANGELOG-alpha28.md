# Wolf Linux 2.0.0-alpha28 — conclusão de instalação VM

- Base: alpha27, aprovada pelo usuário em instalação GUI completa na VM e boot KDE.
- Wolf Installer GUI 0.8: acompanha resultado do executor via arquivo temporário por execução, sem confiar no exit code do QTerminal.
- Em sucesso real do Bash (código zero), o terminal aguarda Enter, fecha e a interface mostra **Instalação concluída**, com opções **Reiniciar agora** e **Continuar na Live**.
- A interface anterior é fechada após a decisão. Nenhum reboot automático; somente ação explícita do usuário.
- Aviso para ejetar a ISO / ajustar boot antes de reiniciar.
- Em falha de instalação, não aparece mensagem de sucesso; mantém a interface e informa o erro.
- Reinicialização usa `sudo -n systemctl reboot` apenas na mídia Wolf Live e somente ao clicar no botão.
- Nenhuma alteração no motor de particionamento, perfis, drivers ou KDE instalado.
- Ainda requer validação visual e teste final na VM real.
