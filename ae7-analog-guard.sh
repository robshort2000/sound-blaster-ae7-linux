#!/usr/bin/env bash
# Keep AE-7 analog alive without rebinding.
#
# Leftover CORB DMA (IOMMU faults at 0xfff80000, also seen at 0xfff40000)
# can run for ~an hour and then kill the analog path while PCM still looks
# fine. Stop that DMA at start, stop it again if faults return, and
# re-select Speakers only after a fault burst goes quiet (that is when
# analog died last time).
#
# This unit must not Wants=ae7-cold-bind. Restart=on-failure plus that
# Wants= retried a failed bind and hard-locked the machine. The bind unit
# starts this guard. See /home/rob/ae7-fix/README.md.
#
# DEV is the AE-7 only while that card is installed. With it removed,
# 0000:06:00.0 is the MAXIO NVMe (config dword 4b1e0216). Do not write
# BARs from here onto "whatever is at 06:00.0".
set -uo pipefail
DEV=0000:06:00.0
LOG=/var/log/ae7-analog-guard.log
STOP=/usr/local/lib/ae7/stop-corb-dma.py
mkdir -p /var/log
exec >>"$LOG" 2>&1

log() { echo "$(date -Iseconds) $*"; }

STAMP=/run/ae7.dead

# Bound the config read. An unanswered AE-7 stalls this for many seconds and
# that stall is visible as a frozen display.
pci_ok() {
	local hex rc
	hex=$(timeout 2 python3 -c "print(open('/sys/bus/pci/devices/$DEV/config','rb').read(4).hex())" 2>/dev/null)
	rc=$?
	if (( rc != 0 )) || [[ -z ${hex:-} ]]; then
		echo ffffffff
		return
	fi
	printf '%s\n' "$hex"
}

stop_corb() {
	[[ -x $STOP ]] || return 0
	python3 -u "$STOP" || log "stop-corb failed rc=$?"
}

speakers() {
	amixer -c Creative sset 'Output Select' Speakers >/dev/null 2>&1 || true
	amixer -c Creative sset 'HP/Speaker Auto Detect' off >/dev/null 2>&1 || true
}

if [[ -f $STAMP ]]; then
	log "AE-7 quarantined; not watching"
	exit 0
fi
if [[ ! -d /sys/bus/pci/devices/$DEV ]]; then
	log "AE-7 missing; exit"
	exit 0
fi
if [[ $(pci_ok) == ffffffff ]]; then
	log "AE-7 PCI dead; not rebinding"
	echo 1 >"$STAMP" 2>/dev/null || true
	exit 0
fi

log "start cfg=$(pci_ok)"
# BAR0 mmap only works while pci-stub owns the device. After bind, leftover
# CORB is the kernel's job (PIO init). This guard only restores analog.
speakers

saw_faults=0
quiet_polls=0
last_recover=0

while sleep 5; do
	if [[ -f $STAMP ]] || [[ $(pci_ok) == ffffffff ]]; then
		log "PCI died; not rebinding"
		echo 1 >"$STAMP" 2>/dev/null || true
		exit 0
	fi
	n=$(journalctl -k --since '8 sec ago' --no-pager 2>/dev/null | grep -c 'snd_hda_intel 0000:06:00.0: AMD-Vi: Event logged \[IO_PAGE_FAULT' || true)
	now=$(date +%s)
	if (( n > 0 )); then
		if (( saw_faults == 0 )); then
			log "IOMMU leftover-CORB faults n=$n (analog still usually works)"
		fi
		saw_faults=1
		quiet_polls=0
	elif (( saw_faults )); then
		quiet_polls=$((quiet_polls + 1))
		# A single empty poll is a gap inside a burst. Wait for a
		# second empty poll so Speakers is restored only after the
		# DMA has stayed stopped. On 2026-11-11 16:10 a re-select in
		# a one-poll gap lost to the DMA restarting, and the output
		# stayed dead until another re-select while it was quiet.
		if (( quiet_polls >= 2 && now - last_recover >= 30 )); then
			log "IOMMU faults stayed quiet; re-select Speakers"
			speakers
			last_recover=$now
			saw_faults=0
			quiet_polls=0
		fi
	fi
done
