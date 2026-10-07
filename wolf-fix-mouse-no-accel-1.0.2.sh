#!/usr/bin/env bash
set -Eeuo pipefail

TARGET=/usr/local/bin/wolf-disable-mouse-accel.sh

echo "============================================================"
echo "     WOLF LINUX - MOUSE FLAT PROFILE FIX 1.0.2"
echo "============================================================"

sudo tee "$TARGET" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -u

sleep 2
command -v xinput >/dev/null 2>&1 || exit 0

while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue

    props="$(xinput list-props "$id" 2>/dev/null || true)"

    # Não altera touchpads.
    if grep -q 'libinput Tapping Enabled' <<<"$props"; then
        continue
    fi

    if grep -q 'libinput Accel Profile Enabled' <<<"$props"; then
        profile_line="$(
            grep -m1 'libinput Accel Profile Enabled (' <<<"$props" \
                || true
        )"
        values="${profile_line##*:}"
        values="$(tr -d '[:space:]' <<<"$values")"

        case "$values" in
            *,*,*)
                xinput set-prop \
                    "$id" \
                    'libinput Accel Profile Enabled' \
                    0 1 0 \
                    >/dev/null 2>&1 || true
                ;;
            *,*)
                xinput set-prop \
                    "$id" \
                    'libinput Accel Profile Enabled' \
                    0 1 \
                    >/dev/null 2>&1 || true
                ;;
        esac
    fi

    if grep -q 'libinput Accel Speed' <<<"$props"; then
        xinput set-prop "$id" 'libinput Accel Speed' 0 \
            >/dev/null 2>&1 || true
    fi
done < <(xinput list --id-only 2>/dev/null || true)
EOF

sudo chmod 755 "$TARGET"

# Aplica imediatamente nesta sessão.
"$TARGET"

echo
echo "[OK] Script persistente atualizado e aplicado."
echo
echo "Dispositivos com perfil de aceleração:" 
while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    props="$(xinput list-props "$id" 2>/dev/null || true)"
    if grep -q 'libinput Accel Profile Enabled' <<<"$props"; then
        name="$(xinput list --name-only "$id" 2>/dev/null || echo "ID $id")"
        echo
        echo "  $name (id=$id)"
        grep -E \
            'libinput Accel Profile Enabled \(|libinput Accel Speed \(' \
            <<<"$props" || true
    fi
done < <(xinput list --id-only 2>/dev/null || true)
