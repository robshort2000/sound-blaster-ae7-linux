#!/usr/bin/env python3
"""AE-7 BAR2 mmio_init + speaker jack routing while HDA is still in reset.

Run as root on pci-stub, D0. Abort if PCI dies. Do not run after snd_hda_intel
owns the device (post-CRST BAR2 drops the function).
"""
import os
import sys
import mmap
import struct
import time

DEV = "/sys/bus/pci/devices/0000:06:00.0"
INIT_ADDR = [
    0x400, 0x42c, 0x46c, 0x4ac, 0x4ec, 0x43c, 0x47c, 0x4bc, 0x4fc, 0x408,
    0x100, 0x410, 0x40c, 0x100, 0x100, 0x830, 0x86c, 0x800, 0x86c, 0x800,
    0x804, 0x20c, 0x01c, 0xc0c, 0xc00, 0xc04, 0xc0c, 0xc0c, 0xc0c, 0xc0c,
    0xc08, 0xc08, 0xc08, 0xc08, 0xc08, 0xc04, 0x01c,
]
INIT_DATA = [
    0x00000001, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000001,
    0x00000600, 0x00000014, 0x00000001, 0x0000060f, 0x0000070f,
    0x00000aff, 0x00000000, 0x0000006b, 0x00000001, 0x0000006b,
    0x00000057, 0x00800001, 0x00880680, 0x00000080, 0x00000030,
    0x00000000, 0x00000000, 0x00000003, 0x00000003, 0x00000003,
    0x00000001, 0x000000f1, 0x00000001, 0x000000c7, 0x000000c1,
    0x00000080, 0x00880680,
]
SPK = [
    (0x30, 0x2e, 0x00), (0x30, 0x30, 0x00), (0x48, 0x0d, 0x40),
    (0x48, 0x17, 0x00), (0x48, 0x19, 0x00), (0x30, 0x32, 0x3f),
]


def cfg():
    with open(f"{DEV}/config", "rb") as f:
        return f.read(16)


def enable():
    with open(f"{DEV}/config", "r+b") as f:
        f.seek(4)
        f.write(struct.pack("<H", 0x0006))
        f.flush()


def gcap(m0):
    return struct.unpack_from("<H", m0, 0)[0]


def alive(m0, tag):
    c = cfg()
    g = gcap(m0) if c[:4] != b"\xff" * 4 else 0xffff
    dead = c[:4] == b"\xff" * 4 or g == 0xffff
    print(f"{'FAIL' if dead else 'ok'} {tag}: GCAP={g:#06x} cfg={c[:4].hex()}",
          flush=True)
    return not dead


def cmd(m2, group, target, value):
    struct.pack_into("<I", m2, 0x210, 0x0000007e)
    struct.unpack_from("<I", m2, 0x210)
    struct.pack_into("<I", m2, 0x210, 0x0000005a)
    struct.unpack_from("<I", m2, 0x210)
    struct.unpack_from("<I", m2, 0x210)
    struct.pack_into("<I", m2, 0x20c, 0x00800005)
    struct.pack_into("<I", m2, 0x804, group)
    struct.pack_into("<I", m2, 0x20c, 0x00800005)
    struct.pack_into("<I", m2, 0x204, (target & 0xFF) | (value << 8))
    m2.flush()
    time.sleep(0.02)
    struct.unpack_from("<I", m2, 0x860)
    struct.unpack_from("<I", m2, 0x854)
    struct.unpack_from("<I", m2, 0x840)
    struct.pack_into("<I", m2, 0x20c, 0x00800004)
    struct.pack_into("<I", m2, 0x210, 0)
    struct.unpack_from("<I", m2, 0x210)
    struct.unpack_from("<I", m2, 0x210)
    m2.flush()


def main():
    print("bar2-pre-crst-route starting", flush=True)
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
        m2 = mmap.mmap(fd2, 0xC20, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        if not alive(m0, "start"):
            return 2
        struct.pack_into("<I", m2, 0x1c, 0x00000680)
        struct.pack_into("<I", m2, 0x1c, 0x00880680)
        m2.flush()
        if not alive(m0, "0x1c pulse"):
            return 3
        for a, v in zip(INIT_ADDR, INIT_DATA):
            struct.pack_into("<I", m2, a, v)
        m2.flush()
        if not alive(m0, "mmio_init table"):
            return 4
        for i, (g, t, v) in enumerate(SPK):
            cmd(m2, g, t, v)
            if not alive(m0, f"speaker cmd {i}"):
                return 5
        struct.pack_into("<H", m2, 0x320, 0x0100)
        struct.pack_into("<H", m2, 0x320, 0x0101)
        m2.flush()
        if not alive(m0, "gpio 0/1 on"):
            return 6
        print("pre-CRST BAR2 speaker route done", flush=True)
        m0.close()
        m2.close()
    finally:
        os.close(fd0)
        os.close(fd2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
