#!/usr/bin/env bash
# Wolf alpha41: PREPARA SOMENTE DOIS DISPOSITIVOS VIRTIO DEDICADOS DO QEMU.
# Extremamente destrutivo APENAS nos qcow2 de laboratorio, depois de confirmar.
set -Eeuo pipefail
ACTION="${1:---check}"
EFI_SERIAL='WOLF41EFI'
ROOT_SERIAL='WOLF41ROOT'
EFI_LINK="/dev/disk/by-id/virtio-$EFI_SERIAL"
ROOT_LINK="/dev/disk/by-id/virtio-$ROOT_SERIAL"
EFI_DISK=""
ROOT_DISK=""

fail() { echo "[BLOQUEADO] $*" >&2; exit 2; }
log() { echo "[wolf41] $*"; }

[[ "$ACTION" == '--check' || "$ACTION" == '--apply' ]] || fail 'Uso: wolf-lab41-particionar --check|--apply'
[[ $EUID -eq 0 ]] || fail 'Execute com sudo na Live.'
# A verificação de virtualizacao antecede TODA inspeção e TODA escrita.
virt="$(systemd-detect-virt --vm 2>/dev/null || true)"
[[ "$virt" == kvm || "$virt" == qemu ]] || fail "Exige virtualização QEMU/KVM; detectado: ${virt:-nenhuma}."
[[ -d /sys/firmware/efi ]] || fail 'Laboratorio exige firmware UEFI (OVMF).'
[[ -d /run/archiso/airootfs ]] || fail 'Execute somente dentro da ISO Live Archiso/Wolf, nunca no sistema instalado.'
[[ -L "$EFI_LINK" && -L "$ROOT_LINK" ]] || fail 'Discos seriais WOLF41EFI/WOLF41ROOT não encontrados. Use tests/wolf-vm-multidisk.sh.'
EFI_DISK="$(readlink -f -- "$EFI_LINK")"
ROOT_DISK="$(readlink -f -- "$ROOT_LINK")"
[[ "$EFI_DISK" =~ ^/dev/vd[a-z]+$ && "$ROOT_DISK" =~ ^/dev/vd[a-z]+$ && "$EFI_DISK" != "$ROOT_DISK" ]] || fail 'Os dois alvos devem ser discos VirtIO distintos.'

validate_disk() {
    local disk="$1" serial="$2" size="$3" actual serial_actual rm ro
    [[ -b "$disk" ]] || fail "Não é dispositivo de blocos: $disk"
    [[ "$(lsblk -dnro TYPE "$disk")" == disk ]] || fail "Não é disco inteiro: $disk"
    serial_actual="$(lsblk -dnro SERIAL "$disk" | tr -d '[:space:]')"
    [[ "$serial_actual" == "$serial" ]] || fail "Serial divergente: $disk ($serial_actual)."
    actual="$(blockdev --getsize64 "$disk")"
    [[ "$actual" == "$size" ]] || fail "Capacidade inesperada de $disk: $actual (esperado $size)."
    rm="$(lsblk -dnro RM "$disk" | tr -d '[:space:]')"
    ro="$(lsblk -dnro RO "$disk" | tr -d '[:space:]')"
    [[ "$rm" == 0 && "$ro" == 0 ]] || fail "Disco removível/somente leitura: $disk"
    # Nunca iniciar sobre tabela existente, volume montado ou assinatura no disco.
    if [[ "$ACTION" == --apply ]]; then
        [[ "$(lsblk -nr -o TYPE "$disk" | grep -c '^part$' || true)" == 0 ]] || fail "$disk já contém partições; não preparar novamente."
        if ! sig="$(wipefs --no-act --noheadings --output TYPE "$disk")"; then
            fail "wipefs não conseguiu inspecionar $disk"
        fi
        [[ -z "$(printf '%s' "$sig" | tr -d '[:space:]')" ]] || fail "Disco $disk já possui assinaturas; não apagar."
    fi
}
validate_disk "$EFI_DISK" "$EFI_SERIAL" 68719476736
validate_disk "$ROOT_DISK" "$ROOT_SERIAL" 103079215104

cat <<MAPA
============================================================
Wolf Linux alpha41 — LABORATÓRIO QEMU (NÃO hardware físico)
  Disco A ($EFI_SERIAL): $EFI_DISK — 64 GiB
    A1: 1 GiB FAT32 EFI; A2: restante PV LVM
  Disco B ($ROOT_SERIAL): $ROOT_DISK — 96 GiB
    B1: 40 GiB ext4 /; B2: 8 GiB NTFS (simulacao Windows)
    B3: restante PV LVM
  VG: vg_monstro | LV: lv_projetos | FS: ext4 /home
  EFI e /home são criados em discos físicos virtuais diferentes
  A gravação será feita SOMENTE nestes dois discos virtio.
============================================================
MAPA
[[ "$ACTION" == '--apply' ]] || { log 'Verificação somente leitura concluída. Execute --apply quando estiver pronto.'; exit 0; }

read -r -p 'Para APAGAR OS DOIS DISCOS VIRTUAIS, digite CRIAR-LAB41: ' confirmation
[[ "$confirmation" == 'CRIAR-LAB41' ]] || fail 'Confirmação incorreta; nada alterado.'

