#!/usr/bin/env bash
# Load ca0132, then bind the AE-7 once. Keep D0. Never rebind.
set -euxo pipefail
LOG=/home/rob/ae7-debug/bind-ca0132.log
mkdir -p /home/rob/ae7-debug
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date -Iseconds) ca0132 bind start ==="
echo 8 >/proc/sys/kernel/printk
sync

DEV=0000:06:00.0
# Allow the codec module this session
if [ -f /etc/modprobe.d/ae7.conf ]; then
	mv /etc/modprobe.d/ae7.conf /etc/modprobe.d/ae7.conf.disabled
fi

echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control

# Unbind only the AE-7; leave NVIDIA/AMD HDMI on the patched intel module.
if [ -e /sys/bus/pci/drivers/snd_hda_intel/$DEV ]; then
	echo "$DEV" >/sys/bus/pci/drivers/snd_hda_intel/unbind
fi
echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control
echo "power after unbind: $(cat /sys/bus/pci/devices/$DEV/power_state)"

modprobe snd_hda_codec_ca0132
lsmod | grep ca0132
sync

echo >/sys/bus/pci/devices/$DEV/driver_override
echo "binding $DEV with ca0132 already loaded..."
echo "$DEV" >/sys/bus/pci/drivers/snd_hda_intel/bind
echo "bind returned $?"
echo "power after bind: $(cat /sys/bus/pci/devices/$DEV/power_state)"

# Codec/DSP init is slow (~70s last time just to fail without firmware).
sleep 8
echo "--- 8s ---"
lspci -nnk -d 1102:0010
cat /proc/asound/cards
dmesg | grep -iE '06:00.0|ca0132|hdaudio|Creative|ctefx|AFG|DSP|firmware' | tail -40
echo "=== $(date -Iseconds) ca0132 bind script end (probe may still be running) ==="
sync
