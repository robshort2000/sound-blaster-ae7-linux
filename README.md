# Sound Blaster AE-7 on Linux (Omarchy / Arch)

Workaround for Creative Sound Blaster AE-7 (`PCI 1102:0010`, subsystem `1102:0081`) on Linux 7.1.x.

Upstream: [kernel bug 217510](https://bugzilla.kernel.org/show_bug.cgi?id=217510).

## Warning — use at your own risk

**These patched drivers were vibe-coded against one machine and have not been tested on any other system.**

- They can **hard-lock the box**, **kill the PCI function until a PSU cycle**, or **IRQ-storm** if you bind a dead card.
- Do **not** treat this as an upstream-quality patch set.
- Do **not** drop `pci-stub` until a **cold** probe of the patched `snd-hda-intel` is proven safe on **your** hardware.
- After a failed probe the function often sits in D3cold / `0xffffffff` until **power is removed** (full PSU off). Unbind is not enough. **Do not rebind** on that power cycle.
- Kernel upgrades overwrite `/usr/lib/modules/.../snd-hda-*.ko.zst`. Re-run `ae7-install-modules.sh` after each `linux` upgrade.

If analog already works with stock kernels on your AE-7, you do not need this.

## Hardware this was developed on

- Creative Sound Blaster AE-7 (CA0132 / ca0113), PCI `06:00.0`
- AMD host, kernel `7.1.9-arch1-2`, Omarchy (Arch + Limine UKI)
- Firmware used: `/lib/firmware/ctefx-desktop.bin`

## What is wrong

Stock `snd_hda_intel` + `snd_hda_codec_ca0132` on this card:

1. **Boot hang.** CORB DMA reset wait (`CORBRP.RST`) never completes. With IRQs off during udev probe this **hard-locks** the machine (bug 217510).
2. **Dead MMIO.** A `GCAP` read of `0xffff` was treated as a valid capability word, inventing huge stream counts and a bogus codec mask.
3. **BAR2 / ca0113 is lethal after HDA CRST.** Several Windows-matching sequences kill PCI config (`0xffffffff`) on a cold card:
   - `ca0132_mmio_init_ae5()` (BAR2 `0x1c` / table)
   - `ae5_register_set()` SFR `writeb`/`writel` (before **or** after DSP)
   - bulk `mmio_command_set` **before** DSP is up
   - HP/Speaker **Auto Detect** (jack unsol + BAR2 reroute) hung this box
4. **DSP firmware pick.** AE-7 must load `ctefx-desktop.bin`, not `ctefx.bin`.
5. **Analog route.** Even with DSP alive, line-out stays silent until BAR2 GPIO (pins 0/1) and **post-DSP** `ca0113_mmio_command_set`. GPIO under stub is wiped by CRST; the driver re-applies GPIO after DSP.
6. **EQ sliders.** Mixer can show FX: Equalizer **On** while DSP req 9 is still off (`pe_switch_set` used to run only on resume). Band widgets are volume-only, so they never unmute the EQ block. Toggle Equalizer off/on, or the patched init that always pushes OutFX to the DSP.

## What we did **not** keep (lethal on this card)

| Attempt | Result |
|---|---|
| CORB DMA / wait for CORBRP | udev hang |
| `mmio_init_ae5` after CRST | PCI `0xffffffff` |
| `ae5_register_set` SFR writes (incl. post-DSP) | DSP death / hang |
| mmio_init table under stub on a **cold** card | GCAP `0xffff` |
| HP/Speaker Auto Detect | system hang |

## Working recipe (this machine)

Keep **pci-stub** on the kernel cmdline so stock probe never runs:

```
pci-stub.ids=1102:0010
```

(` /etc/limine-entry-tool.d/ae7.conf` on Omarchy.)

Patched `snd-hda-intel` for this SSID uses **PIO commands** (`AZX_DCAPS_PIO_COMMANDS`) and skips the CORB reset wait.

Patched `ca0132`:

- skip `mmio_init_ae5` after CRST
- skip `ae5_register_set` unless module param `ae7_bar2=1` (unsafe)
- block BAR2 `mmio_command_set` until `DSP_DOWNLOADED`
- lock HP auto-detect off
- push PlayEnhancement / OutFX to DSP on first init (so EQ actually enables)
- GPIO + `mmio_command_set` after DSP

Boot bind (GPIO under stub, then one `snd_hda_intel` bind):

```
/usr/local/sbin/ae7-cold-bind.sh
```

systemd: `ae7-cold-bind.service` (enabled). Analog path that worked: **Output Select = Speakers**. Headphone jack / gain enum did not.

Mixer: leave **HP/Speaker Auto Detect** off.

## Install on this kernel (Omarchy / Arch)

From a tree that already contains the built `.ko` files:

```bash
pkexec /usr/local/sbin/ae7-install-modules.sh
sudo systemctl enable --now ae7-cold-bind.service
```

Or bind once without installing:

```bash
pkexec bash cold-bind-ca0132.sh
```

Building the out-of-tree codec only:

```bash
make -C /lib/modules/$(uname -r)/build M=$PWD/ca0132-oot modules
```

`ca0132-oot/ca0132.c` is a symlink into a local kernel source checkout (not shipped). Apply `patches/ae7-ca0132-intel-controller.patch` on Linux 7.1.9 `sound/hda/` and rebuild `snd-hda-core`, `snd-hda-intel`, `snd-hda-codec`, `snd-hda-codec-ca0132`.

## Kernel files touched

- `sound/hda/controllers/intel.c` — AE-7 PIO + GCAP `0xffff` abort
- `sound/hda/core/controller.c` — skip CORB programming when PIO
- `sound/hda/codecs/ca0132.c` — DSP/BAR2 policy, auto-detect lock, EQ init sync

## License

Kernel patches follow the Linux kernel (`GPL-2.0-only`). Helper scripts in this repo are the same unless a file says otherwise.
