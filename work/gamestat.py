"""Gameplay sprite updates and pixel errors: gamestat.py hal.bin full_report.txt [lo hi]"""
import ast, sys
sys.path.insert(0, '/home/vboxuser/AeroFgtNeo/tests')
import hallog
L = hallog.load(sys.argv[1])
lo, hi = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (1200, 1500)
upd = clean = 0
for k in range(lo, hi):
    if k in L and k - 1 in L:
        if L[k]('HAL_SPR_SHOWN', 2) != L[k - 1]('HAL_SPR_SHOWN', 2):
            upd += 1
            if L[k]('HAL_SPR_MIXN', 4) == L[k - 1]('HAL_SPR_MIXN', 4):
                clean += 1
bad = ast.literal_eval(open(sys.argv[2]).read().strip().split('\n')[-1])
g = [d for k, d in bad if lo <= k < hi]
print('frames %d..%d: sprite updates %d (unmixed %d); pixel-diff frames %d, mean %.0f px'
      % (lo, hi, upd, clean, len(g), sum(g) / max(len(g), 1)))
