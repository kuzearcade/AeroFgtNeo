"""Simulate a retained sprite-column allocator over captured sprite lists.

retainsim.py pre.bin [policy] : policy pack | spread (how new sprites are placed in a gap)

Each frame's drawn entries (sprite RAM list order: index 0 at the back, the last on
top) need consecutive Neo columns (xsize + 1), column numbers increasing with the list
order (the Neo draws higher numbers on top; strict for every pair here).  A sprite whose
tiles (shape, zoom, w2, w3) match one of the previous frame, in order, keeps its columns
(only its position may change: SCB3/SCB4 at the flip).  The others are converted into
columns no sprite of the previous frame uses (those are on screen until the flip).
When a new sprite does not fit between its kept neighbours, neighbours are given up
(relocated: converted again) until it fits; failing that, the frame is rebuilt from
scratch in the free columns; what still does not fit is dropped.
"""
import collections
import struct
import sys

import numpy as np

PRE = 4 + 0x800 + 0x20 + 0x4000 + 0x2000 + 0x8000
SPR_OFF = 4 + 0x800 + 0x20 + 0x4000
LO, HI = 43, 380                       # the column ring
LOOK = 24                              # matching look-ahead in the previous list


def frames(path):
    with open(path, "rb") as f:
        while True:
            b = f.read(PRE)
            if len(b) < PRE:
                return
            ram = np.frombuffer(b[SPR_OFF:SPR_OFF + 0x2000], ">u2")
            ents = []
            for i in range(0x200):
                v = int(ram[i])
                if (v >> 14) & 1:
                    break
                if v & 0x8000:
                    continue
                a = 4 * (v & 0x3ff)
                w0, w1, w2, w3 = (int(x) for x in ram[a:a + 4])
                oy, ox = w0 & 0x1ff, w1 & 0x1ff
                ys, xs = (w0 >> 9) & 7, (w1 >> 9) & 7
                if not (oy < 224 or oy + 16 * (ys + 1) > 512):
                    continue
                if not (ox < 320 or ox + 16 * (xs + 1) > 512):
                    continue
                ents.append(((w0 & 0xfe00, w1 & 0xfe00, w2, w3), xs + 1, (ox, oy)))
            if i == 0x1ff and not (int(ram[0x1ff]) >> 14) & 1:
                ents = []               # (no end word: sprite RAM not set up yet, boot)
            yield struct.unpack_from("<I", b)[0], ents


def match(prev, cur):
    """order-preserving greedy match: cur index -> prev index"""
    m = {}
    p = 0
    for i, (k, n, pos) in enumerate(cur):
        for q in range(p, min(len(prev), p + LOOK)):
            if prev[q][0] == k:
                m[i] = q
                p = q + 1
                break
    return m


def place_run(items, lo, hi, busy, policy):
    """place items (ncols list) in order into [lo, hi], avoiding busy; -> starts or None"""
    need = sum(items)
    free = sum(1 for c in range(lo, hi + 1) if c not in busy)
    if free < need:
        return None
    slack = free - need
    gap = slack // (len(items) + 1) if policy == "spread" else 0
    starts = []
    c = lo
    for n in items:
        skip = gap
        while True:
            if c + n - 1 > hi:
                return None if policy == "pack" else place_run(items, lo, hi, busy, "pack")
            if all((c + d) not in busy for d in range(n)):
                if skip <= 0:
                    break
                skip -= 1
            c += 1
        starts.append(c)
        c += n
    return starts


