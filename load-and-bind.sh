#!/usr/bin/env bash
# Load patched HDA modules and bind the AE-7. Log everything to disk first.
set -euxo pipefail
LOG=/home/rob/ae7-debug/patched-bind.log
mkdir -p /home/rob/ae7-debug
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date -Iseconds) patched bind start ==="
echo 8 >/proc/sys/kernel/printk
sysctl -w kernel.printk="8 4 1 7" || true
sync

CORE=/home/rob/ae7-fix/linux-7.1.9/sound/hda/core/snd-hda-core.ko
INTEL=/home/rob/ae7-fix/linux-7.1.9/sound/hda/controllers/snd-hda-intel.ko
test -f "$CORE" && test -f "$INTEL"

# Drop in-use HDA devices so we can replace snd-hda-core.
for dev in /sys/bus/pci/drivers/snd_hda_intel/0000:*; do
	[ -e "$dev" ] || continue
	b=$(basename "$dev")
	echo "unbinding $b from snd_hda_intel"
	echo "$b" >/sys/bus/pci/drivers/snd_hda_intel/unbind || true
done

# AE-7 should already be on pci-stub; leave it there until new modules are in.
modprobe -r snd_hda_codec_nvhdmi || true
modprobe -r snd_hda_codec_atihdmi || true
modprobe -r snd_hda_codec_hdmi || true
modprobe -r snd_hda_intel || true
modprobe -r snd_hda_codec || true
# snd_hda_core may still be held; try anyway
rmmod snd_hda_intel 2>/dev/null || true
rmmod snd_hda_codec 2>/dev/null || true
rmmod snd_hda_core 2>/dev/null || true

lsmod | grep -E 'snd_hda|snd_intel' || true

insmod "$CORE"
insmod "$INTEL"
echo "patched modules loaded"
lsmod | grep snd_hda

sleep 1
echo "--- PCI audio after reload ---"
lspci -nnk -d ::0403

DEV=0000:06:00.0
echo "AE-7 driver now: $(basename "$(readlink -f /sys/bus/pci/devices/$DEV/driver)" || echo none)"
if [ -e /sys/bus/pci/drivers/pci-stub/$DEV ]; then
	echo "$DEV" >/sys/bus/pci/drivers/pci-stub/unbind
fi
echo >/sys/bus/pci/devices/$DEV/driver_override
sync
echo "binding $DEV to snd_hda_intel..."
echo "$DEV" >/sys/bus/pci/drivers/snd_hda_intel/bind
echo "bind returned $?"
sleep 3
echo "--- after bind ---"
lspci -nnk -d 1102:0010
echo
dmesg | grep -iE '06:00.0|CORB|GCTL|Creative|snd_hda|ca0132|AE-7' | tail -50
echo "=== $(date -Iseconds) patched bind done ==="
sync
