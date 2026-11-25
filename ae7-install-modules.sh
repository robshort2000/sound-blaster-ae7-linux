#!/usr/bin/env bash
# Install patched HDA modules for the running kernel. Safe to re-run after a
# linux package upgrade (stock modules get overwritten). Does not bind the
# AE-7 and does not enable ae7-cold-bind.timer.
set -euo pipefail
K=$(uname -r)
ROOT=/home/rob/ae7-fix/linux-7.2.15
DST=/usr/lib/modules/$K/kernel/sound/hda
BAK=/home/rob/ae7-fix/stock-module-backup/$K

if [[ ! -d $DST ]]; then
	echo "No module tree for $K at $DST" >&2
	exit 1
fi

install_one() {
	local src=$1
	local rel=$2
	local dst=$DST/$rel.zst
	local bak=$BAK/$rel.zst
	local vermagic
	if [[ ! -f $src ]]; then
		echo "missing $src" >&2
		exit 1
	fi
	vermagic=$(modinfo -F vermagic "$src")
	case $vermagic in
	"$K "*) ;;
	*)
		echo "vermagic '$vermagic' does not match running kernel $K" >&2
		exit 1
		;;
	esac
	mkdir -p "$(dirname "$bak")" "$(dirname "$dst")"
	if [[ -f $dst && ! -f $bak ]]; then
		cp -a "$dst" "$bak"
	fi
	zstd -19 -f -o "$dst" "$src"
	echo "installed $dst"
}

# snd-hda-codec and snd-intel-dspcfg are not patched. Leave the distro copies.
install_one "$ROOT/sound/hda/core/snd-hda-core.ko" core/snd-hda-core.ko
install_one "$ROOT/sound/hda/controllers/snd-hda-intel.ko" controllers/snd-hda-intel.ko
install_one "$ROOT/ca0132-oot/snd-hda-codec-ca0132.ko" codecs/snd-hda-codec-ca0132.ko
depmod -a "$K"
echo "depmod $K done"
modinfo snd-hda-codec-ca0132 | grep -E 'filename|vermagic'
zstdcat "/usr/lib/modules/$K/kernel/sound/hda/codecs/snd-hda-codec-ca0132.ko.zst" | strings | grep -F 'skipping ae5_register_set'
zstdcat "/usr/lib/modules/$K/kernel/sound/hda/codecs/snd-hda-codec-ca0132.ko.zst" | strings | grep -F 'ignoring HP/Speaker Auto Detect'
echo "AE-7 modules installed for $K (not bound, timer not enabled)"
