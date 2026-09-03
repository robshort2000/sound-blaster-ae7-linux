#!/usr/bin/env bash
# Install patched HDA modules for this running kernel. Safe to re-run after
# a linux package upgrade (stock modules get overwritten).
set -euo pipefail
K=$(uname -r)
SRC=/home/rob/ae7-fix/linux-7.1.9/sound/hda
DST=/usr/lib/modules/$K/kernel/sound/hda
BAK=/home/rob/ae7-fix/stock-module-backup/$K

if [[ ! -d $DST ]]; then
	echo "No module tree for $K at $DST" >&2
	exit 1
fi

install_one() {
	local rel=$1
	local src=$SRC/$rel
	local dst=$DST/$rel.zst
	local bak=$BAK/$rel.zst
	if [[ ! -f $src ]]; then
		echo "missing $src" >&2
		exit 1
	fi
	mkdir -p "$(dirname "$bak")" "$(dirname "$dst")"
	if [[ -f $dst && ! -f $bak ]]; then
		cp -a "$dst" "$bak"
	fi
	zstd -19 -f -o "$dst" "$src"
	echo "installed $dst"
}

# Only these four are patched. Do not replace snd-intel-dspcfg.
install_one core/snd-hda-core.ko
install_one controllers/snd-hda-intel.ko
install_one common/snd-hda-codec.ko
install_one codecs/snd-hda-codec-ca0132.ko
depmod -a "$K"
echo "depmod $K done"
modinfo snd-hda-codec-ca0132 | grep -E 'filename|description'
zstdcat "/usr/lib/modules/$K/kernel/sound/hda/codecs/snd-hda-codec-ca0132.ko.zst" | strings | grep -F 'skipping ae5_register_set' || true
echo "AE-7 modules installed for $K"
