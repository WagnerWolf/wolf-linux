# Wolf Linux DevKit 2.0.0-alpha12

- Substitui o ícone do Kickoff pelo `newwolf-linux-kickoff.svg` fornecido pelo usuário, sem alterar bytes.
- Substitui `plasma-meta` pelo conjunto explícito de dependências do Plasma (sem Discover).
- Acrescenta gate pós-pacotes: Discover e plasma-meta não podem estar instalados.
- Remove entradas Discover dos launchers dos templates Plasma durante a instalação, sem autostart.
- Corrige MultiMonitor 0.3.1 para preservar Kickoff atual e herdar ícone apenas em painéis novos.
- Amplia smoke test para verificar política Discover e proteção do Kickoff.
