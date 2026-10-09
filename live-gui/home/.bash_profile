# Wolf Linux Live: tela gráfica só no tty1 e somente quando permitido.
if [[ -z "${DISPLAY:-}" && "${XDG_VTNR:-}" == "1" ]]; then
    if grep -Eq '(^|[[:space:]])wolf[.]nogui=1([[:space:]]|$)' /proc/cmdline; then
        echo '[Wolf Live] Modo terminal solicitado (wolf.nogui=1).'
    else
        echo '[Wolf Live] Iniciando Openbox; em caso de falha, terminal permanece acessível.'
        if ! startx -- :0 vt1; then
            echo '[AVISO] Sessão gráfica indisponível. Use sudo wolf-install --help para o instalador CLI.'
        fi
    fi
fi
