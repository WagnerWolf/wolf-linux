# Wolf Linux Live — Installer 2.0

O aplicativo Wolf Installer é o único instalador apresentado na mídia Live. Ele abre com a escolha do layout do teclado (ABNT2 inicialmente aplicado), depois oferece os modos Apagar disco inteiro, Particionamento manual e Reutilizar partições.

O usuário deve escolher explicitamente o perfil de instalação (Minimal, Test, Full) e conferir o resumo das operações. Após duas confirmações, a instalação progride em um terminal embutido. Não há necessidade de abrir um terminal separado.

GParted e outras ferramentas auxiliares ficam acessíveis na própria interface. GParted pode modificar partições realmente e deve ser usado com atenção.

A detecção de topologias de disco e as proteções contra dispositivos perigosos são implementadas no backend. LVM multidisco, RAID e dispositivos criptografados estão fora do escopo dos três fluxos genéricos.

Para desenvolvimento da ISO: `bash tests/wolf-smoke-test.sh`, seguido de `bash tests/wolf-build-iso.sh`. Consulte o README principal para a instalação.
