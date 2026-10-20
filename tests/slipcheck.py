"""Check the HAL's own slip log against the pixel comparison: slipcheck.py dir [offset]

dir holds a harness run of the real-cart build with HARNESS_SLIPLOG=slip.bin,
HARNESS_HALLOG=hal.bin and HARNESS_NEOPAL=npal.bin, and full_report.txt: the
differing frames from compare_full.py (FULL_ALL=1) or work/full_par.py, whose last
line is the list of (game frame, differing pixels).

1. The log itself: its records (hal/video.s G_SLIPLOG) expanded to slots must give
   each slot exactly the slip bits the harness saw in HAL_SLIP at that frame, and
   its counters must match.
2. Every frame whose picture differs from the original must be logged: frame k is
   shown in slot k + offset, so a record covering that slot or a neighbour (the
   commit straddles the real vblank) counts.
3. How close it gets: exact frames, logged frames, by slip kind."""
import ast
import collections
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hallog   # noqa: E402

BITS = ((0, "palette"), (1, "tilemap"), (2, "sprites"), (3, "tilemap (range)"), (4, "boot"))
NPAL_REC = 24 + 0x2000


def load_log(path):
    """-> (records {number: (first slot, frames, bits)}, last header)"""
    d = open(path, "rb").read()
    recs, hdr, p = {}, None, 0
    while p < len(d):
        _gf, nrec, n = struct.unpack_from("<IIH", d, p)
        hdr = struct.unpack_from(">IIIIIIH", d, p + 10)
        p += 10 + 32
        if nrec < len(recs):        # cleared and started again
            recs = {}
        for _ in range(n):
            no = struct.unpack_from("<I", d, p)[0]
            first, frames, bits = struct.unpack_from(">IHH", d, p + 4)
            recs[no] = (first, frames, bits)
            p += 12
    return recs, hdr


def main():
    D = sys.argv[1]
    off = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    P = lambda n: os.path.join(D, n)
    recs, hdr = load_log(P("slip.bin"))
    nrec, nfr, npal, nbg, nspr, nretro, _head = hdr
    L = hallog.load(P("hal.bin"))
    slot = {k: L[k]("HAL_FRAMES", 4) for k in L}
    d = open(P("npal.bin"), "rb").read()
    seen = {}
    for i in range(len(d) // NPAL_REC):
        gf = struct.unpack_from("<I", d, i * NPAL_REC)[0]
        seen[gf] = struct.unpack_from("<H", d, i * NPAL_REC + 12)[0]

    # 1. the log against the harness's view
    ok = True
    if len(recs) != nrec or sorted(recs) != list(range(nrec)):
        print("log: %d records written, %d streamed" % (nrec, len(recs)))
        ok = False
    logged = collections.defaultdict(int)      # slot -> bits
    for first, frames, bits in recs.values():
        for s in range(first, first + frames):
            logged[s] |= bits
    last = max(slot.values())
    bad = [(k, seen[k], logged.get(slot[k], 0) & ~8) for k in sorted(seen)
           if k in slot and slot[k] < last and seen[k] != logged.get(slot[k], 0) & ~8]
    cnt = collections.Counter()
    for s, b in logged.items():
        if b & ~8:
            cnt["any"] += 1
        for i, _ in BITS:
            if b >> i & 1:
                cnt[i] += 1
    expect = {"frames": (nfr, cnt["any"]),         # (the last frame: logged at the next commit) "palette": (npal, cnt[0]), "tilemap": (nbg, cnt[1]),
              "sprites": (nspr, cnt[2])}
    print("log: %d records, %d frames with a slip; per slot %s the harness's HAL_SLIP"
          % (nrec, nfr, "matches" if not bad else "DIFFERS from"))
    for k, h, g in bad[:10]:
        print("  game frame %d slot %d: harness %#x, log %#x" % (k, slot[k], h, g))
    for name, (a, b) in expect.items():
        if a != b:
            print("  counter %s %d, records give %d" % (name, a, b))
            ok = False
    ok = ok and not bad
    ranges = sorted(r for r in recs.values() if r[2] & 8)
    print("  stale tilemap ranges: %d, %d frames (counter %d)" % (len(ranges), sum(r[1] for r in ranges), nretro))

    # 2. differing frames against the log
    rep = open(P("full_report.txt")).read().strip().split("\n")
    diff = ast.literal_eval(rep[-1])
    gf_list = sorted(slot)
    m = re.search(r"differ.*? of (\d+) frames|(\d+) of (\d+) frames differ", rep[0])
    compared = int(m.group(3)) if m else len([k for k in gf_list if k + off in slot])
    unl, by = [], collections.Counter()
    for k, px in diff:
        b = 0
        for o in (off - 1, off, off + 1):
            if k + o in slot:
                b |= logged.get(slot[k + o], 0)
        if not b:
            unl.append((k, px))
        for i, name in BITS:
            if b >> i & 1:
                by[name] += 1
    dset = {k for k, _ in diff}
    quiet = sum(1 for k in gf_list if k + off in slot and k not in dset and logged.get(slot[k + off], 0))
    print("pictures: %d frames compared, %d exact (%.1f%%), %d differ (%d pixels in all)"
          % (compared, compared - len(diff), 100.0 * (compared - len(diff)) / max(compared, 1), len(diff),
             sum(px for _, px in diff)))
    print("  differing frames logged %d, unlogged %d; by slip kind %s"
          % (len(diff) - len(unl), len(unl), ", ".join("%s %d" % (n, by[n]) for _, n in BITS if by[n])))
    print("  logged but exact: %d frames" % quiet)
    if unl:
        print("  unlogged:", unl[:30])
    print("RESULT:", "ok" if ok and not unl else "FAIL")
    return 0 if ok and not unl else 1


if __name__ == "__main__":
    sys.exit(main())
