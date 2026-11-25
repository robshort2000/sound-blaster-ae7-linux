#!/usr/bin/env python3
"""Stop leftover AE-7 CORB/RIRB DMA. PIO verbs do not use it.

Firmware/reset can leave CORB running against a bogus address. On the
AMD test machine that showed up as AMD-Vi IO_PAGE_FAULT at 0xfff80000.
That DMA eventually kills analog while PCM still looks healthy.

DEV is the AE-7 bus address on the test machine. Change it to yours
(`lspci -d 1102:0010`).

Do NOT program CORB/RIRB buffer addresses. Do NOT rebind. Abort if GCAP
dies. Safe to run while snd_hda_intel is bound.
"""
import os
import sys
import mmap
import struct

DEV = "/sys/bus/pci/devices/0000:06:00.0"
# HD-audio BAR0
GCAP = 0x00
CORBLBASE = 0x40
CORBUBASE = 0x44
CORBCTL = 0x4c
RIRBCTL = 0x5c


def cfg4():
    with open(f"{DEV}/config", "rb") as f:
        return f.read(4)


def main():
    if not os.path.isdir(DEV):
        print("AE-7 PCI device missing", flush=True)
        return 1
    c = cfg4()
    print(f"pci {c.hex()}", flush=True)
    if c == b"\xff\xff\xff\xff":
        print("PCI dead; refuse", flush=True)
        return 2

    fd = os.open(f"{DEV}/resource0", os.O_RDWR)
    try:
        # Full BAR (16KiB). 0x100 fails EINVAL; a bound snd_hda_intel also
        # refuses mmap — that is expected, skip rather than fight the driver.
        try:
            m = mmap.mmap(fd, 0x4000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        except OSError as e:
            print(f"BAR0 mmap skipped ({e}); driver likely owns the BAR", flush=True)
            return 0
        gcap = struct.unpack_from("<H", m, GCAP)[0]
        corb_lo = struct.unpack_from("<I", m, CORBLBASE)[0]
        corb_hi = struct.unpack_from("<I", m, CORBUBASE)[0]
        corbctl = m[CORBCTL]
        rirbctl = m[RIRBCTL]
        print(
            f"before GCAP={gcap:#06x} CORBCTL={corbctl:#04x} RIRBCTL={rirbctl:#04x} "
            f"CORBADDR={corb_hi:#010x}{corb_lo:08x}",
            flush=True,
        )
        if gcap == 0xffff:
            print("GCAP dead; refuse", flush=True)
            m.close()
            return 3

        m[CORBCTL] = 0
        m[RIRBCTL] = 0
        m.flush()

        gcap2 = struct.unpack_from("<H", m, GCAP)[0]
        corbctl2 = m[CORBCTL]
        rirbctl2 = m[RIRBCTL]
        c2 = cfg4()
        print(
            f"after  GCAP={gcap2:#06x} CORBCTL={corbctl2:#04x} RIRBCTL={rirbctl2:#04x} "
            f"pci={c2.hex()}",
            flush=True,
        )
        m.close()
        if c2 == b"\xff\xff\xff\xff" or gcap2 == 0xffff:
            print("FAIL card died after CORBCTL stop; do not rebind", flush=True)
            return 4
    finally:
        os.close(fd)
    print("corb-dma stopped", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
