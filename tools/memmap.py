"""Original aerofgt address space -> Neo Geo MVS address space.

Every RAM region of the original board is mapped *linearly* so pointer arithmetic,
table walks and the boot RAM test behave exactly as on the original:

  original                      size    Neo Geo
  0xfef000-0xffefff work RAM    64KB    0x100000-0x10ffff work RAM (BIOS area unused after takeover)
  0x1a0000-0x1a07ff palette      2KB    0xd01000-0xd017ff backup RAM
  0x1b0000-0x1b07ff raster RAM   2KB    0xd01800-0xd01fff backup RAM
  0x1b2000-0x1b5fff tile VRAM   16KB    0xd02000-0xd05fff backup RAM
  0x1c0000-0x1c7fff spr lookup  32KB    0xd06000-0xd0dfff backup RAM
  0x1d0000-0x1d1fff sprite RAM   8KB    0xd0e000-0xd0ffff backup RAM
  0x1b0800-0x1b0801 watchdog state word   0xd00800-0xd00801 backup RAM (BIOS-unused area)
  0x1b0ff0-0x1b1000 boot stack (16 bytes)  0xd00ff0-0xd01000 backup RAM (BIOS-unused area)
  0xffff00-0xffffff I/O          256B   0xd00e00-0xd00eff HAL I/O mirror block (+ sink)
                                         except 0xffffc1 sound latch -> 0x320000 (REG_SOUND)

The BIOS only touches 0xd00000-0xd00411 of backup RAM in steady state (measured), so
0xd00800-0xd0ffff is free for the conversion while the game owns the machine.
"""

LINEAR = [
    # (orig_lo, orig_hi_inclusive, neo_lo, name)
    (0xfef000, 0xffefff, 0x100000, "wram"),
    # one-past-the-end of work RAM is used as an initial stack pointer (lea $fff000,sp);
    # 0x110000 is the first Neo work RAM mirror, so pre-decrement lands on 0x10fffe
    (0xfff000, 0xfff000, 0x110000, "wram_end"),
    (0x1a0000, 0x1a07ff, 0xd01000, "palette"),
    (0x1b0000, 0x1b07ff, 0xd01800, "raster"),
    (0x1b0800, 0x1b0801, 0xd00800, "watchdogword"),
    # MAME maps only 16 bytes of boot stack; A7 starts one past it (0x1b1000)
    (0x1b0ff0, 0x1b1000, 0xd00ff0, "bootstack"),
    (0x1b2000, 0x1b5fff, 0xd02000, "vram"),
    (0x1c0000, 0x1c7fff, 0xd06000, "sprlut"),
    (0x1d0000, 0x1d1fff, 0xd0e000, "sprram"),
    # 0xffff00-0xffff7f is unmapped on the original board (init code writes CRTC-like
    # values there that go nowhere); give it a harmless sink next to the I/O mirror
    (0xffff00, 0xffffff, 0xd00e00, "io"),
]

SOUND_LATCH_ORIG = 0xffffc1
SOUND_LATCH_NEO = 0x320000

# HAL view of the I/O mirror block (byte addresses on the Neo side)
IO_MIRROR = 0xd00e80

ORIG_ROM_END = 0x080000


def map_addr(addr):
    """Map a 24-bit original address to its Neo address, or None if it is not RAM/IO."""
    a = addr & 0xffffff
    if a == SOUND_LATCH_ORIG:
        return SOUND_LATCH_NEO
    for lo, hi, neo, _name in LINEAR:
        if lo <= a <= hi:
            return neo + (a - lo)
    return None


def region_name(addr):
    a = addr & 0xffffff
    if a < ORIG_ROM_END:
        return "rom"
    for lo, hi, _neo, name in LINEAR:
        if lo <= a <= hi:
            return name
    return None


def is_pointer_value(v32):
    """A 32-bit constant that is plausibly an address into mapped original RAM/IO.

    Real pointers in this program have a zero top byte (they come from movea.l/lea
    with 24-bit addresses); negative numbers such as -2 (0xfffffffe) are not pointers.
    """
    if v32 >> 24:
        return False
    return map_addr(v32) is not None
