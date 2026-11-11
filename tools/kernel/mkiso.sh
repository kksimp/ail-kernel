#!/usr/bin/env bash
# Make a bootable Limine ISO from a kernel ELF (runs on Kaleb's machines).
# Usage: tools/kernel/mkiso.sh KERNEL.elf OUT.iso
# Needs xorriso and a limine package (limine binary plus limine-bios-cd.bin, limine-uefi-cd.bin, limine-bios.sys).
set -eu
k=${1:?usage: mkiso.sh KERNEL.elf OUT.iso}; out=${2:?usage: mkiso.sh KERNEL.elf OUT.iso}
lim=${LIMINE_DIR:-$(dirname "$(find /usr/share /usr/local/share /opt -name limine-bios.sys -print -quit 2>/dev/null)")}
[ -f "$lim/limine-bios.sys" ] || { echo "limine files not found; set LIMINE_DIR" >&2; exit 2; }
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
mkdir -p "$d/iso/boot/limine" "$d/iso/EFI/BOOT"
cp "$k" "$d/iso/boot/kernel.elf"
cp "$lim"/limine-bios.sys "$lim"/limine-bios-cd.bin "$lim"/limine-uefi-cd.bin "$d/iso/boot/limine/"
cp "$lim"/BOOTX64.EFI "$d/iso/EFI/BOOT/" 2>/dev/null || true
cat > "$d/iso/boot/limine/limine.conf" <<CONF
timeout: 0
/ail-k
    protocol: limine
    kernel_path: boot():/boot/kernel.elf
CONF
xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 \
  -boot-info-table -hfsplus -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin \
  -efi-boot-part --efi-boot-image --protective-msdos-label "$d/iso" -o "$out" 2>/dev/null
limine bios-install "$out" >/dev/null
