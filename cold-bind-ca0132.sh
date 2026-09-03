#!/usr/bin/env bash
# Cold path: card is on pci-stub in D0. Swap in patched HDA, load ca0132, bind once.
set -euxo pipefail
LOG=/home/rob/ae7-debug/cold-bind-ca0132.log
mkdir -p /home/rob/ae7-debug
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date -Iseconds) cold ca0132 bind ==="
echo 8 >/proc/sys/kernel/printk
sync

CORE=/home/rob/ae7-fix/linux-7.1.9/sound/hda/core
CTRL=/home/rob/ae7-fix/linux-7.1.9/sound/hda/controllers
COMM=/home/rob/ae7-fix/linux-7.1.9/sound/hda/common
DEV=0000:06:00.0

echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control
echo "AE-7 before swap: power=$(cat /sys/bus/pci/devices/$DEV/power_state) driver=$(basename "$(readlink -f /sys/bus/pci/devices/$DEV/driver)")"

# Headphone/speaker amp GPIO only (two writew). Not the mmio_init table.
python3 -u /home/rob/ae7-fix/bar2-gpio-hp.py

# Unbind HDMI functions only so we can replace snd-hda-core.
for dev in /sys/bus/pci/drivers/snd_hda_intel/0000:*; do
	[ -e "$dev" ] || continue
	b=$(basename "$dev")
	echo "unbinding $b"
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
# Codec driver BEFORE the controller binds the AE-7.
CA0132=/home/rob/ae7-fix/linux-7.1.9/sound/hda/codecs/snd-hda-codec-ca0132.ko
if [ -f "$CA0132" ]; then
	insmod "$CA0132"
else
	modprobe snd_hda_codec_ca0132
fi
insmod "$CTRL/snd-hda-intel.ko"
lsmod | grep -E 'ca0132|snd_hda_intel|snd_hda_core'

sleep 1
echo "AE-7 after swap (still stub): power=$(cat /sys/bus/pci/devices/$DEV/power_state) driver=$(basename "$(readlink -f /sys/bus/pci/devices/$DEV/driver)")"
echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control

echo "$DEV" >/sys/bus/pci/drivers/pci-stub/unbind
echo >/sys/bus/pci/devices/$DEV/driver_override
echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control
sync
# If PCI config goes 0xffffffff, unbind immediately so a dead AE-7
# cannot interrupt-storm the machine (that hung the last session).
watchdog() {
	local i cfg
	for i in $(seq 1 80); do
		sleep 0.25
		cfg=$(python3 -c "print(open('/sys/bus/pci/devices/$DEV/config','rb').read(4).hex())" 2>/dev/null || echo ffffffff)
		if [ "$cfg" = "ffffffff" ]; then
			echo "WATCHDOG: AE-7 PCI dead; removing to stop IRQ storm"
			timeout 2 bash -c "echo $DEV >/sys/bus/pci/drivers/snd_hda_intel/unbind" || true
			timeout 3 bash -c "echo 1 >/sys/bus/pci/devices/$DEV/remove" || true
			return
		fi
	done
}
watchdog &
WG=$!

echo "binding $DEV once; power=$(cat /sys/bus/pci/devices/$DEV/power_state)"
timeout 20 bash -c "echo $DEV >/sys/bus/pci/drivers/snd_hda_intel/bind" || echo "bind timed out"
echo "bind returned $? power=$(cat /sys/bus/pci/devices/$DEV/power_state 2>/dev/null || echo unknown)"
sleep 12
kill "$WG" 2>/dev/null || true
wait "$WG" 2>/dev/null || true
echo "--- 12s ---"
lspci -nnk -d 1102:0010
cat /proc/asound/cards
dmesg | grep -iE '06:00.0|ca0132|hdaudio|Creative|ctefx|AFG|DSP|firmware|GCAP|GCTL' | tail -50
echo "=== $(date -Iseconds) script done ==="
sync
