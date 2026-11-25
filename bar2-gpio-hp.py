#!/usr/bin/env python3
"""AE-7 BAR2 GPIO only (headphone/speaker amp enable). pci-stub, D0.

Does not run mmio_init (that table killed a cold card). Two writew to 0x320.
Abort if GCAP/PCI dies.
"""
import os
import sys
import mmap
import struct

DEV = "/sys/bus/pci/devices/0000:06:00.0"


def cfg():
    with open(f"{DEV}/config", "rb") as f:
        return f.read(16)


def enable():
    with open(f"{DEV}/config", "r+b") as f:
        f.seek(4)
        f.write(struct.pack("<H", 0x0006))
        f.flush()


def alive(m0, tag):
    c = cfg()
    g = struct.unpack_from("<H", m0, 0)[0] if c[:4] != b"\xff" * 4 else 0xffff
    dead = c[:4] == b"\xff" * 4 or g == 0xffff
    print(f"{'FAIL' if dead else 'ok'} {tag}: GCAP={g:#06x} cfg={c[:4].hex()}",
          flush=True)
    return not dead


def main():
    print("bar2-gpio-hp starting", flush=True)
    c = cfg()
    print("config", c.hex(), flush=True)
    if c[:4] == b"\xff" * 4:
        print("PCI dead; refuse", flush=True)
        return 1
    enable()
    fd0 = os.open(f"{DEV}/resource0", os.O_RDWR)
    fd2 = os.open(f"{DEV}/resource2", os.O_RDWR)
    try:
        m0 = mmap.mmap(fd0, 0x100, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        m2 = mmap.mmap(fd2, 0x400, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        if not alive(m0, "start"):
            return 2
        gpio = struct.unpack_from("<H", m2, 0x320)[0]
        print(f"BAR2+0x320 before {gpio:#06x}", flush=True)
        # Stop leftover CORB/RIRB DMA before bind. PIO will not use it;
        # leaving it running IOMMU-faults at 0xfff80000 and later kills analog.
        corbctl = m0[0x4c]
        rirbctl = m0[0x5c]
        print(f"CORBCTL={corbctl:#04x} RIRBCTL={rirbctl:#04x} before stop", flush=True)
        m0[0x4c] = 0
        m0[0x5c] = 0
        m0.flush()
        if not alive(m0, "corb dma stop"):
            return 5
        # pin 0 on, then pin 1 on (ae7_setup_defaults)
        struct.pack_into("<H", m2, 0x320, 0x0100)
        m2.flush()
        if not alive(m0, "gpio pin0 on"):
            return 3
        struct.pack_into("<H", m2, 0x320, 0x0101)
        m2.flush()
        if not alive(m0, "gpio pin1 on"):
            return 4
        gpio = struct.unpack_from("<H", m2, 0x320)[0]
        print(f"BAR2+0x320 after {gpio:#06x}", flush=True)
        print("gpio-hp done", flush=True)
        m0.close()
        m2.close()
    finally:
        os.close(fd0)
        os.close(fd2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