for cmd in sgdisk partprobe udevadm mkfs.ext4 mkfs.vfat mkfs.ntfs pvcreate vgcreate lvcreate blkid mount umount lvs; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Ferramenta ausente: $cmd"
done
for d in "$EFI_DISK" "$ROOT_DISK"; do
    # Recusa montar como disco bruto, partição filha ou swap ativa.
    [[ "$(lsblk -nr -o TYPE "$d" | grep -c '^part$' || true)" == 0 ]] || fail "Partições detectadas antes da escrita: $d"
    [[ -z "$(lsblk -nr -o MOUNTPOINTS "$d" | tr -d '[:space:]')" ]] || fail "Disco montado: $d"
done
[[ ! -e /dev/vg_monstro ]] || fail 'O VG vg_monstro já existe. Abortado para não tocar em LVM existente.'

log 'Criando GPT/partições somente nos dois VirtIO identificados...'
sgdisk --clear --new=1:0:+1G --typecode=1:ef00 --change-name=1:WOLF41_ESP \
    --new=2:0:0 --typecode=2:8e00 --change-name=2:WOLF41_PV_A "$EFI_DISK"
sgdisk --clear --new=1:0:+40G --typecode=1:8300 --change-name=1:WOLF41_ROOT \
    --new=2:0:+8G --typecode=2:8300 --change-name=2:WOLF41_TEST_KEEP \
    --new=3:0:0 --typecode=3:8e00 --change-name=3:WOLF41_PV_B "$ROOT_DISK"
partprobe "$EFI_DISK" "$ROOT_DISK"
udevadm settle
A1="${EFI_DISK}1"; A2="${EFI_DISK}2"
B1="${ROOT_DISK}1"; B2="${ROOT_DISK}2"; B3="${ROOT_DISK}3"
for p in "$A1" "$A2" "$B1" "$B2" "$B3"; do [[ -b "$p" ]] || fail "Partição não surgiu: $p"; done

mkfs.vfat -F32 -n WOLF41_ESP "$A1"
mkfs.ext4 -F -L WOLF41_RAIZ "$B1"
mkfs.ntfs -Q -F -L WOLF41_WINDOWS_TEST "$B2"
log 'Criando VG e LV que atravessam OS DOIS discos VirtIO...'
pvcreate -y "$A2" "$B3"
vgcreate vg_monstro "$A2" "$B3"
lvcreate -y -n lv_projetos -l 100%FREE vg_monstro
LV=/dev/vg_monstro/lv_projetos
mkfs.ext4 -F -L WOLF41_HOME "$LV"

DIR=/run/wolf41-lab-seed
[[ ! -e "$DIR" ]] || fail "Ponto de montagem de preparo já existe: $DIR"
mkdir -p "$DIR"
mounted=()
cleanup() {
    local t
    for ((i=${#mounted[@]}-1; i>=0; i--)); do
        t="${mounted[i]}"
        if mountpoint -q -- "$t"; then umount -- "$t" || true; fi
    done
    rmdir "$DIR/efi" "$DIR/home" "$DIR/keep" "$DIR" 2>/dev/null || true
}
trap cleanup EXIT
mkdir -p "$DIR"/{efi,home,keep}
mount "$B1" "$DIR"; mounted+=("$DIR")
mkdir -p "$DIR"/{efi,home,keep,etc}
mount "$A1" "$DIR/efi"; mounted+=("$DIR/efi")
mount "$LV" "$DIR/home"; mounted+=("$DIR/home")
mount -t ntfs-3g "$B2" "$DIR/keep"; mounted+=("$DIR/keep")

ROOT_UUID="$(blkid -s UUID -o value "$B1")"
EFI_UUID="$(blkid -s UUID -o value "$A1")"
HOME_UUID="$(blkid -s UUID -o value "$LV")"
cat > "$DIR/etc/fstab" <<FSTAB
UUID=$ROOT_UUID / ext4 rw,relatime 0 1
UUID=$EFI_UUID /boot/efi vfat umask=0077 0 2
UUID=$HOME_UUID /home ext4 rw,relatime 0 2
FSTAB
mkdir -p "$DIR/home/wolf/Documentos" "$DIR/home/wolf/.wolf41-antigo"
printf 'MANTER: dado visivel de /home multi-PV Wolf41\n' > "$DIR/home/wolf/Documentos/wolf41-visivel.txt"
printf 'CONFIGURACAO ANTIGA: apagar somente se confirmado\n' > "$DIR/home/wolf/.wolf41-antigo/config.txt"
mkdir -p "$DIR/efi/EFI/Microsoft/Boot" "$DIR/efi/EFI/WolfLinux"
printf 'MARCADOR DE TESTE — NAO E O WINDOWS REAL\n' > "$DIR/efi/EFI/Microsoft/Boot/WOLF41-PRESERVAR.txt"
printf 'MANTER: particao NTFS de teste, nao e Windows real\n' > "$DIR/keep/WOLF41-PRESERVAR.txt"
log 'Seed feito: fstab em raiz, arquivos-testemunha no LV, ESP e partição extra.'
log 'Desmontando seed e verificando mapa...'
cleanup
trap - EXIT
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS "$EFI_DISK" "$ROOT_DISK"
pvs -o pv_name,vg_name,pv_size
lvs -o lv_path,lv_size,devices
log 'Laboratório preparado. Agora execute a descoberta multidisco da GUI.'
