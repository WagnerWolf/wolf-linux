#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Wolf GRUB Manager"
VERSION="0.3"

GRUB_CFG="/boot/grub/grub.cfg"
GRUB_DEFAULT="/etc/default/grub"
GRUB_D="/etc/grub.d"
WOLF_ENTRIES_DIR="/etc/grub.d/wolf-entries.d"
WOLF_CUSTOM_SCRIPT="/etc/grub.d/42_wolf_custom"
BACKUP_ROOT="/var/backups/wolf-grub"

say()  { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

pause() {
    read -r -p $'\nPressione Enter para continuar...' _ || true
}

header() {
    clear 2>/dev/null || true
    say "======================================================"
    say "              ${APP_NAME} v${VERSION}"
    say "======================================================"
    say "Gerencia as FONTES do menu GRUB, não edita grub.cfg"
    say "manualmente. Operações destrutivas exigem confirmação."
    say "======================================================"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

require_grub() {
    need_cmd grub-mkconfig
    [[ -d "$GRUB_D" ]] || die "$GRUB_D não existe."
    [[ -f "$GRUB_DEFAULT" ]] || die "$GRUB_DEFAULT não existe."
}

confirm() {
    local prompt="${1:-Confirmar?}"
    local answer
    read -r -p "$prompt [s/N]: " answer
    [[ "$answer" =~ ^[sS]([iI][mM])?$ ]]
}

boot_mode() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        say "UEFI"
    else
        say "BIOS/Legacy"
    fi
}

read_grub_cfg() {
    [[ -f "$GRUB_CFG" ]] || return 1

    if [[ -r "$GRUB_CFG" ]]; then
        cat "$GRUB_CFG"
    else
        info "$GRUB_CFG exige privilégio de leitura; solicitando sudo..." >&2
        sudo cat "$GRUB_CFG"
    fi
}

grub_cfg_sha256() {
    read_grub_cfg | sha256sum | awk '{print $1}'
}

backup_grub() {
    local stamp dest
    stamp="$(date +%Y%m%d-%H%M%S)"
    dest="${BACKUP_ROOT}/${stamp}"

    info "Criando backup em ${dest}..."
    sudo mkdir -p "$dest"

    [[ -f "$GRUB_DEFAULT" ]] && sudo cp -a "$GRUB_DEFAULT" "$dest/default-grub"
    [[ -d "$GRUB_D" ]] && sudo cp -a "$GRUB_D" "$dest/grub.d"
    [[ -f "$GRUB_CFG" ]] && sudo cp -a "$GRUB_CFG" "$dest/grub.cfg"

    sudo sh -c "printf '%s\n' \
        'Data: $(date -Is)' \
        'Kernel: $(uname -r)' \
        'Boot mode: $(boot_mode)' \
        > '$dest/INFO.txt'"

    ok "Backup criado: $dest"
}

menuentry_stream() {
    read_grub_cfg | awk '
        /^### BEGIN \/etc\/grub\.d\// {
            src=$0
            sub(/^### BEGIN /, "", src)
            sub(/ ###$/, "", src)
        }
        /^[[:space:]]*(menuentry|submenu)[[:space:]]/ {
            line=$0
            kind=line
            sub(/^[[:space:]]*/, "", kind)
            sub(/[[:space:]].*$/, "", kind)

            title=line
            sub(/^[[:space:]]*(menuentry|submenu)[[:space:]]+/, "", title)

            if (substr(title,1,1) == sprintf("%c",39)) {
                title=substr(title,2)
                split(title,a,sprintf("%c",39))
                title=a[1]
            } else if (substr(title,1,1) == "\"") {
                title=substr(title,2)
                split(title,a,"\"")
                title=a[1]
            } else {
                split(title,a,/ --| \{/)
                title=a[1]
            }

            printf "%s\t%s\t%s\n", kind, title, (src ? src : "?")
        }
    '
}

list_entries() {
    say "--- Entradas presentes no grub.cfg atual ---"

    if [[ ! -f "$GRUB_CFG" ]]; then
        warn "$GRUB_CFG não existe."
        return 0
    fi

    local n=0 kind title source
    while IFS=$'\t' read -r kind title source; do
        ((n+=1))
        printf '%3d) %-9s %s\n' "$n" "$kind" "$title"
        printf '     origem: %s\n' "$source"
    done < <(menuentry_stream)

    if (( n == 0 )); then
        warn "Nenhuma menuentry/submenu encontrada."
    else
        say ""
        say "Total: $n"
    fi
}

detect_duplicate_titles() {
    say "--- Títulos repetidos no grub.cfg ---"

    local tmp found title
    tmp="$(mktemp)"

    if ! menuentry_stream \
        | awk -F '\t' '$1=="menuentry" {print $2 "\t" $3}' \
        > "$tmp"; then
        rm -f "$tmp"
        warn "Não foi possível analisar o grub.cfg."
        return 1
    fi

    found=0
    while IFS= read -r title; do
        [[ -n "$title" ]] || continue
        found=1
        printf '\nDuplicada: %s\n' "$title"
        awk -F '\t' -v t="$title" '$1==t {print "  - " $2}' "$tmp" | sort -u
    done < <(
        cut -f1 "$tmp" \
            | sort \
            | uniq -d
    )

    rm -f "$tmp"

    if (( found == 0 )); then
        ok "Não há títulos menuentry idênticos repetidos."
    fi
}

bootnext_entry_count() {
    local count
    count="$(
        menuentry_stream 2>/dev/null \
            | awk -F '\t' '$3=="/etc/grub.d/31_efi_bootnext" && $1=="menuentry" {n++} END{print n+0}'
    )"
    printf '%s\n' "${count:-0}"
}

list_grub_scripts() {
    say "--- Geradores em /etc/grub.d ---"
    local f base mode state

    while IFS= read -r f; do
        base="${f##*/}"
        mode="$(stat -c '%A' "$f" 2>/dev/null || printf '?')"
        if [[ -x "$f" ]]; then
            state="ATIVO"
        else
            state="inativo"
        fi
        printf '%-28s %-8s %s\n' "$base" "$state" "$mode"
    done < <(find "$GRUB_D" -maxdepth 1 -type f -print 2>/dev/null | sort)
}

list_kernels() {
    say "--- Kernels detectados ---"

    say ""
    say "/boot:"
    find /boot -maxdepth 1 -type f \
        \( -name 'vmlinuz-*' -o -name 'initramfs-*.img' -o -name '*-ucode.img' \) \
        -printf '  %f\n' 2>/dev/null | sort || true

    say ""
    say "pkgbase em /usr/lib/modules:"
    local f
    for f in /usr/lib/modules/*/pkgbase; do
        [[ -r "$f" ]] || continue
        printf '  %-28s %s\n' "$(cat "$f")" "${f%/pkgbase}"
    done

    say ""
    say "Pacotes kernel conhecidos pelo pacman:"
    pacman -Qq 2>/dev/null \
        | grep -E '^linux($|-lts$|-zen$|-hardened$|[0-9])' \
        | sed 's/^/  /' || true
}

grub_default_value() {
    local key="$1"
    sed -nE "s/^[[:space:]]*${key}=(.*)$/\1/p" "$GRUB_DEFAULT" | tail -n1
}

diagnostics() {
    require_grub

    say "--- Sistema ---"
    printf 'Boot mode: %s\n' "$(boot_mode)"
    printf 'Kernel atual: %s\n' "$(uname -r)"
    printf 'GRUB package: '
    pacman -Q grub 2>/dev/null || say "não identificado pelo pacman"
    printf 'grub-mkconfig: %s\n' "$(command -v grub-mkconfig)"
    printf 'grub.cfg: %s\n' "$GRUB_CFG"

    if [[ -f "$GRUB_CFG" ]]; then
        printf 'grub.cfg modificado em: %s\n' "$(stat -c '%y' "$GRUB_CFG")"
        printf 'grub.cfg SHA256: %s\n' "$(grub_cfg_sha256)"
    fi

    say ""
    say "--- /etc/default/grub relevante ---"
    grep -E '^[[:space:]]*GRUB_(DEFAULT|TIMEOUT|DISABLE_SUBMENU|DISABLE_OS_PROBER|DISABLE_BOOTNEXT|TOP_LEVEL|SAVEDEFAULT|CMDLINE_LINUX|CMDLINE_LINUX_DEFAULT)=' \
        "$GRUB_DEFAULT" 2>/dev/null || true

    say ""
    list_kernels

    say ""
    list_grub_scripts

    say ""
    detect_duplicate_titles

    if [[ -x "$GRUB_D/31_efi_bootnext" ]]; then
        local bn_count bn_setting
        bn_count="$(bootnext_entry_count)"
        bn_setting="$(grub_default_value GRUB_DISABLE_BOOTNEXT)"
        say ""
        say "--- EFI BootNext (GRUB 2.16+) ---"
        printf 'Gerador 31_efi_bootnext: ATIVO\n'
        printf 'GRUB_DISABLE_BOOTNEXT: %s\n' "${bn_setting:-<não definido>}"
        printf 'Entradas BootNext atuais: %s\n' "$bn_count"

        if (( bn_count > 0 )) && [[ "$bn_setting" != "true" ]]; then
            warn "Há entradas EFI BootNext no menu. Se forem apenas ruído, use a opção"
            warn "'Gerenciar EFI BootNext' e desative-as de forma persistente."
        fi
    fi
}

regenerate_grub() {
    require_grub
    need_cmd grub-script-check

    local tmp count
    tmp="$(sudo mktemp /tmp/wolf-grub.cfg.XXXXXX)"

    info "Gerando configuração temporária..."
    if ! sudo grub-mkconfig -o "$tmp"; then
        sudo rm -f "$tmp"
        die "grub-mkconfig falhou. O grub.cfg atual NÃO foi alterado."
    fi

    info "Validando sintaxe com grub-script-check..."
    if ! sudo grub-script-check "$tmp"; then
        sudo rm -f "$tmp"
        die "A nova configuração falhou na validação. O grub.cfg atual NÃO foi alterado."
    fi

    count="$(sudo grep -cE '^[[:space:]]*menuentry[[:space:]]' "$tmp" || true)"
    if [[ "$count" -lt 1 ]]; then
        sudo rm -f "$tmp"
        die "A configuração nova não contém menuentry. Recusando instalar."
    fi

    say ""
    say "A nova configuração contém ${count} menuentry(s)."

    if ! confirm "Substituir $GRUB_CFG por esta configuração validada?"; then
        sudo rm -f "$tmp"
        warn "Operação cancelada."
        return 0
    fi

    backup_grub
    sudo install -m 0644 "$tmp" "$GRUB_CFG"
    sudo rm -f "$tmp"
    ok "GRUB regenerado e validado."
}

set_grub_key() {
    local key="$1" value="$2"
    local tmp

    tmp="$(mktemp)"
    awk -v key="$key" -v value="$value" '
        BEGIN {done=0}
        $0 ~ "^[[:space:]]*" key "=" {
            print key "=" value
            done=1
            next
        }
        {print}
        END {
            if (!done) print key "=" value
        }
    ' "$GRUB_DEFAULT" > "$tmp"

    sudo install -m 0644 "$tmp" "$GRUB_DEFAULT"
    rm -f "$tmp"
}

manage_bootnext() {
    require_grub

    local current count
    current="$(grub_default_value GRUB_DISABLE_BOOTNEXT)"
    count="$(bootnext_entry_count)"

    say "--- EFI BootNext ---"
    printf 'Gerador: %s\n' "$([[ -x "$GRUB_D/31_efi_bootnext" ]] && printf ATIVO || printf inativo)"
    printf 'GRUB_DISABLE_BOOTNEXT=%s\n' "${current:-<não definido>}"
    printf 'Entradas atuais vindas de 31_efi_bootnext: %s\n' "$count"
    say ""
    say "EFI BootNext permite que o GRUB ofereça atalhos para entradas UEFI."
    say "Isso NÃO é necessário para iniciar normalmente o Wolf Linux, Windows"
    say "ou acessar UEFI Firmware Settings."
    say ""
    say "1) Ocultar entradas EFI BootNext (recomendado para menu limpo)"
    say "2) Reativar entradas EFI BootNext"
    say "0) Voltar"

    local opt
    read -r -p "Opção: " opt
    case "$opt" in
        1)
            backup_grub
            set_grub_key GRUB_DISABLE_BOOTNEXT true
            ok "GRUB_DISABLE_BOOTNEXT=true definido."
            info "Agora regenere o GRUB para remover as entradas do menu."
            ;;
        2)
            backup_grub
            set_grub_key GRUB_DISABLE_BOOTNEXT false
            ok "GRUB_DISABLE_BOOTNEXT=false definido."
            info "Agora regenere o GRUB para aplicar."
            ;;
        0) return 0 ;;
        *) warn "Opção inválida." ;;
    esac
}

manage_os_prober() {
    require_grub

    local current
    current="$(grub_default_value GRUB_DISABLE_OS_PROBER)"

    say "Estado atual em /etc/default/grub:"
    printf '  GRUB_DISABLE_OS_PROBER=%s\n' "${current:-<não definido>}"
    say ""
    say "1) Habilitar detecção de outros sistemas (false)"
    say "2) Desabilitar os-prober (true)"
    say "0) Voltar"

    local opt
    read -r -p "Opção: " opt
    case "$opt" in
        1)
            backup_grub
            set_grub_key GRUB_DISABLE_OS_PROBER false
            ok "os-prober habilitado. Regenere o GRUB para aplicar."
            ;;
        2)
            backup_grub
            set_grub_key GRUB_DISABLE_OS_PROBER true
            ok "os-prober desabilitado. Regenere o GRUB para aplicar."
            ;;
        0) return 0 ;;
        *) warn "Opção inválida." ;;
    esac
}

toggle_generator_script() {
    require_grub

    local -a files=()
    mapfile -t files < <(find "$GRUB_D" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort)

    ((${#files[@]} > 0)) || { warn "Nenhum script encontrado."; return 0; }

    say "Geradores:"
    local i state
    for i in "${!files[@]}"; do
        if [[ -x "$GRUB_D/${files[$i]}" ]]; then
            state="ATIVO"
        else
            state="inativo"
        fi
        printf '%3d) %-28s %s\n' "$((i+1))" "${files[$i]}" "$state"
    done

    say ""
    local choice base target
    read -r -p "Número do script (0 cancela): " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { warn "Seleção inválida."; return 0; }
    (( choice == 0 )) && return 0
    (( choice >= 1 && choice <= ${#files[@]} )) || { warn "Seleção inválida."; return 0; }

    base="${files[$((choice-1))]}"
    target="$GRUB_D/$base"

    case "$base" in
        00_header|10_linux)
            warn "O Wolf GRUB Manager não permite desativar $base."
            warn "Isso poderia remover componentes essenciais ou todas as entradas Linux geradas."
            return 0
            ;;
        31_efi_bootnext)
            warn "Não altere o bit executável de 31_efi_bootnext."
            warn "Uma atualização do pacote GRUB pode restaurá-lo."
            warn "Use a opção 'Gerenciar EFI BootNext', que grava GRUB_DISABLE_BOOTNEXT."
            return 0
            ;;
    esac

    if [[ -x "$target" ]]; then
        warn "Desativar $base impede que ele gere entradas no próximo grub-mkconfig."
        confirm "Desativar este gerador?" || return 0
        backup_grub
        sudo chmod a-x "$target"
        ok "$base desativado. Regenere o GRUB para aplicar."
    else
        confirm "Ativar novamente $base?" || return 0
        backup_grub
        sudo chmod a+x "$target"
        ok "$base ativado. Regenere o GRUB para aplicar."
    fi
}

ensure_wolf_custom_generator() {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
#!/bin/sh
# Wolf Linux: emite entradas customizadas gerenciadas em arquivos .cfg.
for f in /etc/grub.d/wolf-entries.d/*.cfg; do
    [ -r "$f" ] || continue
    cat "$f"
    printf '\n'
done
EOF
    sudo mkdir -p "$WOLF_ENTRIES_DIR"
    sudo install -m 0755 "$tmp" "$WOLF_CUSTOM_SCRIPT"
    rm -f "$tmp"
}

list_wolf_entries() {
    if [[ ! -d "$WOLF_ENTRIES_DIR" ]]; then
        say "Nenhuma entrada Wolf customizada."
        return 0
    fi

    local -a files=()
    mapfile -t files < <(find "$WOLF_ENTRIES_DIR" -maxdepth 1 -type f -name '*.cfg' -printf '%f\n' 2>/dev/null | sort)

    if ((${#files[@]} == 0)); then
        say "Nenhuma entrada Wolf customizada."
        return 0
    fi

    local i title
    for i in "${!files[@]}"; do
        title="$(sed -nE "s/^[[:space:]]*menuentry[[:space:]]+'([^']+)'.*/\1/p" \
            "$WOLF_ENTRIES_DIR/${files[$i]}" 2>/dev/null | head -n1)"
        printf '%3d) %-32s %s\n' "$((i+1))" "${title:-?}" "${files[$i]}"
    done
}

slugify() {
    local s="$1"
    s="${s,,}"
    s="$(sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' <<<"$s")"
    [[ -n "$s" ]] || s="entrada"
    printf '%s\n' "$s"
}

add_custom_entry() {
    require_grub

    warn "Modo avançado: esta função cria uma entrada GRUB customizada."
    warn "Use principalmente para entradas especiais que não são geradas automaticamente."
    say ""

    local title
    read -r -p "Título da entrada: " title
    [[ -n "$title" ]] || { warn "Título vazio."; return 0; }
    [[ "$title" != *"'"* ]] || { warn "O título não pode conter apóstrofo nesta versão."; return 0; }

    say ""
    say "Digite o CORPO da menuentry, uma linha por vez."
    say "Digite apenas um ponto (.) para finalizar."
    say ""

    local body="" line
    while IFS= read -r line; do
        [[ "$line" == "." ]] && break
        body+=$'    '"$line"$'\n'
    done

    [[ -n "$body" ]] || { warn "Corpo vazio. Cancelado."; return 0; }

    local slug tmp dest
    slug="$(slugify "$title")"
    tmp="$(mktemp)"
    dest="$WOLF_ENTRIES_DIR/${slug}.cfg"

    {
        printf "menuentry '%s' --class wolf-custom {\n" "$title"
        printf '%s' "$body"
        printf '}\n'
    } > "$tmp"

    say ""
    say "--- Entrada proposta ---"
    cat "$tmp"
    say ""

    if ! confirm "Salvar esta entrada?"; then
        rm -f "$tmp"
        return 0
    fi

    backup_grub
    ensure_wolf_custom_generator
    sudo install -m 0644 "$tmp" "$dest"
    rm -f "$tmp"

    ok "Entrada salva em $dest"
    info "Use 'Regenerar GRUB' para validar e aplicar."
}

remove_custom_entry() {
    [[ -d "$WOLF_ENTRIES_DIR" ]] || { warn "Nenhuma entrada Wolf customizada."; return 0; }

    local -a files=()
    mapfile -t files < <(find "$WOLF_ENTRIES_DIR" -maxdepth 1 -type f -name '*.cfg' -printf '%f\n' 2>/dev/null | sort)
    ((${#files[@]} > 0)) || { warn "Nenhuma entrada Wolf customizada."; return 0; }

    list_wolf_entries
    say ""

    local choice target
    read -r -p "Número para remover (0 cancela): " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { warn "Seleção inválida."; return 0; }
    (( choice == 0 )) && return 0
    (( choice >= 1 && choice <= ${#files[@]} )) || { warn "Seleção inválida."; return 0; }

    target="$WOLF_ENTRIES_DIR/${files[$((choice-1))]}"
    confirm "Remover $target?" || return 0

    backup_grub
    sudo rm -f "$target"
    ok "Entrada removida. Regenere o GRUB para aplicar."
}

show_source_advice() {
    cat <<'EOF'
Como interpretar as origens:

  /etc/grub.d/10_linux
      Entradas dos kernels Linux instalados. NÃO apague no grub.cfg.
      Zen + LTS é esperado quando ambos os kernels estão instalados.

  /etc/grub.d/30_os-prober
      Sistemas encontrados pelo os-prober, como Windows.

  /etc/grub.d/30_uefi-firmware
      Atalho "UEFI Firmware Settings".

  /etc/grub.d/31_efi_bootnext
      GRUB 2.16+: atalhos para entradas UEFI BootNext.
      Para ocultá-los persistentemente, use GRUB_DISABLE_BOOTNEXT=true.
      Não é recomendado apenas chmod -x no script, pois atualização do pacote
      pode restaurar a permissão.

  /etc/grub.d/40_custom, 41_custom ou outros *_custom
      Entradas customizadas.

  /etc/grub.d/42_wolf_custom
      Entradas criadas pelo Wolf GRUB Manager.

O grub.cfg é um ARQUIVO GERADO. Alterações diretas nele podem desaparecer no
próximo grub-mkconfig.
EOF
}

main_menu() {
    require_grub

    while true; do
        header
        say "1) Diagnóstico completo"
        say "2) Listar entradas e origem"
        say "3) Detectar títulos duplicados"
        say "4) Listar kernels e initramfs"
        say "5) Listar scripts geradores /etc/grub.d"
        say "6) Gerenciar EFI BootNext (GRUB 2.16+)"
        say "7) Ativar/desativar outro script gerador"
        say "8) Configurar os-prober"
        say "9) Adicionar entrada customizada Wolf"
        say "10) Remover entrada customizada Wolf"
        say "11) Listar entradas customizadas Wolf"
        say "12) Regenerar GRUB com backup + validação"
        say "13) Explicar como remover entradas corretamente"
        say "0) Sair"
        say ""

        local opt
        read -r -p "Opção: " opt
        case "$opt" in
            1) diagnostics; pause ;;
            2) list_entries; pause ;;
            3) detect_duplicate_titles; pause ;;
            4) list_kernels; pause ;;
            5) list_grub_scripts; pause ;;
            6) manage_bootnext; pause ;;
            7) toggle_generator_script; pause ;;
            8) manage_os_prober; pause ;;
            9) add_custom_entry; pause ;;
            10) remove_custom_entry; pause ;;
            11) list_wolf_entries; pause ;;
            12) regenerate_grub; pause ;;
            13) show_source_advice; pause ;;
            0) exit 0 ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

require_grub
main_menu
