#!/usr/bin/env bash
# Diagnóstico somente leitura para preparar patch C++ na MESMA versão instalada.
set -u
printf '%s\n' '=== WOLF: FONTE/ABI libfm-qt (leitura) ==='
printf '%s\n' '[Pacotes instalados]'
pacman -Q libfm-qt pcmanfm-qt 2>&1 || true
printf '%s\n' '[Pacote estrangeiro/local]'
pacman -Qm libfm-qt 2>&1 || true
printf '%s\n' '[Arquivos de biblioteca]'
pacman -Ql libfm-qt 2>/dev/null | grep -E '/(libfm-qt|libfmqt).*\.so' | head -15 || true
printf '%s\n' '[Ferramentas de compilação]'
for cmd in git cmake make makepkg pkgctl; do
  if command -v "$cmd" >/dev/null; then printf '[OK] %s\n' "$cmd"; else printf '[AUSENTE] %s\n' "$cmd"; fi
done
printf '%s\n' '[Integração atualmente declarada]'
if [[ -f /usr/share/wolf-linux/integrations/libfm-qt-usb-format.json ]]; then
    echo 'Existe um manifesto Wolf (não demonstra compatibilidade sozinho).'
else
    echo 'Nenhuma extensão Wolf do menu de dispositivos instalada.'
fi
printf '%s\n' '[FIM] Nenhum pacote foi modificado.'
