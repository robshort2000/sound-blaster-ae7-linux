# Sound Blaster AE-7 on Linux (Omarchy / Arch)

Workaround for Creative Sound Blaster AE-7 (`PCI 1102:0010`, subsystem `1102:0081`) on Linux 7.1.9 and 7.2.15.

Upstream: [kernel bug 217510](https://bugzilla.kernel.org/show_bug.cgi?id=217510).

## Warning — use at your own risk

**Vibe-coded. Tested on one machine only. Use at your own risk.**

These patched drivers were written against a single Omarchy workstation and have not been tested on any other system. The 7.2.15 port was confirmed only on that same machine, on 2026-11-25, with analog playback after one manual bind.

- They can **hard-lock the box**, **kill the PCI function until a PSU cycle**, or **IRQ-storm** if you bind a dead card.
- Do **not** treat this as an upstream-quality patch set.
- Do **not** drop `pci-stub` until a **cold** probe of the patched `snd-hda-intel` is proven safe on **your** hardware.
- After a failed probe the function often sits in D3cold / `0xffffffff` until **power is removed** (full PSU off). Unbind is not enough. **Do not rebind** on that power cycle.
- Kernel upgrades overwrite `/usr/lib/modules/.../snd-hda-*.ko.zst`. Re-run `ae7-install-modules.sh` after each `linux` upgrade.

If analog already works with stock kernels on your AE-7, you do not need this.

## Why the guards exist

Do not remove these because a session is lagging or a channel goes quiet. Each one is a scar from a lockup on this machine. The analog reset is `amixer -c Creative sset 'Output Select' Speakers` with **HP/Speaker Auto Detect** left off. One bind of a **live** card, from `/usr/local/sbin/ae7-cold-bind.sh`, after the desktop is up, is the designed path and did not lock the machine (see the 15:51 bind below). What locks the box is a second bind after PCI config is `0xffffffff`, a bind ordered before the login screen, or the analog guard pulling the bind back in.

| Piece | Why it is there |
|---|---|
| `pci-stub.ids=1102:0010` | Stock udev probe waits forever on `CORBRP.RST` with IRQs off and hard-locks (kernel bug 217510). The card stays on the stub until one patched bind. |
| `ae7-cold-bind.timer` (not the service wanted by `multi-user.target`) | Wanting the oneshot ordered it `Before=multi-user` and `Before=sddm`. A card that fell off the bus held Plymouth and the login screen, and the NVIDIA flip timed out. The timer fires 10s after `graphical.target`, so the desktop is up and startup apps have time to launch. `Restart=no`, `TimeoutStartSec=90`. |
| `/run/ae7.dead` | PCI config `0xffffffff`, or a config read that wedges, means the function is dead. The script stamps this file and does not unbind or remove the device. Nothing in that boot may bind again. A second bind of a dead card hard-locks. Unbind of a dead function stuck in D state on 2026-11-11 and SIGKILL could not reap it; that was the lag. Full PSU-off is required. The stamp is in `/run`, so it clears on reboot. That is only safe after power was actually removed. |
| `ae7-analog-guard` does **not** `Wants=` the bind | `Restart=on-failure` plus `Wants=ae7-cold-bind` retried a failed bind and hard-locked the box. The guard only re-selects Speakers after an IOMMU fault burst goes quiet. |
| HP/Speaker Auto Detect forced off | Jack unsol plus a BAR2 reroute hung this box. |
| No `iommu=pt` | Leftover CORB DMA targets a bogus address (`0xfff80000`, later also `0xfff40000`). Passthrough would let the card write that physical address. |

Both scripts hardcode `0000:06:00.0`. That address is the AE-7 only while the card is installed. With the card removed it is the MAXIO NVMe (`1e4b:1602`, config dword `4b1e0216`). Cold-bind refuses unless the driver is `pci-stub`. The analog guard does not check the vendor id. It treats any non-`ffffffff` read as a live AE-7 and will sit on the NVMe. Do not teach it to write BAR0/BAR2 to "whatever is at 06:00.0".

## 2026-11-07 incident

Headphones are the AE-7 line-out, through the bundled volume knob, on a TRS cable. The headphone jack was never brought up. Discord runs inside Ferdium. The mic is the Maono AU-PM401, not the AE-7.

Right channel died while the left kept playing, starting as a Discord voice channel was joined. PipeWire and ALSA were balanced (94%, balance 0.00, Front 98/98, PCM 252/252, DAC node `0x02` amps `[0x62 0x62]`). The sink monitor still carried both channels, so the loss was after the software path. Speaker re-select and a PipeWire restart did not bring the right channel back. That session logged 4158 AMD-Vi `IO_PAGE_FAULT`s from leftover CORB DMA. Do not hammer Output Select in a loop. Each select is a pile of BAR2 writes, and the driver logs a PCI config read on every one.

A full PSU-off then brought the card back. Boots at 15:07 and 15:16 both enumerated it healthy (`1102:0010`, `GCAP=0x6401`, config `02111000`, claimed by `pci-stub`). The timer's patched bind got through reset, then `dspload_image()` failed. The kernel logged `ca0132 DSP load image failed` and the next read was `GCAP=0xffff`, PCI config `0xffffffff` (`AE-7 died at after dsp_download`). The same sequence happened on the next boot. The 14:17 boot the same day had logged `ca0132 DSP downloaded and running` with `GCAP=0x6400`, so a PSU cycle does not by itself leave the chip dead. The DSP image transfer is what dropped it off the bus this time.

The lag after that was the bind still inside the kernel. systemd's 90s start timeout fired, and SIGTERM and SIGKILL left the process running (`Processes still around after final SIGKILL`, ~42s CPU). Those reads are uninterruptible PCI waits. Pulling the card is what made the machine usable again. Quarantine did run (`AE-7 quarantined; not watching` at 15:08:54 and 15:18:11). Do not "fix" that by binding again on the same power cycle.

The DSP DMA wait used to time out and still return success, so `dspload_image()` would autostart a half-written image. That is a suspect for the death, not a proven one: the 15:07 and 15:16 logs only say `ca0132 DSP load image failed`, then `GCAP=0xffff`. The codec now returns `-ETIMEDOUT` from a stalled DMA, stops sending verbs once GCAP reads `0xffff`, and does not issue a PCI config read after MMIO has died. The 15:51 bind did not exercise that path. The transfer finished and the kernel logged `ca0132 DSP downloaded and running`.

## Successful bind, 2026-11-07 15:51

Both ears worked after this bind, once the TRS cable was plugged back into the line-out. The card had been out of the machine. This did not relax the rules above. It followed them.

Preconditions that were true before the bind:

- Full PSU-off, card reinstalled, booted with `pci-stub.ids=1102:0010`.
- `ae7-cold-bind.timer` **disabled** and `ae7-analog-guard.service` **stopped**, so boot could not bind on its own. The 15:07 and 15:16 lockups were that timer starting the DSP download.
- Driver was `pci-stub`. PCI config read `02111000` immediately. `GCAP` was not read from the driver yet. No `/run/ae7.dead`. No IOMMU faults.
- Desktop was already up. Nothing was bound during Plymouth or SDDM.

Codec module, built and installed **before** the bind, without reloading `snd-hda-intel` (that module was already serving the GPU HDMI devices):

```bash
make -C /lib/modules/$(uname -r)/build M=/home/rob/ae7-fix/ca0132-oot modules
# ko lands in ca0132-oot/; it was also copied to
# linux-7.1.9/sound/hda/codecs/snd-hda-codec-ca0132.ko
sudo zstd -19 -f -o /usr/lib/modules/$(uname -r)/kernel/sound/hda/codecs/snd-hda-codec-ca0132.ko.zst \
  /home/rob/ae7-fix/ca0132-oot/snd-hda-codec-ca0132.ko
sudo depmod -a $(uname -r)
```

`ca0132-oot/ca0132.c` is a symlink to `linux-7.1.9/sound/hda/codecs/ca0132.c`. The out-of-tree build avoids rebuilding the rest of the HDA tree. `ae7-install-modules.sh` still installs four modules from the tree; this bind only needed the new ca0132 module on disk, because it was not loaded yet.

The bind itself was one manual run, not the timer:

```bash
sudo /usr/local/sbin/ae7-cold-bind.sh
```

What that script did, from `/var/log/ae7-cold-bind.log` at 15:51:40:

1. Refused to continue unless the driver was `pci-stub`.
2. Set `d3cold_allowed=0` and `power/control=on`.
3. Ran `bar2-gpio-hp.py` while the stub still owned the device: read `GCAP=0x6401`, stopped leftover CORB/RIRB (`CORBCTL=0`, `RIRBCTL=0`), set GPIO pin 0 then pin 1 (`BAR2+0x320` ended `0x0101`).
4. `modprobe snd-hda-codec-ca0132` and `modprobe snd-hda-intel`.
5. Unbound `pci-stub`, cleared `driver_override`, and bound `snd_hda_intel`, with a 0.25s PCI-config watchdog and a 25s timeout around the bind write.
6. Config stayed `02111000`. ALSA showed `HDA Creative`. It set **Output Select = Speakers** and **HP/Speaker Auto Detect** off. Log line: `Creative card present; Speakers selected`. Finished 15:51:48. No `/run/ae7.dead`.

Kernel, all in the same second, `snd_hda_codec_ca0132 hdaudioC6D1`:

- `AE-7 dsp_reset begin` then `AE-7 dsp_reset done`
- `AE-7 dspxfr_image begin` then `AE-7 dsp_set_run_state`
- `ca0132 DSP downloaded and running`
- `AE7dbg after dsp_download: GCAP=0x6400 pci=0x101102` (that pci value is `0x00101102`, vendor `1102` device `0010`)
- Setup then set `BAR2 GPIO pin 0 -> 1` and `BAR2 GPIO pin 1 -> 1`

Afterward: default sink `alsa_output.pci-0000_06_00.0.analog-stereo`, both channels 94%, balance 0.00, Front 98/98, load average about 0.18, zero `IO_PAGE_FAULT`s. User confirmed both sides of the headphones.

Right-channel note: the earlier speaker re-select only reasserted GPIO pin 0 and did not bring the right side back. This full init, which sets pin 0 and pin 1 after a completed DSP download, did. Pin 1 is not proven to be the right channel by itself. What is proven is that a pin-0-only reselect was not enough, and a fresh DSP init that sets both pins was.

Still true after this success:

- Do not bind when config is `0xffffffff` or `/run/ae7.dead` exists. The 15:07 and 15:16 boots died inside the same script.
- The timer was disabled for the reinstall boot. It was enabled again the same day at `OnActiveSec=10s` so the next reboot binds after startup apps have launched. The analog guard was inactive after the manual script run. The systemd unit starts the guard. The script alone does not.
- Do not point the guard at `0000:06:00.0` while the AE-7 is removed. That address becomes the MAXIO NVMe.

## Hardware this was developed on

- Creative Sound Blaster AE-7 (CA0132 / ca0113), PCI `06:00.0`
- AMD host, Omarchy (Arch + Limine). Kernels this tree was actually run on: `7.1.9-arch1-2`, then `7.2.15-4-omarchy` (2026-11-25).
- Firmware used: `/lib/firmware/ctefx-desktop.bin`

## 2026-11-25, kernel 7.2.15

Stock 7.2.15 does not fix this card. The cold-bind timer was still enabled after the Omarchy update, it loaded stock `ca0132`, and the machine hard-locked. The card was pulled to recover. `pci-stub.ids=1102:0010` had held the card through early boot.

The same fixes were ported onto 7.2.15, including HP/Speaker Auto Detect forced off against the new presence-detect default. With the timer disabled, one manual bind of a live card (`pci-stub`, config `02111000`, no `/run/ae7.dead`) logged `ca0132 DSP downloaded and running`, left `GCAP` at `0x6400`, left config at `02111000`, selected Speakers, and left Auto Detect off. Analog playback worked on this machine. The timer was enabled only after that. This is still one machine. The patch is `patches/ae7-7.2.15.patch`.

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
7. **Analog dies after leftover CORB DMA goes quiet.** PIO skips *programming* CORB, but firmware restarts CORB/RIRB DMA against a bogus address (`0xfff80000`, later `0xfff40000`). AMD-Vi logs `IO_PAGE_FAULT` on `0000:06:00.0` while it runs. PCM still plays. When the faults stop, analog goes silent. Do **not** use `iommu=pt`. Do **not** write CORB base registers. Clearing `CORBCTL` and `RIRBCTL` run bits is the safe stop. Userspace cannot mmap BAR0 once `snd_hda_intel` owns it (`EINVAL`). The codec watchdog in `ca0132.c` (`ae7_corb_work`) clears those run bits every 2s. The guard re-selects Speakers only after two quiet polls, because a re-select in a one-poll gap on 2026-11-11 16:10 lost to the DMA restarting.

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

Boot bind (GPIO under stub, then one `snd_hda_intel` bind) runs **after** the desktop is up, from `ae7-cold-bind.timer` (10s after `graphical.target`). It must not be wanted by `multi-user.target`. That ordering puts the oneshot `Before=` the target, so a card that falls off the bus holds Plymouth and the login screen, and the NVIDIA flip times out.

If PCI config goes to `0xffffffff` (or the config read wedges), the script writes `/run/ae7.dead` and exits. It does not unbind the function and it does not write `remove`. The guard does not pull the bind back in. Do not restart either unit after that stamp; the card stays dead until a full power-off.

## 2026-11-11 boot lag

Two boots died the same way, then a third came up clean.

- 09:59 boot: stub claimed a live card (`GCAP=0x6401`, config `02111000`). Timer bind at 10:00:04. `dsp_reset` finished, `dspxfr_image` started, and 33 seconds later the kernel logged `AE-7 MMIO dead at chipio_send`, `ca0132 DSP load image failed`, and `AE-7 probe stopped after MMIO died`. The codec abort worked. The installed `/usr/local/sbin/ae7-cold-bind.sh` then ran `mark_dead()`, which unbound `snd_hda_intel` and wrote PCI `remove`. That unbind stayed in D state (`bash -c echo .../unbind`). systemd's 90s timeout, SIGTERM, and SIGKILL left it running (42s CPU). Load went to 14. `nvidia-smi` sat at 2000% CPU. `/run/ae7.dead` was set.
- 10:05 reboot, no power removed: same pattern. `dspxfr_image` at 10:05:44, MMIO dead at `chipio_send` at 10:06:16, then the same unkillable unbind. The machine locked.
- 10:11 reboot: DSP finished in the same second (`ca0132 DSP downloaded and running`), Speakers selected, config stayed `02111000`, no stamp, no D-state tasks. Load was normal. This is the intermittent DSP transfer failure, not a timer-ordering failure.

The source script in `ae7-fix/ae7-cold-bind-boot.sh` now only stamps `/run/ae7.dead`. The installed copy was updated the same morning. Do not rebind on a boot where the stamp exists.

The 32-second gap is one MMIO that never completed. `ctefx-desktop.bin` begins with an HCI list (6 ChipIO pairs at `0x100d20` through `0x100e34`) attached to a 65528-word segment. `dspxfr_one_seg()` started that DMA and then wrote the HCI list while the transfer was still running. There were no IOMMU faults and no `DSP DMA timed out` line, so the DMA itself was not what aborted. The next ChipIO saw `GCAP=0xffff`. When the same download finishes, every step is in the same second, which is the race going the other way. The AE-7 path now writes the HCI list and any unaligned prefix before `dma_set_state(RUN)`. The kernel line is `AE-7 dspxfr chipio before dma`.

The 10:25 power-on boot loaded that module. Log, all in the same second: `chipio before dma, words=65528 rem=0 hci=1`, then the two short remainder segments (`words=72 rem=6` and `words=16 rem=5`), then `ca0132 DSP downloaded and running`. Config stayed `02111000`, Speakers selected, no `/run/ae7.dead`. A warm reset just before that never reached the OS. There is no journal for it. That hang is earlier than the AE-7 timer bind. It happens only after the power button is held in to cut the machine off. A normal Omarchy shutdown, then reboot, does not hang. Recovery from the hung boot is a full PSU-off. Not yet tied to the DSP download.

## 2026-11-24 20:39 lock

Moving the HCI writes before the DMA did not stop the death. The 20:39 boot logged `chipio before dma, words=65528 rem=0 hci=1` at 20:39:39 and then, 57 seconds later, `AE-7 MMIO dead at chipio_send`. DMA had not started. There were zero IOMMU faults. The same HCI list (`dspxfr_hci_write`, six `chipio_write` pairs) finished in the same second on the 20:45 power-on boot and the DSP came up. The failure is one ChipIO MMIO that does not complete until the PCI bridge gives up. 32 seconds and 57 seconds are both in that timeout range.

The bind script had already exited at 20:40:23. Its 25 second timeout gave up while the kernel was still inside the stuck read. It saw the card die, stamped `/run/ae7.dead`, and did not unbind. The kernel logged the death at 20:40:36, after the script was gone. `ca0132_init` still returns 0 on that path, so `snd_hda_intel` stays bound to a codec whose BAR no longer answers. The journal kept going until 20:42:35. In that last stretch the GPU load plugin stopped being able to sample the GPU and the journal ends without a shutdown line. That is the hard lock: a dead AE-7 MMIO stalls the PCI path the GPU is on. There was no unbind and no soft-lockup message. The 20:45 full power-on came up clean.

```
/usr/local/sbin/ae7-cold-bind.sh
```

Analog path that worked: **Output Select = Speakers**. Headphone jack / gain enum did not.

Mixer: leave **HP/Speaker Auto Detect** off.

After bind, `stop-corb-dma.py` clears leftover CORB/RIRB DMA. `ae7-analog-guard.service` is started by the bind unit (not by `multi-user.target`) and re-selects Speakers when an IOMMU fault burst goes quiet.

## Install on this kernel (Omarchy / Arch)

From a tree that already contains the built `.ko` files:

```bash
pkexec /usr/local/sbin/ae7-install-modules.sh
sudo systemctl enable --now ae7-cold-bind.timer
```

Enable the **timer**, not the service. `ae7-install-guard.sh` disables `ae7-cold-bind.service` and `ae7-analog-guard.service` on purpose. Wanting the oneshot from `multi-user.target` is the login-screen hang described above. The timer starts the oneshot, and the oneshot starts the guard.

Or bind once without installing:

```bash
pkexec bash cold-bind-ca0132.sh
```

Building the out-of-tree codec only:

```bash
make -C /lib/modules/$(uname -r)/build M=$PWD/ca0132-oot modules
```

`ca0132-oot/ca0132.c` is a symlink into a local kernel source checkout (not shipped). Apply `patches/ae7-ca0132-intel-controller.patch` on Linux 7.1.9 `sound/hda/`. Apply `patches/ae7-7.2.15.patch` on Linux 7.2.15 `sound/hda/` (the 7.1.9 patch does not apply cleanly; 7.2.15 adds a `QUIRK_GENERIC` path). Rebuild `snd-hda-core`, `snd-hda-intel`, and `snd-hda-codec-ca0132`. Leave the distro `snd-hda-codec` in place on 7.2.15. Do not drop `pci-stub`. Do not enable the timer until one manual bind of a live card has finished with `ca0132 DSP downloaded and running` and PCI config still `02111000`.

## Kernel files touched

- `sound/hda/controllers/intel.c` — AE-7 PIO + GCAP `0xffff` abort
- `sound/hda/core/controller.c` — skip CORB programming when PIO; **stop leftover CORB/RIRB DMA**
- `sound/hda/codecs/ca0132.c` — DSP/BAR2 policy, auto-detect lock, EQ init sync

## License

Kernel patches follow the Linux kernel (`GPL-2.0-only`). Helper scripts in this repo are the same unless a file says otherwise.