def run(path, policy):
    st = collections.Counter()
    worst = collections.Counter()
    prev = []                  # [(key, ncols, pos, start)]
    nfr = 0
    per_conv = []
    for gf, cur in frames(path):
        nfr += 1
        m = match(prev, cur)
        shown = set()
        for k, n, pos, s in prev:
            shown.update(range(s, s + n))
        anchor = {i: prev[q][3] for i, q in m.items()}
        ncol = [c[1] for c in cur]
        n = len(cur)
        start = {}
        relocated = 0
        ok = True
        i = 0
        while i < n:
            if i in anchor:
                start[i] = anchor[i]
                i += 1
                continue
            j = i
            while j < n and j not in anchor:
                j += 1
            lo = start[i - 1] + ncol[i - 1] if i > 0 else LO
            hi = anchor[j] - 1 if j < n else HI
            s = place_run(ncol[i:j], lo, hi, shown, policy) if lo <= hi else None
            if s is not None:
                for t, x in zip(range(i, j), s):
                    start[t] = x
                i = j
                continue
            if j < n:                       # give up the next kept sprite
                del anchor[j]
                relocated += 1
                continue
            left = [t for t in anchor if t < i]
            if not left:
                ok = False
                break
            k = max(left)                   # or the nearest kept one before
            del anchor[k]
            relocated += 1
            for t in range(k, i):
                start.pop(t, None)
            i = k
        dropped = 0
        if not ok:
            # rebuild: everything new, in free columns, back entries dropped first
            st["rebuilds"] += 1
            relocated = len(m)
            anchor = {}
            s = None
            first = 0
            while first < n:
                s = place_run(ncol[first:], LO, HI, shown, policy)
                if s is not None:
                    break
                first += 1
            dropped = first
            start = {t: x for t, x in zip(range(first, n), s or [])}
        newc = [t for t in range(len(cur)) if t in start and t not in anchor]
        moved = sum(1 for t in anchor if cur[t][2] != prev[m[t]][2])
        same = len(anchor) - moved
        kept_prev = set(m[t] for t in anchor)
        hides = sum(1 for q in range(len(prev)) if q not in kept_prev)
        used = set(shown)
        for t, s in start.items():
            used.update(range(s, s + cur[t][1]))
        st["entries"] += len(cur)
        st["same"] += same
        st["moved"] += moved
        st["converted"] += len(newc)
        st["relocated"] += relocated
        st["dropped"] += dropped
        st["dropframes"] += 1 if dropped else 0
        worst["cols"] = max(worst["cols"], len(used))
        worst["conv"] = max(worst["conv"], len(newc))
        # flip writes: a head for every converted sprite, head + x for moved, a hide
        # for every sprite of the previous frame not kept
        fw = len(newc) + 2 * moved + hides
        worst["flipwrites"] = max(worst["flipwrites"], fw)
        st["flipwrites"] += fw
        per_conv.append((len(cur), len(newc), fw))
        prev = [(cur[t][0], cur[t][1], cur[t][2], start[t]) for t in range(len(cur)) if t in start]
    busy = [c for n, c, f in per_conv if n >= 40]
    busyf = [f for n, c, f in per_conv if n >= 40]
    e = st["entries"]
    print("%s %s: %d frames, %d drawn entries" % (path, policy, nfr, e))
    print("  kept same %.1f%%, kept moved %.1f%%, converted %.1f%% (of which relocated %d), dropped %d in %d frames, rebuilds %d"
          % (100 * st["same"] / e, 100 * st["moved"] / e, 100 * st["converted"] / e, st["relocated"],
             st["dropped"], st["dropframes"], st["rebuilds"]))
    print("  worst frame: columns in use %d (pool %d), conversions %d, flip writes %d"
          % (worst["cols"], HI - LO + 1, worst["conv"], worst["flipwrites"]))
    if busy:
        busy.sort()
        busyf.sort()
        print("  busy frames (>= 40 drawn): %d; conversions median %d p95 %d max %d; flip writes median %d p95 %d"
              % (len(busy), busy[len(busy) // 2], busy[int(len(busy) * .95)], busy[-1],
                 busyf[len(busyf) // 2], busyf[int(len(busyf) * .95)]))


def main():
    pol = sys.argv[2] if len(sys.argv) > 2 else "spread"
    if pol == "relaxed":
        run_relaxed(sys.argv[1])
    else:
        run(sys.argv[1], pol)


def rects(cur):
    """screen rectangles (x0, y0, x1, y1), zoom ignored (full size: conservative)"""
    r = np.zeros((len(cur), 4), np.int32)
    for i, (k, n, (ox, oy)) in enumerate(cur):
        rows = ((k[0] >> 9) & 7) + 1
        x = ox - 512 if ox >= 320 else ox
        y = oy - 512 if oy >= 224 else oy
        r[i] = (x, y, x + 16 * n, y + 16 * rows)
    return r


def run_relaxed(path):
    """only overlapping sprites must keep the list order in column numbers"""
    st = collections.Counter()
    worst = collections.Counter()
    prev = []
    per = []
    nfr = 0
    for gf, cur in frames(path):
        nfr += 1
        n = len(cur)
        ncol = [c[1] for c in cur]
        shown = set()
        for k, nc, pos, s in prev:
            shown.update(range(s, s + nc))
        # match by tiles anywhere, the same position first
        pool = collections.defaultdict(list)
        for q, (k, nc, pos, s) in enumerate(prev):
            pool[k].append(q)
        col = {}
        mq = {}
        for i, (k, nc, pos) in enumerate(cur):
            c = pool.get(k)
            if c:
                pick = next((q for q in c if prev[q][2] == pos), c[0])
                c.remove(pick)
                col[i] = prev[pick][3]
                mq[i] = pick
        r = rects(cur)
        if n:
            ov = ((r[:, None, 0] < r[None, :, 2]) & (r[None, :, 0] < r[:, None, 2]) &
                  (r[:, None, 1] < r[None, :, 3]) & (r[None, :, 1] < r[:, None, 3]))
        relocated = 0
        # kept sprites out of order with an overlapping one: give up the later one
        changed = True
        while changed:
            changed = False
            ks = sorted(col)
            for a in ks:
                if a not in col:
                    continue
                for b in ks:
                    if b > a and b in col and ov[a, b] and col[b] < col[a] + ncol[a]:
                        del col[b]
                        del mq[b]
                        relocated += 1
                        changed = True
        anchors = set(col)
        dropped = 0
        busy = set(shown)
        pending = []
        order = list(range(n))
        for i in order:
            if i in anchors or i in col:
                continue
            while True:
                lo = max([LO] + [col[k] + ncol[k] for k in col if k < i and ov[i, k]])
                hiv = [k for k in col if k > i and ov[i, k]]
                hi = min([HI] + [col[k] - 1 for k in hiv])
                s = None
                # nearest free run to the sprite's proportional place in the pool
                ideal = LO + (HI - LO) * i // max(1, n)
                ideal = min(max(ideal, lo), max(lo, hi - ncol[i] + 1))
                for dist in range(0, HI - LO + 1):
                    for c in ((ideal + dist, ideal - dist) if dist else (ideal,)):
                        if lo <= c and c + ncol[i] - 1 <= hi and \
                                all((c + d) not in busy for d in range(ncol[i])):
                            s = c
                            break
                    if s is not None or (ideal - dist < lo and ideal + dist > hi):
                        break
                if s is not None:
                    col[i] = s
                    busy.update(range(s, s + ncol[i]))
                    break
                kept_above = [k for k in hiv if k in anchors]
                kept_below = [k for k in col if k < i and ov[i, k] and k in anchors]
                if kept_above:
                    k = min(kept_above, key=lambda k: col[k])  # the lowest upper bound: re-place it
                elif kept_below:
                    k = max(kept_below, key=lambda k: col[k])  # the highest lower bound
                else:
                    dropped += 1
                    break
                del col[k]
                anchors.discard(k)
                del mq[k]
                relocated += 1
                if k < i:                   # (placed again after this one)
                    order.append(k)
        if dropped:
            # fall back: the whole frame fresh, in list order, into the free columns
            free = [c for c in range(LO, HI + 1) if c not in shown]
            fresh = {}
            fi = 0
            fd = 0
            for i in range(n):
                # next run of ncol[i] consecutive free columns
                while fi < len(free):
                    run = free[fi:fi + ncol[i]]
                    if len(run) == ncol[i] and run[-1] - run[0] == ncol[i] - 1:
                        break
                    fi += 1
                if fi >= len(free):
                    fd += 1
                    continue
                fresh[i] = free[fi]
                fi += ncol[i]
            if fd < dropped:
                st["fallbacks"] += 1
                relocated += len(anchors)
                col, anchors, dropped = fresh, set(), fd
                mq = {}
        used = set(shown)
        for i, s in col.items():
            used.update(range(s, s + ncol[i]))
        conv = [i for i in col if i not in anchors]
        moved = sum(1 for i in anchors if cur[i][2] != prev[mq[i]][2])
        kept_prev = set(mq[i] for i in anchors)
        hides = len(prev) - len(kept_prev)
        fw = len(conv) + 2 * moved + hides
        st["entries"] += n
        st["same"] += len(anchors) - moved
        st["moved"] += moved
        st["converted"] += len(conv)
        st["relocated"] += relocated
        st["dropped"] += dropped
        st["dropframes"] += 1 if dropped else 0
        worst["cols"] = max(worst["cols"], len(used))
        worst["conv"] = max(worst["conv"], len(conv))
        worst["fw"] = max(worst["fw"], fw)
        per.append((n, len(conv), fw))
        prev = [(cur[i][0], ncol[i], cur[i][2], col[i]) for i in range(n) if i in col]
    e = st["entries"]
    print("%s relaxed: %d frames, %d drawn entries, whole-frame fallbacks %d" % (path, nfr, e, st["fallbacks"]))
    print("  kept same %.1f%%, kept moved %.1f%%, converted %.1f%% (of which relocated %d), dropped %d in %d frames"
          % (100 * st["same"] / e, 100 * st["moved"] / e, 100 * st["converted"] / e, st["relocated"],
             st["dropped"], st["dropframes"]))
    print("  worst frame: columns in use %d (pool %d), conversions %d, flip writes %d"
          % (worst["cols"], HI - LO + 1, worst["conv"], worst["fw"]))
    busy = sorted(c for n_, c, f in per if n_ >= 40)
    busyf = sorted(f for n_, c, f in per if n_ >= 40)
    if busy:
        print("  busy frames (>= 40 drawn): %d; conversions median %d p95 %d max %d; flip writes median %d p95 %d"
              % (len(busy), busy[len(busy) // 2], busy[int(len(busy) * .95)], busy[-1],
                 busyf[len(busyf) // 2], busyf[int(len(busyf) * .95)]))


if __name__ == "__main__":
    main()
