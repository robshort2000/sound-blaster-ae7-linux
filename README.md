# Sound Blaster AE-7 on Linux

Workaround for a Creative Sound Blaster AE-7 (`PCI 1102:0010`, subsystem `1102:0081`) whose CA0132 sits behind an ASMedia ASM1083/1085 rev 03 bridge. Stock `snd_hda_intel` hard-locks that combination during probe.

Upstream: [kernel bug 217510](https://bugzilla.kernel.org/show_bug.cgi?id=217510). The same lock is also reported as [221495](https://bugzilla.kernel.org/show_bug.cgi?id=221495), [221614](https://bugzilla.kernel.org/show_bug.cgi?id=221614), and Debian [#1115581](https://bugs.debian.org/1115581). AE-9 cards with the same bridge are [219552](https://bugzilla.kernel.org/show_bug.cgi?id=219552). AE-5 and AE-5 Plus (`1102:0012`) do not use that bridge and are not this failure. Older Sound Blaster Z and ZxR cards are not this CORBRP hard lock. Early AE-7 boards with a Tundra Tsi381 bridge (`10e3:8111`) stay up at probe and have a different "analog goes quiet" problem.

Developed on Omarchy, which is Arch with Limine. The kernel behavior is what matters. The bootloader, GPU, and slot address below are only how they showed up on the one machine this was run on.

## Warning — use at your own risk

**Vibe-coded. Tested on one machine only. Use at your own risk.**

These patched drivers were written against a single workstation and have not been tested on any other system. The 7.2.15 port was confirmed only on that same machine, on 2026-11-25, with analog playback after one manual bind.

- They can **hard-lock the box**, **kill the PCI function until a PSU cycle**, or **IRQ-storm** if you bind a dead card.
- Do **not** treat this as an upstream-quality patch set.
- Keep `pci-stub` on `1102:0010` until a **cold** probe of the patched `snd-hda-intel` is proven on your machine.
- After a failed probe the function often sits in D3cold / `0xffffffff` until **power is removed** (full PSU off). Unbind is not enough. Leave it alone for the rest of that power cycle.
- A kernel upgrade overwrites `/usr/lib/modules/.../snd-hda-*.ko.zst` on Arch. Rebuild after each upgrade. Other distributions install modules differently.

If analog already works with stock kernels on your AE-7, you do not need this.

## Read this before the logs

`lspci -d 1102:0010` prints your card's bus address. The helper scripts hardcode `0000:06:00.0` because that is where the AE-7 enumerated on the test machine. Change `DEV` (and the matching systemd `ConditionPathExists=`) before you run them.

The test machine, so the logs below have a referent:

- Sound Blaster AE-7, CA0132, subsystem `1102:0081`, behind an ASMedia ASM1083/1085 rev 03 bridge. Its bus address there was `0000:06:00.0`.
- AMD CPU. Leftover CORB DMA was logged as AMD-Vi `IO_PAGE_FAULT`. An Intel board reports this probe lock as an NMI or a machine check, and it will not print that AMD-Vi line. The analog guard matches the AMD-Vi text for `0000:06:00.0`; edit that match for your IOMMU and your bus address.
- NVIDIA GPU on the same platform. A stuck AE-7 completion stalled that GPU too, which is why `nvidia-smi` spun and the display modeset timed out. Any GPU sharing the platform can stall the same way. The GPU vendor is not part of the patch.
- On that motherboard, removing the AE-7 left a MAXIO NVMe (`1e4b:1602`) at `0000:06:00.0`. That is slot wiring on one board. The analog guard does not check the vendor id, so it will keep polling whatever device sits at the address you configured.
- Kernels actually run: `7.1.9-arch1-2`, then `7.2.15-4-omarchy`.
- Firmware that worked: `/lib/firmware/ctefx-desktop.bin`.
- Listening was the line-out through the card's volume knob on a TRS cable. The headphone jack was never brought up. The microphone in the voice-call notes was a separate USB device, not the AE-7 input.

## Why the guards exist

Each one is a scar from a lockup on the test machine. The analog reset there was `amixer -c Creative sset 'Output Select' Speakers` with **HP/Speaker Auto Detect** left off. One bind of a **live** card, after the desktop is up, is the path that played audio. What locked the box was a second bind after PCI config was `0xffffffff`, a bind ordered before the login screen, or the analog guard pulling the bind back in.

| Piece | Why it is there |
|---|---|
| `pci-stub.ids=1102:0010` | Stock udev probe waits on `CORBRP.RST` with IRQs off and hard-locks (kernel bug 217510). The card stays on the stub until one patched bind. The id is the AE-7 device, not a bus address. |
| `ae7-cold-bind.timer` (the service is not wanted by `multi-user.target`) | Wanting the oneshot ordered it `Before=multi-user`. On the test machine that held Plymouth and SDDM, and the NVIDIA modeset timed out, because a stuck PCI read stalls the platform. The timer fires 10s after `graphical.target`, so the desktop is already up. `Restart=no`, `TimeoutStartSec=90`. Keep the bind after the display is up on your machine too. The display server does not have to be SDDM. |
| `/run/ae7.dead` | PCI config `0xffffffff`, or a config read that wedges, means the function is dead. The script stamps this file and does not unbind or remove the device. A second bind of a dead card hard-locks. On 2026-11-11 an unbind of a dead function stuck in D state and SIGKILL could not reap it. Full PSU-off is required. The stamp is in `/run`, so it clears on reboot. That reboot is safe only after power was actually removed. |
| `ae7-analog-guard` does not `Wants=` the bind | `Restart=on-failure` plus `Wants=ae7-cold-bind` retried a failed bind and hard-locked the box. The guard only re-selects Speakers after an IOMMU fault burst goes quiet. |
| HP/Speaker Auto Detect forced off | Jack unsol plus a BAR2 reroute hung the test machine. |
| No `iommu=pt` | Leftover CORB DMA targets a bogus address (`0xfff80000`, later also `0xfff40000`). On the test machine, passthrough would have let the card write that physical address. |

## 2026-11-07 incident

On the test machine, the listening path was the line-out and the bundled volume knob. A voice call was joined. PipeWire and ALSA were balanced (94%, balance 0.00, Front 98/98, PCM 252/252, DAC node `0x02` amps `[0x62 0x62]`). The sink monitor still carried both channels, so the loss was after the software path. The microphone was a separate USB device.

The right channel died while the left kept playing. Speaker re-select and a PipeWire restart did not bring the right side back. That session logged 4158 AMD-Vi `IO_PAGE_FAULT`s from leftover CORB DMA. Hammering Output Select makes this worse: each select is a pile of BAR2 writes, and the driver logs a PCI config read on every one.

A full PSU-off then brought the card back. Boots at 15:07 and 15:16 both enumerated it healthy (`1102:0010`, `GCAP=0x6401`, config `02111000`, claimed by `pci-stub`). The timer's patched bind got through reset, then `dspload_image()` failed. The kernel logged `ca0132 DSP load image failed` and the next read was `GCAP=0xffff`, PCI config `0xffffffff` (`AE-7 died at after dsp_download`). The same sequence happened on the next boot. The 14:17 boot the same day had logged `ca0132 DSP downloaded and running` with `GCAP=0x6400`, so a PSU cycle does not by itself leave the chip dead. The DSP image transfer is what dropped it off the bus this time.

The lag after that was the bind still inside the kernel. systemd's 90s start timeout fired, and SIGTERM and SIGKILL left the process running (`Processes still around after final SIGKILL`, ~42s CPU). Those reads are uninterruptible PCI waits. Pulling the card is what made the machine usable again. Quarantine did run (`AE-7 quarantined; not watching` at 15:08:54 and 15:18:11). Leave a dead card alone for the rest of that power cycle.

The DSP DMA wait used to time out and still return success, so `dspload_image()` would autostart a half-written image. That is a suspect for the death, not a proven one: the 15:07 and 15:16 logs only say `ca0132 DSP load image failed`, then `GCAP=0xffff`. The codec now returns `-ETIMEDOUT` from a stalled DMA, stops sending verbs once GCAP reads `0xffff`, and does not issue a PCI config read after MMIO has died. The 15:51 bind did not exercise that path. The transfer finished and the kernel logged `ca0132 DSP downloaded and running`.

## Successful bind, 2026-11-07 15:51

Both ears worked after this bind, once the TRS cable was plugged back into the line-out. The card had been out of the machine. This did not relax the rules above. It followed them.

Preconditions that were true before the bind:

- Full PSU-off, card reinstalled, booted with `pci-stub.ids=1102:0010`.
- `ae7-cold-bind.timer` disabled and `ae7-analog-guard.service` stopped, so boot could not bind on its own. The 15:07 and 15:16 lockups were that timer starting the DSP download.
- Driver was `pci-stub`. PCI config read `02111000` immediately. No `/run/ae7.dead`. No IOMMU faults.
- Desktop was already up. Nothing was bound during early boot.

Codec module, built and installed **before** the bind. `snd-hda-intel` was already serving the test machine's GPU HDMI, so it was not reloaded:

```bash
make -C /lib/modules/$(uname -r)/build M=/home/rob/ae7-fix/ca0132-oot modules
sudo zstd -19 -f -o /usr/lib/modules/$(uname -r)/kernel/sound/hda/codecs/snd-hda-codec-ca0132.ko.zst \
  /home/rob/ae7-fix/ca0132-oot/snd-hda-codec-ca0132.ko
sudo depmod -a $(uname -r)
```

`ca0132-oot/ca0132.c` is a symlink into a local kernel checkout that is not shipped. The out-of-tree build avoids rebuilding the rest of the HDA tree. On Arch the module file is `.ko.zst`. The paths above are that machine's tree.

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

Kernel, all in the same second, `snd_hda_codec_ca0132 hdaudioC6D1` (the codec index will differ on another machine):

- `AE-7 dsp_reset begin` then `AE-7 dsp_reset done`
- `AE-7 dspxfr_image begin` then `AE-7 dsp_set_run_state`
- `ca0132 DSP downloaded and running`
- `AE7dbg after dsp_download: GCAP=0x6400 pci=0x101102` (that pci value is `0x00101102`, vendor `1102` device `0010`)
- Setup then set `BAR2 GPIO pin 0 -> 1` and `BAR2 GPIO pin 1 -> 1`

Afterward the default sink was the AE-7 analog device, both channels 94%, balance 0.00, Front 98/98, load average about 0.18, zero `IO_PAGE_FAULT`s. Both sides of the headphones were confirmed by ear.

Right-channel note: an earlier speaker re-select only reasserted GPIO pin 0 and did not bring the right side back. This full init, which sets pin 0 and pin 1 after a completed DSP download, did. Pin 1 is not proven to be the right channel by itself. What is proven is that a pin-0-only reselect was not enough, and a fresh DSP init that sets both pins was.

Still true after this success:

- Skip the bind when config is `0xffffffff` or `/run/ae7.dead` exists. The 15:07 and 15:16 boots died inside the same script.
- The timer was disabled for the reinstall boot, then enabled again the same day at `OnActiveSec=10s` so the next reboot binds after the desktop is up. The analog guard was inactive after the manual script run. The systemd unit starts the guard. The script alone does not.
- Stop the guard if the AE-7 is removed. On the test machine the old bus address became an NVMe.

## 2026-11-25, kernel 7.2.15

Stock 7.2.15 does not fix this card. On the test machine the cold-bind timer was still enabled after a distro update, it loaded stock `ca0132`, and the machine hard-locked. The card was pulled to recover. `pci-stub.ids=1102:0010` had held the card through early boot, so the lock was the timer's bind, not enumeration.

The same fixes were ported onto 7.2.15, including HP/Speaker Auto Detect forced off against the new presence-detect default. With the timer disabled, one manual bind of a live card (`pci-stub`, config `02111000`, no `/run/ae7.dead`) logged `ca0132 DSP downloaded and running`, left `GCAP` at `0x6400`, left config at `02111000`, selected Speakers, and left Auto Detect off. Analog playback worked on that machine. The timer was enabled only after that. The patch is `patches/ae7-7.2.15.patch`. It applies to Linux 7.2.15 `sound/hda/`. The 7.1.9 patch does not apply cleanly, because 7.2.15 adds a `QUIRK_GENERIC` path in `ca0132.c`.

## What is wrong

Stock `snd_hda_intel` + `snd_hda_codec_ca0132` on this AE-7:

1. **Boot hang.** CORB DMA reset wait (`CORBRP.RST`) never completes. With IRQs off during udev probe this **hard-locks** the machine (bug 217510).
2. **Dead MMIO.** A `GCAP` read of `0xffff` was treated as a valid capability word, inventing huge stream counts and a bogus codec mask.
3. **BAR2 / ca0113 is lethal after HDA CRST.** Several Windows-matching sequences kill PCI config (`0xffffffff`) on a cold card:
   - `ca0132_mmio_init_ae5()` (BAR2 `0x1c` / table)
   - `ae5_register_set()` SFR `writeb`/`writel` (before **or** after DSP)
   - bulk `mmio_command_set` **before** DSP is up
   - HP/Speaker **Auto Detect** (jack unsol + BAR2 reroute) hung the test machine
4. **DSP firmware pick.** This AE-7 loads `ctefx-desktop.bin`, not `ctefx.bin`.
5. **Analog route.** Even with DSP alive, line-out stays silent until BAR2 GPIO (pins 0/1) and **post-DSP** `ca0113_mmio_command_set`. GPIO under the stub is wiped by CRST; the driver re-applies GPIO after DSP.
6. **EQ sliders.** Mixer can show FX: Equalizer **On** while DSP req 9 is still off (`pe_switch_set` used to run only on resume). Band widgets are volume-only, so they never unmute the EQ block. Toggle Equalizer off/on, or use the patched init that always pushes OutFX to the DSP.
7. **Analog dies after leftover CORB DMA goes quiet.** PIO skips *programming* CORB, but firmware DMA-reads a fixed IOVA (`0xfff80000`, later also `0xfff40000`). On the AMD test machine, AMD-Vi logged `IO_PAGE_FAULT` for the card's bus address while it ran. PCM still plays. When the faults stop, analog goes silent. A long fault storm stalls the GPU on the same platform and the display hard-locks. Leave `iommu=pt` unset. Leave the CORB base registers alone. Clearing `CORBCTL` and `RIRBCTL` run bits is the safe stop, but on 2026-11-25 the 2s watchdog never observed the run bit across 2350 faults, so it does not stop this storm. `snd-hda-intel` reserves both IOVAs in the DMA API allocator and then maps one dummy page at each (`IOMMU_READ|IOMMU_WRITE`) during probe, so the reads complete and the IOMMU does not fault. The reserve is required. A raw `iommu_map()` of `0xfff80000` is also where the DSP loader's 512 KB buffer is placed, and that collision fails the download. See 2026-11-26. Userspace cannot mmap BAR0 once `snd_hda_intel` owns it (`EINVAL`). The codec watchdog in `ca0132.c` (`ae7_corb_work`) still clears those run bits every 2s. The guard re-selects Speakers only after two quiet polls, because a re-select in a one-poll gap on 2026-11-11 16:10 lost to the DMA restarting.

## What we did not keep (lethal on this card)

| Attempt | Result |
|---|---|
| CORB DMA / wait for CORBRP | udev hang |
| `mmio_init_ae5` after CRST | PCI `0xffffffff` |
| `ae5_register_set` SFR writes (incl. post-DSP) | DSP death / hang |
| mmio_init table under stub on a **cold** card | GCAP `0xffff` |
| HP/Speaker Auto Detect | system hang |

## What worked on the test machine

Keep **pci-stub** on the kernel command line so the stock probe never runs:

```
pci-stub.ids=1102:0010
```

On the test machine that line is added from `/etc/limine-entry-tool.d/ae7.conf`, because the bootloader is Limine. The parameter is the part that matters. Add it the way your bootloader expects.

Patched `snd-hda-intel` matches subsystem `1102:0081` and uses **PIO commands** (`AZX_DCAPS_PIO_COMMANDS`) and skips the CORB reset wait. Other `1102:0010` devices keep the stock entry.

Patched `ca0132`:

- skip `mmio_init_ae5` after CRST
- skip `ae5_register_set` unless module param `ae7_bar2=1` (unsafe)
- block BAR2 `mmio_command_set` until `DSP_DOWNLOADED`
- lock HP auto-detect off
- push PlayEnhancement / OutFX to DSP on first init (so EQ actually enables)
- GPIO + `mmio_command_set` after DSP

The boot bind (GPIO under the stub, then one `snd_hda_intel` bind) runs **after** the desktop is up, from `ae7-cold-bind.timer` (10s after `graphical.target`). It must not be wanted by `multi-user.target`. That ordering puts the oneshot `Before=` the target, so a card that falls off the bus holds the login screen. On the test machine the NVIDIA modeset timed out with it.

If PCI config goes to `0xffffffff` (or the config read wedges), the script writes `/run/ae7.dead` and exits. It does not unbind the function and it does not write `remove`. The guard does not pull the bind back in. Leave both units alone after that stamp. The card stays dead until a full power-off.

## 2026-11-11 boot lag

Two boots on the test machine died the same way, then a third came up clean.

- 09:59 boot: stub claimed a live card (`GCAP=0x6401`, config `02111000`). Timer bind at 10:00:04. `dsp_reset` finished, `dspxfr_image` started, and 33 seconds later the kernel logged `AE-7 MMIO dead at chipio_send`, `ca0132 DSP load image failed`, and `AE-7 probe stopped after MMIO died`. The codec abort worked. The installed `/usr/local/sbin/ae7-cold-bind.sh` then ran `mark_dead()`, which unbound `snd_hda_intel` and wrote PCI `remove`. That unbind stayed in D state. systemd's 90s timeout, SIGTERM, and SIGKILL left it running (42s CPU). Load went to 14. `nvidia-smi` sat at 2000% CPU because the GPU driver shares the stalled platform. `/run/ae7.dead` was set.
- 10:05 reboot, no power removed: same pattern. `dspxfr_image` at 10:05:44, MMIO dead at `chipio_send` at 10:06:16, then the same unkillable unbind. The machine locked.
- 10:11 reboot: DSP finished in the same second (`ca0132 DSP downloaded and running`), Speakers selected, config stayed `02111000`, no stamp, no D-state tasks. Load was normal. This is the intermittent DSP transfer failure, not a timer-ordering failure.

The source script in `ae7-cold-bind-boot.sh` now only stamps `/run/ae7.dead`. The installed copy was updated the same morning. A boot where the stamp exists is finished. Do not bind again until power has been removed.

The 32-second gap is one MMIO that never completed. `ctefx-desktop.bin` begins with an HCI list (6 ChipIO pairs at `0x100d20` through `0x100e34`) attached to a 65528-word segment. `dspxfr_one_seg()` started that DMA and then wrote the HCI list while the transfer was still running. There were no IOMMU faults and no `DSP DMA timed out` line, so the DMA itself was not what aborted. The next ChipIO saw `GCAP=0xffff`. When the same download finishes, every step is in the same second. The AE-7 path now writes the HCI list and any unaligned prefix before `dma_set_state(RUN)`. The kernel line is `AE-7 dspxfr chipio before dma`.

The 10:25 power-on boot loaded that module. Log, all in the same second: `chipio before dma, words=65528 rem=0 hci=1`, then the two short remainder segments (`words=72 rem=6` and `words=16 rem=5`), then `ca0132 DSP downloaded and running`. Config stayed `02111000`, Speakers selected, no `/run/ae7.dead`. A warm power-on just before that never reached the OS. There is no journal for it. That hang is earlier than the AE-7 timer bind. On this machine it showed up only after the power button was held in to cut power. A normal shutdown, then reboot, did not hang. Recovery from the hung boot was a full PSU-off. It is not yet tied to the DSP download.

## 2026-11-24 20:39 lock

Moving the HCI writes before the DMA did not stop the death. The 20:39 boot logged `chipio before dma, words=65528 rem=0 hci=1` at 20:39:39 and then, 57 seconds later, `AE-7 MMIO dead at chipio_send`. DMA had not started. There were zero IOMMU faults. The same HCI list (`dspxfr_hci_write`, six `chipio_write` pairs) finished in the same second on the 20:45 power-on boot and the DSP came up. The failure is one ChipIO MMIO that does not complete until the PCI bridge gives up. 32 seconds and 57 seconds are both in that timeout range.

The bind script had already exited at 20:40:23. Its 25 second timeout gave up while the kernel was still inside the stuck read. It saw the card die, stamped `/run/ae7.dead`, and did not unbind. The kernel logged the death at 20:40:36, after the script was gone. `ca0132_init` still returns 0 on that path, so `snd_hda_intel` stays bound to a codec whose BAR no longer answers. The journal kept going until 20:42:35. In that last stretch the GPU load sampler stopped being able to read the GPU, and the journal ends without a shutdown line. That is the hard lock: a dead AE-7 MMIO stalls the PCI path the GPU is on. The test machine's GPU is NVIDIA, which is why that sampler was `nvidia-smi`. There was no unbind and no soft-lockup message. The 20:45 full power-on came up clean.

Analog path that worked: **Output Select = Speakers**. The headphone jack and its gain enum did not.

Mixer: leave **HP/Speaker Auto Detect** off.

After bind, `stop-corb-dma.py` clears leftover CORB/RIRB DMA. `ae7-analog-guard.service` is started by the bind unit (not by `multi-user.target`) and re-selects Speakers when an IOMMU fault burst goes quiet.

## 2026-11-26 dummy IOVA stole the DSP buffer

On 2026-11-25 at 15:16, `snd-hda-intel` started mapping a dummy page at `0xfff40000` and `0xfff80000` with `iommu_map()` during probe. That stopped the AMD-Vi fault storm. It did not tell the DMA API's IOVA allocator. The last boot that logged `ca0132 DSP downloaded and running` was 15:06 the same day, before that module was installed.

The AE-7 streaming mask is 32-bit (`GCAP` has no 64OK). The DSP loader asks for a 512 KB write-combining buffer (`DSP_DMA_WRITE_BUFLEN_INIT` times 2). The allocator hands a size-aligned buffer out at the top of the 32-bit aperture, which is `0xfff80000`. That is the second dummy page. `dma_map_single()` fails.

`dspload_image()` then returns before any segment is written. The kernel logs `AE-7 dspxfr_image begin` and, in the same second, `ca0132 DSP load image failed`. There is no `chipio before dma` line and no `MMIO dead` line. `GCAP` stays `0x6400` and PCI config stays `02111000`. The card is not dead. A full PSU-off does not clear it, because the next probe maps the same two pages. Three boots on 2026-11-26 failed this way. Two of those cold-bind runs also exited 1 because the Creative ALSA card had not appeared within the script's 8 second wait. The bind that did see the card still had a failed DSP.

WirePlumber then opens the playback device and sets hardware parameters. That is the same write-combining path. `snd_dma_wc_alloc()` frees `dmab->area` when `dma_map_single()` fails, and that pointer is still NULL. `free_pages_exact()` faults. The process is noted as exited with IRQs disabled, and the analog PCM stays `OPEN` under the dead pid. WirePlumber's main thread is a zombie while its other threads stay alive, so systemd does not restart it. `pipewire-pulse` accepts the socket and never finishes the handshake. `pactl info` hangs. Battle.net's voice init blocks in ALSA's Pulse connect, 30 seconds at a time, for about two minutes, and only then creates the window. The journal line is `PulseAudio: Unable to connect: Timeout`. The client log resumes at `Audio device monitor using already-initialized COM`.

The fix reserves each dummy IOVA with `reserve_iova()` on the DMA cookie before `iommu_map()`. If the reserve fails, that page is left unmapped. A raw `iommu_map()` of those addresses is the bug. Do not load a module that only does the map.

The 08:58 reboot with the rebuilt module logged `AE-7: reserved IOVA` for both addresses, then `dummy page at IOVA`, then `chipio before dma` for the 65528-word segment and the two short remainders, then `ca0132 DSP downloaded and running`. Cold bind selected Speakers. The default sink was `alsa_output.pci-0000_06_00.0.analog-stereo`. WirePlumber stayed up. `pactl` answered. The analog PCM was closed. Config stayed `02111000`. There was no `/run/ae7.dead`.

## Install

Build the modules for the kernel you are actually running. Apply `patches/ae7-ca0132-intel-controller.patch` on Linux 7.1.9 `sound/hda/`. Apply `patches/ae7-7.2.15.patch` on Linux 7.2.15 `sound/hda/`. Rebuild `snd-hda-core`, `snd-hda-intel`, and `snd-hda-codec-ca0132`. On the 7.2.15 test, the distro `snd-hda-codec` was left in place because that file was not patched.

`ca0132-oot/ca0132.c` is a symlink into a local kernel source checkout (not shipped). On Arch:

```bash
make -C /lib/modules/$(uname -r)/build M=$PWD/ca0132-oot modules
```

From a tree that already contains the built `.ko` files, the test machine installs with:

```bash
pkexec /usr/local/sbin/ae7-install-modules.sh
sudo systemctl enable ae7-cold-bind.timer
```

Enable the **timer**, not the service. `ae7-install-guard.sh` disables `ae7-cold-bind.service` and `ae7-analog-guard.service` on purpose. Wanting the oneshot from `multi-user.target` is the login-screen hang described above. The timer starts the oneshot, and the oneshot starts the guard.

Enable the timer only after one manual bind of a live card has logged `ca0132 DSP downloaded and running` and PCI config is still `02111000`. Change the hardcoded bus address first.

`ae7-install-modules.sh` checks that the module vermagic matches `uname -r`, copies the three patched modules into the Arch module tree as `.ko.zst`, and runs `depmod`. It does not bind the card.

## Kernel files touched

- `sound/hda/controllers/intel.c` — AE-7 subsystem `1102:0081` uses PIO; `GCAP` `0xffff` aborts probe; dummy IOVAs are reserved in the DMA allocator before they are mapped
- `sound/hda/core/controller.c` — skip CORB programming when PIO; stop leftover CORB/RIRB DMA; a `0xffff` read returns
- `sound/hda/codecs/ca0132.c` — DSP/BAR2 policy, auto-detect forced off, EQ init sync

## License

Kernel patches follow the Linux kernel (`GPL-2.0-only`). Helper scripts in this repo are the same unless a file says otherwise.
