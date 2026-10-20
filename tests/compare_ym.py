"""Compare YM2610 event streams (tests/ym_log.lua) of the original and the conversion.

Music is clocked by the YM timers in real time (by design), so events are compared as
ordered sequences per channel class, not by frame:
  FM key on/off (A:0x28), ADPCM-A key (B:0x00), ADPCM-B control/start/end (A:0x10-0x15),
  SSG/FM/ADPCM parameter writes are summarised by register histogram."""
import sys
from collections import Counter

EVENT_REGS = {(0, 0x28): "fm_key", (1, 0x00): "adpcma_key", (0, 0x10): "adpcmb_ctl",
              (0, 0x12): "adpcmb_start_lo", (0, 0x13): "adpcmb_start_hi",
              (0, 0x14): "adpcmb_end_lo", (0, 0x15): "adpcmb_end_hi"}


def load(path, start_frame):
    ev = {k: [] for k in EVENT_REGS.values()}
    hist = Counter()
    for line in open(path):
        f, side, reg, val = line.split()
        f, side, reg, val = int(f), int(side), int(reg, 16), int(val, 16)
        if f < start_frame:
            continue
        hist[(side, reg)] += 1
        name = EVENT_REGS.get((side, reg))
        if name:
            ev[name].append(val)
    return ev, hist


def main():
    a, ha = load(sys.argv[1], 1)
    b, hb = load(sys.argv[2], 1)
    for name in EVENT_REGS.values():
        sa, sb = a[name], b[name]
        if name == "adpcmb_start_hi" or name == "adpcmb_end_hi":
            sb = [(v - 0x10) & 0xff for v in sb]     # V ROM offset of the shared ADPCM-B data
        n = min(len(sa), len(sb))
        first = next((i for i in range(n) if sa[i] != sb[i]), None)
        print("%-16s orig %5d  neo %5d  common prefix %s" % (name, len(sa), len(sb),
              "all %d" % n if first is None else "%d (orig %02x / neo %02x)" % (first, sa[first], sb[first])))


main()
