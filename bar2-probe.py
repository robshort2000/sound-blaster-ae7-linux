#!/usr/bin/env python3
"""Read AE-7 BAR2 under pci-stub. Optional single write if AE7_BAR2_WRITE=1.

Run as root on a cold boot while 0000:06:00.0 is pci-stub in D0.
Do not run if PCI config is 0xffffffff. One fatal write needs a PSU cycle.
"""
import os, sys, mmap, struct

DEV = "/sys/bus/pci/devices/0000:06:00.0"
OFFSETS = (0x1c, 0x100, 0x204, 0x20c, 0x210, 0x304, 0x320, 0x800, 0x804, 0x840, 0x854, 0x860, 0x86c)

def pci_config():
    with open(f"{DEV}/config", "rb") as f:
        return f.read(16)

def pci_enable():
    with open(f"{DEV}/config", "r+b") as f:
        f.seek(4)
        f.write(struct.pack("<H", 0x0006))
        f.flush()
        os.fsync(f.fileno())

def dump_bar2(m, tag):
    print(f"--- BAR2 {tag} ---")
    for off in OFFSETS:
        val = struct.unpack_from("<I", m, off)[0]
        print(f"  [{off:#06x}] = {val:#010x}")

def main():
    cfg = pci_config()
    print("config", cfg.hex())
    if cfg[:4] == b"\xff\xff\xff\xff":
        print("PCI dead; refuse. PSU cycle required.")
        return 1
    pci_enable()
    cfg = pci_config()
    print("config after enable", cfg.hex())
    print("power", open(f"{DEV}/power_state").read().strip())

    fd = os.open(f"{DEV}/resource2", os.O_RDWR)
    try:
        m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        dump_bar2(m, "read")
        cfg = pci_config()
        print("config after reads", cfg.hex(),
              "DEAD" if cfg[:4] == b"\xff\xff\xff\xff" else "alive")
        if os.environ.get("AE7_BAR2_WRITE") == "1":
            off = int(os.environ.get("AE7_BAR2_OFF", "0x1c"), 0)
            val = int(os.environ.get("AE7_BAR2_VAL", "0x00000680"), 0)
            print(f"WRITE {val:#010x} -> BAR2+{off:#x}")
            struct.pack_into("<I", m, off, val)
            m.flush()
            dump_bar2(m, "after write")
            cfg = pci_config()
            print("config after write", cfg.hex(),
                  "DEAD" if cfg[:4] == b"\xff\xff\xff\xff" else "alive")
        m.close()
    finally:
        os.close(fd)
    return 0

if __name__ == "__main__":
    sys.exit(main())
