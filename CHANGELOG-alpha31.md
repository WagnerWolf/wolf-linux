# Wolf Linux 2.0.0-alpha31 — Reutilização EFI e /home (piloto VM)

- Alpha30: usuário validou instalação Minimal manual e apagar disco inteiro em VM. Alpha18 segue baseline estável.
- GUI 1.1 habilita **Reutilizar partições** em QEMU/KVM **UEFI**, disco VirtIO, com `/` ext4 formatada, EFI FAT32 e `/home` ext4 dedicadas preservadas. Não aceita `mkfs` para EFI/home neste modo.
- O plano `wolf.install.preview.v3` inclui `storage.cleanup_home` (booleano; padrão não). Revisão, simulação e preflight seguem sem alterações de disco.
- Limpeza opcional dos ocultos de TODOS os diretórios de usuário identificados imediatamente dentro da partição `/home`. Mostra a lista exata e solicita `LIMPAR` **antes** de formatar a raiz; revalida a lista depois. Entradas visíveis e a partição `/home` são preservadas. **ATENÇÃO:** entradas ocultas podem conter credenciais, chaves SSH, e-mails e dados irrecuperáveis — faça backup.
- Reutilização não recria o fallback genérico `EFI/BOOT/BOOTX64.EFI` (evita sobrescrever bootloader existente); instala/atualiza `EFI/WolfLinux` e pode alterar entrada de boot NVRAM.
- Preservação entre usuários com UIDs diferentes e múltiplas contas ainda não homologada; teste inicialmente usando o mesmo nome de usuário.
- Testes: contrato JSON, recusa de hardware/BIOS, verificação GPT/filesystems, mount/swap, dupla confirmação e limpeza simulada em fixture, smoke e staging; NÃO foi executada instalação real neste ambiente.
- A alpha31 deve ser testada em **cópia de uma VM alpha30 desligada**, mantendo disco qcow2 e NVRAM originais intactos. NÃO usar `fresh`.
