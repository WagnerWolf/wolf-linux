# Wolf Linux 2.0.0 — notas de lançamento

**Estado:** versão 2.0.0 preparada para distribuição com a ISO compilada pelo Archiso.

O mantenedor confirmou a conclusão e inicialização do sistema nos modos apagar disco inteiro, particionamento manual e reutilizar partições, incluindo entrada UEFI Wolf Linux funcional. Os testes de outros cenários (BIOS, hardware diverso e topologias especiais) não são automaticamente cobertos por essa homologação.

## O que está incluído

- Instalador visual único, responsivo, com terminal PTY embutido.
- Três modos de instalação, seleção de teclado, usuário/hostname e perfis Minimal/Test/Full.
- Cálculo e estimativas de espaço; atalhos para diagnósticos e GParted na Live.
- Detecção de GPU e seleção do provedor Vulkan; ferramentas opcionais recuperáveis em caso de falhas.
- KDE Plasma/Wayland, PipeWire e utilitários Wolf Linux no sistema instalado.

## Compatibilidade e avisos

- Gerenciamento de pacotes: Arch, Chaotic-AUR, AUR como último recurso.
- O modo genérico manual/reuso possui limitações em LVM multidisco, RAID e LUKS.
- A mídia Live permite alterações reais em discos. Confirme os dispositivos e faça backup quando necessário.
- Valores de espaço exibidos para perfis são estimativas. Para Full, reserve folga substancial.

## Mudanças desta revisão final

Somente versionamento, identidade e documentação. Sem alteração do executor validado na alpha59.

## Construção

```bash
./preparar_ambiente_wolf_linux.sh
bash tests/wolf-smoke-test.sh
bash tests/wolf-build-iso.sh
```

Após gerar a imagem, verifique a inicialização e o funcionamento básico no hardware de destino antes de distribuir amplamente.
