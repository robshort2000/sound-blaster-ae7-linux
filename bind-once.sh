#!/usr/bin/env bash
# One cold bind of the AE-7 with patched HDA. Do not rebind. Do not load ca0132.
set -euxo pipefail
LOG=/home/rob/ae7-debug/bind-once.log
mkdir -p /home/rob/ae7-debug
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date -Iseconds) bind-once start ==="
echo 8 >/proc/sys/kernel/printk
sync

CORE=/home/rob/ae7-fix/linux-7.1.9/sound/hda/core
CTRL=/home/rob/ae7-fix/linux-7.1.9/sound/hda/controllers
COMM=/home/rob/ae7-fix/linux-7.1.9/sound/hda/common
DEV=0000:06:00.0

echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control

for dev in /sys/bus/pci/drivers/snd_hda_intel/0000:*; do
	[ -e "$dev" ] || continue
	b=$(basename "$dev")
	echo "$b" >/sys/bus/pci/drivers/snd_hda_intel/unbind || true
done

modprobe -r snd_hda_codec_nvhdmi || true
modprobe -r snd_hda_codec_atihdmi || true
modprobe -r snd_hda_codec_hdmi || true
modprobe -r snd_hda_intel || true
modprobe -r snd_hda_codec || true
rmmod snd_hda_intel 2>/dev/null || true
rmmod snd_hda_codec 2>/dev/null || true
rmmod snd_hda_core 2>/dev/null || true

insmod "$CORE/snd-hda-core.ko"
insmod "$CORE/snd-intel-dspcfg.ko" || true
insmod "$COMM/snd-hda-codec.ko"
insmod "$CTRL/snd-hda-intel.ko"

# HDMI will auto-bind. AE-7 stays on pci-stub until we bind once.
sleep 1
lspci -nnk -d ::0403

if [ -e /sys/bus/pci/drivers/pci-stub/$DEV ]; then
	echo "$DEV" >/sys/bus/pci/drivers/pci-stub/unbind
fi
echo >/sys/bus/pci/devices/$DEV/driver_override
echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control
sync
echo "binding $DEV once..."
echo "$DEV" >/sys/bus/pci/drivers/snd_hda_intel/bind
echo "bind returned $?"
sleep 2
echo "--- result ---"
lspci -nnk -d 1102:0010
cat /proc/asound/cards
dmesg | tail -40
echo "=== $(date -Iseconds) bind-once done ==="
sync
