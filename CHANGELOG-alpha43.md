# Wolf Linux DevKit 2.0.0-alpha43 — preparação de homologação física

## Escopo

A alpha42 foi validada pelo usuário em QEMU/KVM com dois discos VirtIO, EFI em um, raiz no outro e `/home` em LV estendido a dois PVs. A reinstalação preservou os dados de teste. A alpha43 **não libera instalação destrutiva em SSD físico**.

### Identidade da `/home` preservada

- Novo `live-gui/wolf_home_identity.py` verifica o diretório pessoal existente antes da criação do usuário.
- Se o antigo UID pertence ao intervalo 1000–60000 e não existe colisão na base de usuários da nova instalação, `useradd` reaproveita esse UID. Arquivos antigos mantêm seus proprietários numéricos.
- Conflitos de UID, links simbólicos e identidades inválidas impedem a configuração, sem executar `chown -R`.
- Se o diretório pertencer a UID diferente (por exemplo, root no fixture do laboratório), o instalador pede **`AJUSTAR /home/usuario`** para corrigir **apenas o diretório principal**, nunca o conteúdo recursivamente.
- Um teste real de escrita (`mktemp` e remoção do próprio temporário) é executado como o usuário final. Se ACL ou permissões internas bloquearem a escrita, a instalação interrompe com diagnóstico, sem aplicar permissões abrangentes.
- A lógica só se aplica ao modo reutilizar com `/home` dedicada **preservada**.

### Pré-diagnóstico para discos físicos

- `wolf-physical-preflight`: inventário exclusivamente de leitura por `lsblk`, classificação conservadora dos discos e indicação de partições, montagens, assinaturas e volumes existentes.
- Discos com Windows, partições, LVM, mídia Live ou montagens são classificados para proteção.
- Um disco sem partições é marcado apenas para inspeção manual, **não** como seguro para formatação.
- Disponível na aba Bem-vindo da Live. Não introduz opção de instalação física na GUI nem altera as barreiras do Bash.

## Testes

`python3 tests/wolf-test-alpha43.py`, `bash tests/wolf-test-live-desktop.sh`, `bash tests/wolf-smoke-test.sh`. Os testes do novo helper usam diretórios temporários e inventários fictícios; não modificam discos reais.

## Pendente

Validar GUI e instalador com ISO real no hardware do usuário. Próximos passos: piloto de instalação física somente em SSD descartável dedicado e expansão do Wolf Rescue com procedimentos de recuperação seguros. Não instalar nos NVMe que contêm Windows/EFI/LVM ainda.
