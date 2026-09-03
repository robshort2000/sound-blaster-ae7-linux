#!/usr/bin/env bash
# Boot path: AE-7 is on pci-stub (cmdline). Patched snd-hda-intel is already
# loaded for HDMI/onboard. GPIO under stub, then bind once.
set -uo pipefail
DEV=0000:06:00.0
LOG=/var/log/ae7-cold-bind.log
GPIO=/usr/local/lib/ae7/bar2-gpio-hp.py
mkdir -p /var/log
exec >>"$LOG" 2>&1
echo "=== $(date -Iseconds) boot bind ==="

if [[ ! -d /sys/bus/pci/devices/$DEV ]]; then
	echo "AE-7 PCI device missing; skip"
	exit 0
fi

cfg() {
	python3 -c "print(open('/sys/bus/pci/devices/$DEV/config','rb').read(4).hex())" 2>/dev/null || echo ffffffff
}

if [[ $(cfg) == ffffffff ]]; then
	echo "AE-7 PCI dead; refuse bind"
	exit 1
fi

drv=$(basename "$(readlink -f /sys/bus/pci/devices/$DEV/driver 2>/dev/null || true)")
if [[ $drv == snd_hda_intel ]] && grep -q 'HDA Creative' /proc/asound/cards 2>/dev/null; then
	echo "already bound to snd_hda_intel with Creative card"
	exit 0
fi
if [[ $drv != pci-stub ]]; then
	echo "driver is '${drv:-none}', not pci-stub; refuse"
	exit 1
fi

echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control
python3 -u "$GPIO" || { echo "GPIO under stub failed"; exit 1; }
if [[ $(cfg) == ffffffff ]]; then
	echo "AE-7 died during GPIO; refuse bind"
	exit 1
fi

modprobe snd-hda-codec-ca0132
modprobe snd-hda-intel

echo "$DEV" >/sys/bus/pci/drivers/pci-stub/unbind
echo >/sys/bus/pci/devices/$DEV/driver_override
echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control

watchdog() {
	local i c
	for i in $(seq 1 80); do
		sleep 0.25
		c=$(cfg)
		if [[ $c == ffffffff ]]; then
			echo "WATCHDOG: AE-7 PCI dead; removing"
			timeout 2 bash -c "echo $DEV >/sys/bus/pci/drivers/snd_hda_intel/unbind" || true
			timeout 3 bash -c "echo 1 >/sys/bus/pci/devices/$DEV/remove" || true
			return
		fi
	done
}
watchdog &
WG=$!

timeout 25 bash -c "echo $DEV >/sys/bus/pci/drivers/snd_hda_intel/bind" || echo "bind timed out"
echo "bind done driver=$(basename "$(readlink -f /sys/bus/pci/devices/$DEV/driver 2>/dev/null || echo none)") cfg=$(cfg)"
sleep 8
kill "$WG" 2>/dev/null || true
wait "$WG" 2>/dev/null || true

if [[ $(cfg) == ffffffff ]]; then
	echo "AE-7 dead after bind"
	exit 1
fi

# Line-out is the working analog path. Headphone select was silent.
if grep -q 'HDA Creative' /proc/asound/cards 2>/dev/null; then
	amixer -c Creative sset 'Output Select' Speakers >/dev/null 2>&1 || true
	amixer -c Creative sset 'HP/Speaker Auto Detect' off >/dev/null 2>&1 || true
	echo "Creative card present; Speakers selected"
else
	echo "no Creative card after bind"
	cat /proc/asound/cards || true
	exit 1
fi
echo "=== $(date -Iseconds) done ==="
exit 0
