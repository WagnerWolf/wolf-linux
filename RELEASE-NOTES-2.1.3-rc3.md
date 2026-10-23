# Wolf Linux DevKit 2.1.3-rc3 — Bootstrap Chaotic-AUR resiliente

- Corrige regressão da RC2: falha no `pacman-key --recv-key` interrompia a instalação imediatamente.
- Importação da **chave primária documentada** `3056513887B78AEB`: tentativas por keyserver Ubuntu, HKP/80 e HTTPS; saída dos erros visível.
- Sem desabilitar assinaturas ou aceitar pacotes sem verificação.
- Falhas nas chaves, bootstrap CDN, sincronização ou instalação do CachyOS: menu explícito **Tentar novamente** / **Continuar pelo linux-lts**.
- Em fallback, retira seção Chaotic-AUR do `pacman.conf` se não sincronizou e registra pendência em `/etc/wolf-linux/cachyos-pending.txt` e `/var/log/wolf-optional-failures.log`.
- GRUB e verificação do NVIDIA DKMS levam em conta se CachyOS foi instalado. LTS continua obrigatório.
- Migração posterior ao CachyOS requer habilitar Chaotic-AUR com chave confiável, instalar kernel+headers, confirmar DKMS/NVIDIA, configurar GRUB; nunca apenas alterar `GRUB_TOP_LEVEL`.
- Ainda precisa ser compilada ISO e validado o fluxo real no Archiso/VM (normal e fallback simulado).
