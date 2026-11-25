#!/usr/bin/env bash
# Boot path: AE-7 is on pci-stub (cmdline). Patched snd-hda-intel is already
# loaded for HDMI/onboard. GPIO under stub, then bind once.
#
# Why this exists: stock udev probe hard-locks on CORBRP.RST (kernel bug
# 217510). This oneshot is started by ae7-cold-bind.timer after
# graphical.target, not wanted by multi-user.target, so a dead card cannot
# hold the login screen. See /home/rob/ae7-fix/README.md.
#
# A dead card (PCI config 0xffffffff, or a config read that wedges) is
# stamped in /run/ae7.dead and left in place. Do not unbind it and do not
# write remove. On 2026-11-11 the DSP image died at chipio_send, the probe
# aborted, and the unbind in mark_dead() stuck in D state. timeout and
# SIGKILL could not reap it. That PCI wait is the boot lag. Nothing in
# this boot may bind again. A full power-off is required.
# 2026-11-07: after a real PSU-off the chip enumerated healthy, then
# dspload_image() failed and the function went to 0xffffffff. The bind
# stayed in uninterruptible PCI waits and SIGKILL did not reap it. That
# was the lockup. Do not bind again on that power cycle.
#
# The same script succeeded at 15:51 the same day, after another PSU-off
# and with the timer disabled so boot could not bind early. Preconditions:
# driver was pci-stub, config read 02111000, no /run/ae7.dead, desktop
# already up. It ran GPIO under the stub (pins 0 and 1), bound once, and
# the kernel logged "ca0132 DSP downloaded and running" with GCAP still
# 0x6400. Both headphone channels worked. Details in the README section
# "Successful bind, 2026-11-07 15:51".
set -uo pipefail
DEV=0000:06:00.0
LOG=/var/log/ae7-cold-bind.log
GPIO=/usr/local/lib/ae7/bar2-gpio-hp.py
STAMP=/run/ae7.dead
STOP=/run/ae7-watchdog.stop
mkdir -p /var/log
exec >>"$LOG" 2>&1
echo "=== $(date -Iseconds) boot bind ==="

if [[ -f $STAMP ]]; then
	echo "AE-7 already quarantined this boot; not binding"
	exit 0
fi

if [[ ! -d /sys/bus/pci/devices/$DEV ]]; then
	echo "AE-7 PCI device missing; skip"
	exit 0
fi

# "ffffffff" is a real all-ones config read. "timeout" means the read wedged.
cfg() {
	local hex rc
	hex=$(timeout 2 python3 -c "print(open('/sys/bus/pci/devices/$DEV/config','rb').read(4).hex())" 2>/dev/null)
	rc=$?
	if (( rc == 124 )); then
		echo timeout
		return
	fi
	if (( rc != 0 )) || [[ -z ${hex:-} || $hex == ffffffff ]]; then
		echo ffffffff
		return
	fi
	printf '%s\n' "$hex"
}

mark_dead() {
	echo "$1"
	if [[ -f $STAMP ]]; then
		echo "already quarantined"
		return 0
	fi
	echo 1 >"$STAMP"
	# Do not unbind or remove the function. On 2026-11-11 the card died
	# during DSP download, then this unbind stuck in D state. timeout and
	# SIGKILL could not reap it, and that PCI wait is what lagged the
	# machine. The stamp is enough: nothing else in this boot may bind.
	echo "AE-7 quarantined for this boot. Left the device in place. Do not rebind until a full power-off."
}

# Two unresponsive reads. One blip must not remove a live card.
dead_twice() {
	local a b
	a=$(cfg)
	[[ $a == ffffffff || $a == timeout ]] || return 1
	sleep 0.3
	b=$(cfg)
	[[ $b == ffffffff || $b == timeout ]]
}

if dead_twice; then
	mark_dead "AE-7 PCI dead before bind"
	exit 0
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
if dead_twice; then
	mark_dead "AE-7 died during GPIO; refuse bind"
	exit 0
fi

modprobe snd-hda-codec-ca0132
modprobe snd-hda-intel

echo "$DEV" >/sys/bus/pci/drivers/pci-stub/unbind
echo >/sys/bus/pci/devices/$DEV/driver_override
echo 0 >/sys/bus/pci/devices/$DEV/d3cold_allowed
echo on >/sys/bus/pci/devices/$DEV/power/control

rm -f "$STOP"
watchdog() {
	local bad=0 c
	while [[ ! -f $STOP ]]; do
		sleep 0.25
		[[ -f $STOP ]] && return 0
		c=$(cfg)
		if [[ $c == ffffffff || $c == timeout ]]; then
			bad=$((bad + 1))
			if (( bad >= 2 )); then
				mark_dead "WATCHDOG: AE-7 PCI dead; quarantined, not removed"
				return 0
			fi
		else
			bad=0
		fi
	done
}
watchdog &
WG=$!

timeout 25 bash -c "echo $DEV >/sys/bus/pci/drivers/snd_hda_intel/bind" || echo "bind timed out"
echo "bind done driver=$(basename "$(readlink -f /sys/bus/pci/devices/$DEV/driver 2>/dev/null || echo none)") cfg=$(cfg)"
sleep 8
echo 1 >"$STOP"
wait "$WG" 2>/dev/null || true

if [[ -f $STAMP ]]; then
	echo "watchdog quarantined AE-7"
	exit 0
fi
if dead_twice; then
	mark_dead "AE-7 dead after bind"
	exit 0
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
