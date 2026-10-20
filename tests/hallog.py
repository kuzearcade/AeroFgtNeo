"""Read a HARNESS_HALLOG dump: hallog.load(path) -> {game frame: get(name, size)}.
usage: hallog.py hal.bin first last NAME[:size] ...   (size in bytes, default 2)"""
import os, re, struct, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
REC = 4 + 0x800


def hal_vars():
    src = open(os.path.join(ROOT, "tools", "aerofgt2neo.py")).read()
    return {m.group(1): int(m.group(2), 16) for m in re.finditer(r'\("(HAL_\w+)", 0x(d00[4-9a-b][0-9a-f]{2})\)', src)}


def load(path):
    v = hal_vars()
    out = {}
    with open(path, "rb") as f:
        while True:
            b = f.read(REC)
            if len(b) < REC:
                break
            gf = struct.unpack_from("<I", b)[0]
            def get(name, size=2, b=b):
                o = 4 + v[name] - 0xd00400
                return int.from_bytes(b[o:o + size], "big", signed=False)
            out[gf] = get
    return out


if __name__ == "__main__":
    log = load(sys.argv[1])
    names = sys.argv[4:]
    for gf in range(int(sys.argv[2]), int(sys.argv[3])):
        if gf in log:
            print(gf, " ".join("%s=%d" % (n, log[gf](n.split(":")[0], int((n + ":2").split(":")[1])))
                               for n in names))
