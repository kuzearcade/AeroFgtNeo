"""Load the MAME 'aerofgt' set into flat, CPU-order region images.

Every file is verified against the CRC32/SHA1 listed in MAME's aerofgt.cpp, so the
converter only ever runs on the exact dump it was written for.
"""

import hashlib
import zipfile
import zlib


# (name, crc32, sha1, region, offset, size, word_swap)
AEROFGT_FILES = [
    ("1.u4",        0x6fdff0a2, "7cc9529b426091027aa3e23586cb7d162376c0ff", "maincpu", 0x000000, 0x80000, True),
    ("2.153",       0xa1ef64ec, "fa3e434738bf4e742ad68882c1e914100ce0f761", "audiocpu", 0x00000, 0x20000, False),
    ("538a54.124",  0x4d2c4df2, "f51c2b3135f0a921ac1a79e63d6878c03cb6254b", "tiles", 0x000000, 0x80000, True),
    ("1538a54.124", 0x286d109e, "3a5f3d2d89cf58f6ef15e4bd3f570b84e8e695b2", "tiles", 0x080000, 0x80000, True),
    ("538a53.u9",   0x630d8e0b, "5a0c252ccd53c5199a695909d25ecb4e53dc15b9", "sprites", 0x000000, 0x100000, True),
    ("534g8f.u18",  0x76ce0926, "5ef4cec215d4dd600d8fcd1bd9a4c09081d59e33", "sprites", 0x200000, 0x080000, True),
    ("it-19-01",    0x6d42723d, "57c59234e9925430a4c687733682efed06d7eed1", "adpcmb", 0x00000, 0x40000, False),
    ("it-19-06",    0xcdbbdb1d, "067c816545f246ff1fd4c821d70df1e7eb47938c", "adpcma", 0x000000, 0x100000, False),
]

REGION_SIZES = {
    "maincpu": 0x80000,
    "audiocpu": 0x20000,
    "tiles": 0x100000,
    "sprites": 0x400000,
    "adpcmb": 0x40000,
    "adpcma": 0x100000,
}


class RomError(Exception):
    pass


def _swap16(data):
    out = bytearray(len(data))
    out[0::2] = data[1::2]
    out[1::2] = data[0::2]
    return out


def load_aerofgt(zip_path):
    """Return dict region -> bytearray (big-endian CPU order for 16-bit regions)."""
    regions = {name: bytearray(size) for name, size in REGION_SIZES.items()}
    with zipfile.ZipFile(zip_path) as z:
        names = {i.filename.lower(): i.filename for i in z.infolist()}
        for name, crc, sha1, region, offset, size, swap in AEROFGT_FILES:
            data = None
            if name.lower() in names:
                data = z.read(names[name.lower()])
            else:
                # tolerate renamed files: match by CRC
                for info in z.infolist():
                    if info.CRC == crc:
                        data = z.read(info.filename)
                        break
            if data is None:
                raise RomError("missing %s (crc %08x) in %s" % (name, crc, zip_path))
            if len(data) != size or zlib.crc32(data) != crc or hashlib.sha1(data).hexdigest() != sha1:
                raise RomError("%s does not match the expected dump" % name)
            if swap:
                data = _swap16(data)
            regions[region][offset:offset + size] = data
    return regions


def load_security_code(zip_path, length=0x200):
    """Fetch the Neo Geo BIOS cartridge security block from a user-supplied MVS set.

    The block is not shipped with this project; it is copied at conversion time from a
    Neo Geo cartridge set the user owns (default: sonicwi3, the CHA256/PROGBK1 reference).
    """
    with zipfile.ZipFile(zip_path) as z:
        p1 = None
        for info in z.infolist():
            if info.filename.lower().endswith("-p1.p1") or info.filename.lower().endswith(".p1"):
                p1 = z.read(info.filename)
                break
    if p1 is None:
        raise RomError("no P1 ROM in %s" % zip_path)
    p = _swap16(p1)
    if len(p) > 0x100000:
        # sonicwi3 style: file holds 0x100000-0x1fffff first, then 0x000000-0x0fffff
        if p[0x100100:0x100107] == b"NEO-GEO":
            p = p[0x100000:] + p[:0x100000]
    if p[0x100:0x107] != b"NEO-GEO":
        raise RomError("P ROM in %s has no NEO-GEO header" % zip_path)
    ptr = int.from_bytes(p[0x182:0x186], "big")
    block = bytes(p[ptr:ptr + length])
    # the checked code ends at the second RTS (4E75) in the block
    first = block.find(b"\x4e\x75")
    second = block.find(b"\x4e\x75", first + 2)
    if first < 0 or second < 0:
        raise RomError("security block not recognised")
    return block[:second + 2]
