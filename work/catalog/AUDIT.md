# Aero Fighters on Neo Geo MVS: full-game profile and performance audit

Date: 2026-10-16.

| | |
|---|---|
| Builds measured | Original arcade `aerofgt` (MAME). Converted DIRECT build `work/out_wf` (p1 a6008b40), with the frame-wrap fix below. |
| Exact / assist builds | Not changed: p1 9f6956ff / s1 c40c610b, assist 87a9a660. |
| Playthrough | 200,000 game frames (about 56 minutes), the same bot input on both (`work/play/bot200k.txt`). It coins and starts every 600 frames, so it keeps continuing through every stage. |
| Method | Full MAME instruction trace (every instruction, with cycle counts) in 20 chunks of 10,000 frames, started from save states. |

| Trace | Instructions | Cycles |
|---|---|---|
| Original | 2.78 G | 32.6 G (10 MHz) |
| Converted | 3.87 G | 40.6 G (12 MHz) |

---

## 1. Bottom line

**The original arcade game is itself CPU-bound.**
- It is busy 86-94% on average per stage.
- It hits 99.4% in dense scenes (95th percentile).
- About 34% of its busy time goes to its sprite-list builder.

**The converted game spends 203k cycles per frame, which is the whole Neo Geo frame (12 MHz / 59.19 Hz = 202.7k).** Only about a third of that is the game:

| Share | Cycles/frame | What |
|---|---|---|
| Game code (original, relocated) | 48.7k (24%) | |
| gx.s (rewritten object/collision loops) | 16.9k (8%) | game work |
| **Game side total** | **65.6k (32%)** | |
| fx.s: walk the objects, emit sprite pieces | 56.4k (28%) | |
| spr.s + sprr.s: convert lists to Neo sprites, flip, reclaim | 32.0k (16%) | |
| bg.s: tilemap conversion **+ scrub filler 12.3k** | 19.1k (9%) | |
| dl.s: in-place (delta) updates | 13.7k (7%) | |
| video.s (palette), idle.s, sched.s | 14.0k (7%) | |
| tm.s / tx.s / hal.s | 2.3k (1%) | |
| **HAL total** | **137.5k (68%)** | |

**Result on the whole playthrough (fixed build):**
- **7.59% of frames are late** (15,188 of 199,991).
- **3.34% of frames drop sprites** (23,800 sprites dropped in all).
- 75 overruns.

The earlier dense-scene work measured where the time goes in a storm frame: game ~66-72k plus HAL ~130-136k, which is more than one frame.

**To reach "no late frames, no drops", the peak frame must fit in about 190k (202.7k minus a ~10k scheduling margin).**
- Peak frames are 200-210k today, so about **20-30k cycles must come out of peak frames**.
- Nearly all of that has to come from the sprite path: fx + spr + dl = 102k.
- The game side is already close to the floor: about 66k, against roughly 101k for the same work in the original.

No single option below closes the gap. Sections 6-7 give a ranked combination that does on paper.

---

## 2. Critical bug found on the way (fixed in DIRECT, NOT fixed in exact)

**At game frame 32767 (about 9 min 13 s after power-on) the DIRECT build froze its sprites forever.**

**Cause:** `HAL_FRAMES` low word wraps, and frame-number comparisons were written as `sub.w a,b` then `bgt/ble/bge`.
- `sub` sets V on signed overflow, and `bgt` tests N⊕V, so the result inverts at the wrap.
- The flip then threw away every new complete set as "never shown".
- The ring kept the shown set as its oldest, so reclaim stopped and no conversion ever began again: every frame was late from then on.

**Fix in `out_wf`:** a `tst.w` after each such `sub.w`, which makes the branch test the 16-bit difference only. All DIRECT-only or under `ifeq DIRECT-1`. The sites:
- hal/spr.s: flip `.c` / `.o` / `.nl` loops, the not-older check, FX_PRDY.
- hal/sched.s `sch_ready`: FX_PRDY / FX_DRDY / `.c` / `.nw`.
- hal/dl.s `.o`.
- hal/fx.s: fx_hud_flush / fx_hud_count / fx_hud_flushall.
- hal/rs.s: flip.

**Affected:**
- **The build deployed on the MiSTer (538-p1.p1 md5 3213314c) has the bug.** The 6-minute captures never reached 9 minutes, so it was never seen.
- **The exact build very likely has it too.** It shares the spr.s flip `.c` / `.o` code. Fixing it there changes exact-build bytes (9f6956ff), so it was left for your decision.

---

## 3. Original arcade game: what it does, and where its time goes

**Catalogue:** 1260 functions, each with a description and a subsystem. Files:
- `work/catalog/orig_functions_described.tsv`
- disassembly with coverage: `orig_disasm.txt`
- profile: `orig_profile.json`

### Structure
- **Task scheduler:** cooperative tasks. Start 0xa6c, kill 0xaca, yield 0xaee. Idle loop 0xb84/0xb8c polls 0xff8055; it is 11% of all cycles.
- **Vblank:** IRQ 0x888. Sprite list copy 0xa14.
- **Object main loop 0x1996a:** handler table 0x199ba, indexed by type word +0x16 (127 types seen; `type_handlers.tsv`).
- **Sprite-list builder 0x2bee0..0x2bf9a:** scan loop 0x2bf1a-0x2bf44; emitters 0x2c0d2 / 0x2c0ec / 0x2c0b4.
- **Collision:**
  - shot scan 0x2a182 (entry 0x2a142) over 48 x-sorted slots from 0xff42c0;
  - hitbox 0x29ee6, overlap 0x2a1f6;
  - player contact 0x29fbc.
- **Scripts:** object script interpreter 0x2c954; stage script 0x17d2e; rank 0x17a02.
- **Player:** player fire 0x18718.
- **Utilities:** palette fade 0x2a92a, colour cycling 0x2a2de, score 0x2b354, RNG 0x2a602 (uses X via roxl), cull 0x2b2da, LUT bulk loader 0x2bbca.

### Profile
- 145k cycles/frame average at 10 MHz.
- Busy share: builder ~34%, collision ~18%, object dispatch ~11%, vblank/sprite copy ~5%, the rest game logic.

| Stage | Busy avg % | Busy p95 % | Top shares |
|---|---|---|---|
| runway / space finale | 93.9 | 99.5 | builder 26%, main loop 25%, player weapons 12%, collision 8% |
| final stage | 93.7 | 99.4 | builder 30%, main loop 26%, player weapons 10% |
| desert (boss) | 93.5 | 99.4 | builder 28%, main loop 26%, player weapons 13% |
| night ocean (fleet) | 90.4 | 99.4 | builder 28%, main loop 26%, player weapons 14% |
| river valley | 89.8 | 99.4 | builder 26%, main loop 26%, player weapons 15% |
| city 1 (skyscrapers) | 89.1 | 99.4 | builder 27%, main loop 26%, player weapons 15% |
| coast/mountain river | 88.7 | 99.4 | main loop 27%, builder 26%, player weapons 15% |
| desert | 87.4 | 99.4 | builder 28%, main loop 27% |
| jungle base | 87.4 | 99.4 | main loop 27%, builder 25% |
| military base B | 86.2 | 99.3 | main loop 27%, builder 23%, player weapons 19% |
| military base A | 86.1 | 99.3 | main loop 28%, builder 24% |
| city 2 (streets) | 86.1 | 99.3 | main loop 27%, builder 25% |
| city 3 (ruins) | 85.8 | 99.4 | builder 27%, main loop 27% |
| attract demo | 82.5 | 99.2 | main loop 28%, builder 23%, player weapons 21% |
| stage intro screens | 75.0 | 99.4 | |
| map / select | 74.2 | 99.4 | |

"Main loop" in the original includes its own idle wait inside the task yield. Inclusive costs are unreliable there, because tasks switch stacks.

**The original also slows down in dense scenes:** p95 is 99.4%, so it misses frames itself; earlier measurement found it lags 2.3%.

**So "100% performance" should be defined as "never later than the original" or "never late at all".** The second is a stricter target than the arcade board meets.

---

## 4. Converted game: what it does, and where its time goes

**Catalogue:** 1776 functions, covering the relocated game plus 237 HAL routines. Files:
- `neo_functions_described.tsv`
- `neo_hal_routines.tsv`
- `neo_disasm.txt`
- per-PC profile: `neo_subsys_pc.txt`

### Hottest routines (whole playthrough, cycles per frame)

| Routine | Cycles/frame | Share | Notes |
|---|---|---|---|
| fx_emt | 20.4k | 10.1% | per-piece emitter (walk) |
| fx_objg | 15.4k | 7.6% | per-object generic walk |
| spr_lo | 14.8k | 7.3% | list entry → Neo sprite columns (VRAM writes) |
| hal_bg_scrub1 | 12.3k | 6.1% | **filler**: re-verifies tilemap slots |
| fx_walk | 12.3k | 6.0% | slot scan over the object table |
| gx_cols | 8.6k | 4.3% | collision scan (rewritten) |
| hal_spr_go | 7.7k | 3.8% | conversion dispatcher |
| dl_chunk | 6.6k | 3.3% | delta-update matching |
| gx_upds | 5.5k | 2.7% | object update loop (rewritten) |
| obj_cull_outside_rect | 3.5k | 1.7% | game |
| obj_main_loop_and_yield | 3.3k | 1.6% | game |
| obj_calc_hitbox | 3.3k | 1.6% | game |
| hal_late_n | 3.1k | 1.5% | time checks |
| fx_hud_take | 2.8k | 1.4% | HUD to the fix layer |
| hal_spr_flip | 2.7k | 1.3% | |
| hal_bg_column | 2.5k | 1.2% | |
| dir_speed_velocity | 2.3k | 1.1% | game: table × speed (mulu) |
| sch_slot | 2.1k | 1.1% | |
| hitbox_overlap_clip | 2.1k | 1.0% | game |
| hal_spr_work, dl_fin | 2.1k each | 1.0% each | |

### Per stage (busy excludes the original idle loop and the bg scrub filler)

| Stage | Busy avg % | Busy p95 % | Top shares |
|---|---|---|---|
| night ocean (fleet) | 96.6 | 99.7 | fx 33%, spr 15%, dl 7%, gx 6%, collision 5% |
| jungle base | 96.5 | 99.7 | fx 33%, spr 15%, dl 7%, gx 7% |
| map / select | 95.5 | 100.0 | fx 30%, spr 13%, scoring/HUD 8% |
| stage intro screens | 95.3 | 99.5 | fx 30%, spr 13% |
| desert | 95.0 | 99.7 | fx 32%, spr 13%, dl 9% |
| city 3 (ruins) | 94.0 | 99.6 | fx 31%, spr 14%, dl 8% |
| coast/mountain river | 93.5 | 99.6 | fx 32%, spr 15% |
| city 1 (skyscrapers) | 92.9 | 99.7 | fx 33%, spr 14%, gx 8% |
| runway / space finale | 92.6 | 99.7 | fx 32%, spr 14% |
| desert (boss) | 92.5 | 99.7 | fx 34%, spr 16% |
| military base A | 91.7 | 99.6 | fx 31%, spr 13%, gx 8% |
| military base B | 91.5 | 99.6 | fx 32%, spr 14% |
| river valley | 91.1 | 99.6 | fx 32%, spr 13% |
| city 2 (streets) | 90.6 | 99.6 | fx 31%, spr 14%, gx 7% |
| attract demo | 89.4 | 99.6 | fx 25%, bg 14%, spr 9% |
| final stage | 72.0 | 99.7 | fx 33%, dl 12%, spr 10% |

### Late frames and drops per stage (HAL counters)

| Stage | Frames | Late % | Frames with drops % | Dropped sprites | Overruns |
|---|---|---|---|---|---|
| night ocean (fleet) | 14,498 | 12.42 | 2.30 | 1,483 | 7 |
| coast/mountain river | 48,164 | 11.88 | 2.96 | 3,946 | 9 |
| desert (boss) | 16,342 | 11.74 | 6.79 | 3,509 | 5 |
| map / select | 44,142 | 6.66 | 3.71 | 4,376 | 8 |
| runway / space finale | 741 | 4.99 | 0 | 0 | 0 |
| city 1 (skyscrapers) | 42,285 | 4.36 | 4.69 | 9,625 | 11 |
| military base A | 33,360 | 2.66 | 0.55 | 861 | 35 |
| **All** | **199,991** | **7.59** | **3.34** | **23,800** | **75** |

**Caveat on stage labels.** This table maps frames to stages by the lookup-RAM fingerprint of the original run.
- Stage order is random per run, so stages the original never loaded fall into neighbouring labels. "map / select" and "coast/mountain river" absorb several stages here.
- Before tuning per stage, the fingerprint table should get entries for the missing stages (see 7.4).

### Busy-time comparison, same work

| Work | Original | Converted |
|---|---|---|
| Game logic (excluding builder / sprite copy) | ~88k cycles | ~66k (gx rewrites + DIRECT builder removal) |
| Sprite path | ~49k (builder + copy) | 102k (fx + spr + dl) |

The sprite path doubles because a Neo sprite is a column of tiles in VRAM written through the LSPC port. The original writes 8 bytes per piece to sprite RAM.

---

## 5. Sprite and tile catalogue (for later optimisation)

### Sprites
**Files** (`work/catalog/sprites/`):
- `categories.tsv`: one row per object type, with category, description, tables, sprite defs, max tiles / pixels, object-frames seen, and stages.
- `objects.json`: full detail.
- `type_XXXX.png`: rendered frames per type.
- `overview_*.png`: contact sheets.

There are 127 types in 15 categories, ordered here by how often they are on screen (object-frames over the playthrough):

| Category | Types | Object-frames | Largest def (tiles) |
|---|---|---|---|
| enemy bullets | 8 | 1,250,170 | 2 |
| explosions | 6 | 1,019,507 | 25 |
| HUD/text | 5 | 806,923 | 14 |
| player shots | 5 | 748,121 | 12 |
| ground enemies | 10 | 699,289 | 25 |
| items | 2 | 663,823 | 2 |
| bosses | 52 | 569,959 | 116 |
| shadows | 3 | 395,171 | 42 |
| enemy aircraft | 17 | 354,342 | 25 |
| player | 2 | 292,590 | 48 |
| city / buildings | 3 | 185,493 | 158 |
| ground structures | 7 | 65,238 | 30 |
| naval | 3 | 45,937 | 31 |
| screens | 1 | 21,276 | 120 |
| player bomb | 3 | 8,646 | 256 |

Bosses are split per stage in `categories.tsv`:
- desert landship 0x62-0x6a;
- ocean battleship 0x76-0x7a;
- base boss 0x83-0x88;
- city fortress 0x4d-0x55;
- river mech 0x5b-0x5d;
- finale bomber 0x9a;
- final boss 0xa5-0xad.

Corrections from the code:
- 0x18 = player weapon blast pieces. The "pair bullet storm" seen earlier was the demo player's weapon.
- 0x0b = debris.
- 0x0f / 0x10 = power-up / bonus.
- 0x2e = aircraft shadow.
- 0x34 = ground turret.
- 0x33 / 0x38 = aircraft.

**For optimisation:** six categories make up ~75% of all on-screen objects:
- enemy bullets, explosions, HUD, player shots, ground enemies, items;
- all of them small (≤ 25 tiles).

These are the candidates for per-type fast paths (option A2). Bosses and city buildings are few but large (up to 158 tiles): candidates for the delta path or a static cache.

### Tiles
**Files** (`work/catalog/tiles/`):
- `tiles.tsv`: every tile used, with layer, stages and use count.
- `summary.txt`
- `atlas_<stage>_L0/L1.png`

Usage:
- Layer 0 uses 11,934 unique tiles and layer 1 uses 10,105, out of 32,768 in the ROM.
- 13,560 tiles are shared between stages.

Per stage:
- **Biggest:** coast/river (L0 2,968), desert (L0 2,192 / L1 2,424), cities (L1 2,324).
- **Smallest:** jungle/military bases (L0 1,832 / L1 188).

---

## 6. Options audit

Estimates are for **peak** (dense) frames unless marked as averages. They come from this profile and the earlier dense-window measurements (game 66-72k + HAL 130-136k).

The status column means:
- **new**: not tried;
- **tried**: tried before, with the result given;
- **no**: ruled out.

### A. Sprite walk, fx.s (56k average, ~50k in storms): the biggest lever

| # | Option | Saves (est.) | Risk | Status |
|---|---|---|---|---|
| A1 | **Fold the walk into the game's own object update** (gx_upds already visits every slot). Emit the pieces while the object is in registers; drop fx_walk's second scan of 128 slots. Needs the snapshot timing kept: the list is built for slot k and taken at k−FX_DELAY. | 8-12k (fx_walk 12k mostly slot scanning + fx_objg setup) | medium: emit order must still be sorted/grouped (fx_sort 1k already exists) | new |
| A2 | **Per-type fast paths for the top categories**, like fxb_obj for 0x18, which took storms from 52% to 33% late. Order: enemy bullets, debris 0x0b, explosions 0x09/0x20, items 0x0f/0x10, player shots, shadows 0x2e. One fixed-shape entry, with no generic piece decode. | 10-20k in storms (fx_emt 20k + fx_objg 15k are generic) | low; per type, testable alone | partly done (0x18) |
| A3 | **Build-time compiled emitters per piece table**: straight-line code from the ROM piece tables, by the generator, like gen_sprfast. Only for the ~200 hottest tables (catalogue object-frames), to keep ROM size sane. | 5-10k | medium (ROM space, generator) | related FUSED prototype archived (work/fz_proto) after not paying; that one combined pieces too, so a pure code-specialisation version is different |
| A4 | Cache the HUD take when the score, lives and bombs have not changed (fx_hud_take 2.8k). | 1-2k | low | new (HUD object skip saved only 1.6k earlier) |
| A5 | Skip off-screen objects before the piece loop (cull in the walk, using the game's own cull 0x2b2da rectangle). | 1-3k | low | new |

### B. Conversion, spr.s / sprr.s / dl.s (46k average)

| # | Option | Saves (est.) | Risk | Status |
|---|---|---|---|---|
| B1 | **Small-sprite pool for more types.** The bullet pool (single-buffered, hardware-like) cut storm drops from 1816 to 22. Extend it to enemy bullets and debris, which are 1-2 tiles and the largest category. | 5-10k in storms + most drops | medium: pool columns come out of the ring; the boss-part pool made things worse (96 columns + vblank tile writes) | partly done |
| B2 | **dl.s cost limiter:** delta matching is 13.7k. Gate it on the expected gain: in-place updates only for big, mostly-static sets (city buildings, bosses), plain conversion for small churn. | 3-6k | low/medium | new (DL_OFF baseline: more drops but different timing) |
| B3 | Leaner spr_lo inner loop: unroll per column height (heights 1, 2, 4 dominate small categories); write SCB2/3/4 via fixed address increments. | 2-4k | low | new |
| B4 | Pre-decoded list entries | — | — | tried: moves cost walk↔conversion, net ~60 cycles/sprite worse |
| B5 | Resident / Neo-native sprites (RES prototype) | — | — | **no**: per-object reuse bookkeeping (~970-1200 cycles/object) costs more than regenerating (~400) |
| B6 | Ring capacity (DL_CW dead-column reclaim) | — | — | tried: not useful; drops are timing, not capacity |

### C. Tilemap, bg.s (19k average)

| # | Option | Saves (est.) | Risk | Status |
|---|---|---|---|---|
| C1 | **Scrub only in true idle.** hal_bg_scrub1 (12.3k) is a safety net that re-verifies tilemap slots. With tm.s hooking every writer (0x2c924, 0x5e0c, 0x81c8, the clears), it should never find anything. Run it only after all of the slot's work is done, or turn it off in gameplay. Measure first: count scrub fixes over the playthrough. | 0 on frames where it is truly filler; up to ~5-10k where it runs before conversion work | low | new |
| C2 | Tilemap-1 empty-column hiding (tx.s) | done | | done |

### D. Game side (66k)

| # | Option | Saves (est.) | Risk | Status |
|---|---|---|---|---|
| D1 | **Batched shot collision:** one pass over the enemy slots per frame testing all player shots, instead of ~5 scans per shot over 88 slots (gx_cols 8.6k + shot_collide_scan 1.8k + hitbox/overlap 5.4k). Build the candidate pairs, then apply hits in the original's order so the outcomes are identical. The X-flag and RNG ordering must be kept. | 6-12k in storms (boss collision scans were ~16k) | medium/high (correctness; RAM-equivalence check exists: tests/compare_state.py) | new (active lists gave no gain: 65% candidates) |
| D2 | x-sorted early exit: the slots at 0xff42c0 are x-sorted, so stop when slot x > shot x + max width. | 2-5k | medium | new |
| D3 | dir_speed_velocity / obj_move_dir_speed (3.6k): speeds come from a small set, so use premultiplied velocity tables instead of mulu (~70 cycles each). | 1-2k | low (same results bit for bit) | new |
| D4 | Hitbox recompute (obj_calc_hitbox 3.3k): compute once per object per frame, cached by frame number (wrap-safe!). | 1-2k | low | new |
| D5 | Fold obj_cull_outside_rect (3.5k) into gx_upds. | 1-2k | low | new |

### E. Scheduling and policy (turns spare time and margin into no late frames)

| # | Option | Effect | Status |
|---|---|---|---|
| E1 | Whole-frame holds (game waits) | late → slowdown instead | user chose no-holds (2026-10-15) |
| E2 | **Graceful load shedding by category:** when the slot's predictor says the list will not finish, shed the lowest classes first instead of going late (shadows 0x2e every other frame, debris 0x0b at half rate, then explosion sub-pieces). That is the classic Neo Geo flicker, and the category catalogue gives the priority classes. | removes most remaining late frames at the cost of flicker in the worst ~3% | new |
| E3 | Carry the conversion across frames for static sets (city buildings, boss hulls) so their work never lands in a peak frame. | smooths peaks | partly (carried conversion first) |
| E4 | **Find the exact gap:** run MAME with the 68000 overclocked (Lua clock change on `:maincpu`) to 105/110/115/120%, and measure late and drops on the dense windows. The factor where both reach zero is the real number of cycles still needed per peak frame. | measurement | new; do this first |

### F. Platform

| # | Option | Note |
|---|---|---|
| F1 | MiSTer core CPU turbo | Not MVS hardware (MVS-only decision). Useful only as the E4 measurement on hardware. |
| F2 | Z80 offload | No: it can't reach 68k RAM or VRAM, and it runs the sound driver. |
| F3 | Bigger P ROM banks for generated code (A3) | Fine under PROGBK1. |

---

## 7. Recommended plan

1. **Ship the wrap fix.**
   - Deploy `out_wf` to the MiSTer: the current deploy freezes after about 9 minutes.
   - Decide on the exact build (byte change).
2. **E4 overclock sweep.** Puts a number on the real peak gap before any more code is written.
3. **C1 scrub audit.** Cheap; tells whether 12k of "busy" is real.
4. **A2 fast paths:** enemy bullets, debris, explosions, items, shadows, one type at a time. Each has its own content window from the catalogue's stage column.
5. **A1 walk folded into gx_upds.**
6. **D1/D2 collision batching**, checked with the RAM-equivalence harness.
7. **B1 pool extension** for 1-2 tile types if drops remain; **B2 dl gating**.
8. **E2 load shedding** as the final guarantee for whatever still does not fit.

Steps 3-7 add up to an estimated **35-60k on peak frames** against the 20-30k needed (estimates; E4 confirms the target).

**Measuring harness for each step:**
- `work/play/runchunk.sh neo <from> <to>` traces any 10k-frame window from the save states in `work/play/st_wf`.
- `prof_stage.py` gives per-stage shares.
- The per-stage counter run gives late and drops.

**Still to do in measurement:**
- Extend the stage fingerprint table: the frames with no matching fingerprint sit under neighbouring labels.
- Make catalog.py compute exclusive cycles straight from the per-PC counts. Its call-tree exclusive numbers under-count HAL code that runs inside interrupts (`neo_subsys_pc.txt` has the correct values).

---

## 8. File index

All under `~/AeroFgtNeo/work/`.

**Catalogue (`catalog/`)**
- `AUDIT.md`: this file.
- Original game: `orig_disasm.txt`, `orig_functions_described.tsv`, `orig_profile.json`, `orig_stages.tsv`.
- Converted game: `neo_disasm.txt`, `neo_functions_described.tsv`, `neo_hal_routines.tsv`, `neo_subsys_pc.txt`, `neo_stages.tsv`, `neo_stage_stats.tsv`.
- Reference: `type_handlers.tsv`, `known_addresses.txt`, `context.md`, `stages.png`.
- `sprites/` and `tiles/`: section 5.

**Traces and states (`play/`)**
- Raw traces: `tr_orig/c*`, `tr_neo/c*`; each chunk has pc / edges / incl / timeline / summary.
- Save states: `st_orig`, `st_wf`.
- Census: `cen/` (objects, defs, scenes, tiles, LUT and palette dumps).
- Tools: `catalog.py`, `prof_stage.py`, `neo_desc.py`, `categories.py`, `tiles_cat.py`, `render_objs.py`, `agg/agg.c`, `runchunk.sh`.

---

## 9. Results of plan steps 1-7 (2026-10-16)

### Measurement method
Single playthroughs are chaotic between builds: the game's RNG depends on timing, so any timing change sends the game down a different route after a few thousand frames. Builds are therefore compared on **nine whole bot playthroughs** (movie seeds 7-15, 1.8M game frames in all).
- Script: `work/play/bench9.sh <romdir> <name>`.
- Run-to-run spread: about ±1% late per movie.
- Standard error of the 9-movie mean: about ±0.25%.

### Step 1: wrap fix shipped
- **Deployed:** `work/out_wf` p1 (md5 6a385206) to the MiSTer as Conversions/aerofgtn/538-p1.p1. The previous file is kept as `538-p1.p1.n0_3213314c`; s1/c/m/v are unchanged (identical md5).
- **Not boot-tested on hardware:** the other project's core was running and was left alone.
- **Exact build: not affected.** It ran 80,000 game frames through both counter wraps with a steady late rate and no freeze, so it was left unchanged.

### Step 2: overclock sweep
- **Tooling:**
  - `neogeo.cpp` hook `NEOGEO_CPU_SCALE=<factor>`. It does nothing unless the variable is set; it is re-applied after a state load.
  - Stats runners: `work/play/runstat.sh` (chunked, from the save states) and `runfull.sh` (whole run from power-on).
- **Result (out_wf, 200k frames):**

| CPU | Late | Frames with drops | Overruns |
|---|---|---|---|
| 1.00x | 7.22% | 3.46% | 62 |
| 1.05x | 4.80% | 2.53% | 69 |
| 1.10x | 3.60% | 2.82% | 46 |
| 1.15x | 2.49% | 2.83% | 26 |
| 1.20x | 1.91% | 2.65% | 7 |
| 1.30x | 0.84% | 2.24% | 0 |
| 1.40x | 0.35% | 2.53% | 0 |
| 1.60x | 0.10% | 2.54% | 0 |
| 2.00x | 0.07% | 3.41% | 0 |

- **Late frames are CPU-bound with a long tail:**
  - +30% CPU removes 89% of them;
  - +60% removes almost all;
  - so "no late frames" needs about 37% less work in the worst frames, not 10-15%.
- **Drops are not CPU-bound at all.** They come from ring capacity (see step 7).

### Step 3: background scrub audit
- Over the playthrough: 554k checks and **575 stale columns found**, from text the game erases in place. So the scrub cannot be removed.
- 85% of it already ran only while the game was idle.
- The post-commit part now skips when the slot interrupted a busy game (`video.s`, DIRECT only).
- **Measured effect: within noise.** 3 movies: 6.16% → 6.35% late.

### Step 4: fast path for one-piece objects
87.6% of walked objects are one-piece C-table objects.
- **The new path:** `fx_o1` in `fx.s` (switch `FX_O1`, default 1). It does the setup and the piece in one go, with no bound arithmetic, call or loop.
- **Exactness:** checked by the in-build self-check `FX_O1CHK=1` (both paths on every object). **4,492,274 objects over the 200k-frame playthrough, 0 mismatches.**
- **Result (9 movies):** **late 6.30% → 5.04%** (−20%). Drops 2.77% → 2.81% (unchanged). Overruns 609 → 714; in DIRECT an overrun only means the game loses that time.

### Step 5: the walk's slot scan
- **Folding the walk into the game's object loop is not viable.** The walk would see objects before collision and later handlers move them, and before later spawns. Hooking every activation would mean ~100 sites, mostly 4-byte instructions.
- **Done instead:** the scan is unrolled 8-way (exact by construction, ~1k cycles/frame). 9 movies: 5.20% late vs 5.04%, i.e. within noise.

### Step 6: collision
- **D2 (x-sorted early exit): not valid.** The slots are not x-sorted; only the walk's draw order is.
- **D1 (batching the scans): not exact without seeing every candidate-flag write in a frame.** The earlier active-list attempt measured no gain, and the scan is already 8-way unrolled at ~20 cycles per empty slot.
- **No change made.**

### Step 7: drops
- **Object mix in the 5,511 drop frames**, against other frames:
  - debris 0x0b: 8.4 vs 3.7;
  - small bullets 0x2d / 0xcb / 0xca: about 11 vs 6;
  - buildings 0x44: 3.2 vs 0.9;
  - cars 0x46: 2.1 vs 0.4.
- **B1 (pool extension): not useful.** Moving the small bullets to the pool would save only ~11 columns per drop frame.
- **The real cause is the ring's dead columns.** At drop time a new list needs ~93-125 columns, but the shown set spans ~245, because each in-place update (dl.s) hides the heads it doesn't keep and converts the changed ones below the set's end.
- **B2 (`DL_CW=1`, re-tested on 3 movies): no drop gain.** 3.11% frames with drops vs 3.10%.
- **Superseded (section 10):** the dead-column explanation was wrong. A drop probe found the shown set's dead columns ≈ 0; the cause is split fragmentation.

### Current DIRECT build
- **Build:** `work/out_u8`: wrap fix + scrub gating + `fx_o1` + 8-way scan.
- **Regression:**
  - vis-violations 0/0, resets 0, HUD dropouts 0;
  - GAME OVER text appears in one frame (reference `work/go_orig` regenerated);
  - m7 late 494, overruns 0; attract late 381, overruns 7.
- **Exact / assist builds:** byte-identical (9f6956ff / c40c610b / 87a9a660).

## 10. Drops: split fragmentation and SPR_ANCH (2026-10-16)

### Finding
- **Probe:** `work/play/dropring.lua` (`rundr.sh`) logs the ring at the first drop in each game frame; classified by a script (split / nosplit / wsplit × fits / over).
- **Dead columns are not the cause:** DL_DEAD of the shown set was ≈ 0.
- **Cause:** a set slightly too big splits. Its tiny lower run cuts the free ring into two ~112-column pieces, each too small for the next ~115-130-column list. On `u8`, 96.5% of drop frames were "shown set split, need fits the total free".

### Fixes (`hal/spr.s`, DIRECT only, switch `SPR_ANCH`, default 1)
- **Placement anchoring (`hal_spr_where`):** a set not begun at the top is placed low, about 1.5 × the last set's size + 16 above SPR_PB, so it doesn't sit in the middle of the free space.
- **Split lower-run anchoring (`spr_split_anch`):** the lower run of a split starts at SPR_PB + its own size (summed over up to SPLN = 64 entries, margin 4), not just below the previous set.
- **Reclaim guard:** reclaiming a set doesn't chain its old tail when that tail is the split guard SPG. This fixed 2 vis-violations in m7 at frame 3381.
- **`spr_anyw`:** the drop and BLK checks wait when the oldest set was freed mid-conversion but isn't reclaimed yet.

### Results
| Build | Drop frames (3-movie probe) | bench9 late | bench9 frames with drops | overruns |
|---|---|---|---|---|
| `u8` | 16,833 | 5.20% | 2.86% | 741 |
| `an3` (anchoring + guard, SPLN 12) | 7,936 | 4.44% | 1.36% | 718 |
| `an4` (+ spr_anyw, 1.5×prev+16, SPLN 64) | 1,451 | 4.76% | 0.21% | 714 |

- The late-frame difference between `an3` and `an4` is within bench noise (per-movie 3.2-5.7%). `an4` may convert some drops into waits.
- **Remaining `an4` drops:** nosplit / fits 1,008 (441 of them mid-conversion), split or wsplit / over 330, other ~110. Split / fits fell from 16,235 to 52.
- **Regression (`an4`):** vis-violations 0/0, resets 0, GAME OVER ok; m7 late 817 / drops 487, attract late 380 / drops 964 (single runs are route noise).

### HUD dropouts
- `hudfix.lua` / `hudrun.py`: short (≤ 30-frame) dips in fix columns 36-39 over three 200k-frame runs: `u8` 28, `an3` 23. Same frequency, so not a regression.
- Long dips are game-over / continue screens (the GAME OVER text replaces the 1P HUD), so the hudpix hits in `an4` are false positives.
- One-frame blinks (e.g. `an3` m7 3972, on a frame with a pending dl update) were already present before this work. The likely cause is the walk catching the HUD mid-rewrite; not proven.

### Current DIRECT build
- **Build:** `work/out_an4` (DIRECT p1 9bcaa2e0). Sources before this work: `work/bk7/spr.s.pre_anch`.
- **Exact / assist builds:** byte-identical (9f6956ff / c40c610b / 87a9a660).
- `out_an4` deployed to the MiSTer 2026-10-16 (p1 md5 6ca157f4) and boot-tested; previous p1 kept as 538-p1.p1.wf_6a385206. Superseded by `out_an5` (section 11).

## 11. Nosplit drops: list-sized anchor (2026-10-16)

### Finding
- About 95% of `an4`'s nosplit drops had one shape: the converting set was anchored low (start 60-150), reached SPR_PB and dropped, with 130-300 free columns above its start.
- **Cause:** the anchor was PB + 1.5 × PREV + 16, and PREV (the last completed set's size) was often tiny or zero (empty lists, small sets). The next full list of 50-130 columns then started far too low.

### Fix (`hal/spr.s`, DIRECT + SPR_ANCH)
- **`spr_begin_anch`**, called from `hal_spr_begin` after `hal_spr_where`, applies only with no set split, the start at or below the newest set's end, and the tail not below that end. It sums the list's entry widths from a5 to FX_AEND (the walk already keeps only on-screen entries) and starts at PB + sum + 4, at most at the newest set's end. Lists over ANLN = 96 entries keep the old estimate.
- **Budget:** the conversion start check reserves ANCH_LINES = 6 extra lines (about 70 cycles per entry).
- **Backup:** the previous source is `work/bk7/spr.s.pre_banch`.

### Results
| Build | Drop frames (3-movie probe) | bench9 late | bench9 frames with drops | dropped | overruns |
|---|---|---|---|---|---|
| `an4` | 1,451 | 4.76% | 0.21% | 39,295 | 714 |
| `an5` | 573 | 4.54% | 0.10% | 9,985 | 512 |

- The nosplit / fits class fell from 1,008 to 11.
- **What remains is mostly capacity:** split or wsplit / over 427 (in dense scenes the list needs 150-185 columns, more than all the free space), split or wsplit / fits 116, nosplit 27.
- **Regression:** vis-violations 0/0, resets 0, GAME OVER as `an4`. The m7 HUD "dropout" at 8064 is the continue screen (a false positive).
- **Builds:** `work/out_an5` DIRECT p1 a3be3035 (md5). Exact 9f6956ff / c40c610b and assist 87a9a660 unchanged (`work/out_exck3`).
- **Deployed** to the MiSTer 2026-10-16 (p1 md5 a3be3035) and boot-tested; the `out_an4` p1 is kept as 538-p1.p1.an4_6ca157f4.

## 12. Remaining split drops: capacity (2026-10-16, investigation only)

### Findings (`an5`, 3-movie probe: 543 split / wsplit drop frames)
- **Dense scenes only.** The list needs ~170-186 columns while the shown set holds ~165-175, so two full sets exceed the ring's 338 columns. Tilemaps take columns 1-42, so there are no spare hardware columns.
- **Overshoot is small:** need + shown − 338 has median 5, 75th percentile 13, 90th 24, max 45. The 116 "fits" frames are within the split's own guard and tail columns.
- **Occurrence:** 7-11 short clusters per 200k-frame movie (e.g. bot200k_8 frames 11958-13603).
- **In-place updates never run here:** `dl_try` refuses any base while a set is split (`why=3`, `tst.b HAL_SPR_SPS / bpl .r3`), and these scenes are always split.
- **List dump** (`work/play/dumpl.lua` + `rundl.sh`; bot200k_8 to frame 14000, 94 drop frames):
  - **22 of 94:** the converting list is identical to the shown set's list (probably the same game state twice). Converting it is wasted work that drops sprites.
  - **The rest:** entries identical in place, median 25%; matched by tile, size and zoom in any order, median ~83% of columns (147 of 177); `dl`'s in-order 8-entry lookahead finds only ~17 columns. The game's list order shuffles between frames.
  - Keeping even the in-order matches would bring shown + new columns under 338 in 70 of 94 frames (22 of them the identical lists). This assumes the room is usable; with a split base the free room is the hole between the runs, not below the set's end.

### Options
1. **Identical-list shortcut:** when the new list equals the shown set's, don't convert it; the shown set stays. This is cheap (~3-4k cycles to compare a ~70-entry list, only under ring pressure) and covers ~23% of these drops in the sample.
2. **`dl` on a split base:** new entries go into the hole between the runs (above the lower run's kept sprites), allowed only where they cover none of them (the DL_NCOV cell test). This is a larger design change.
3. **Out-of-order keeping:** match beyond `dl`'s 8-entry in-order lookahead, with draw order checked only between overlapping sprites (retainsim's "relaxed" mode). This also helps normal frames. It is the biggest change.

### Identical-list skip: tried, reverted (2026-10-16)
- **Change (`dl.s`):** while a set is split, `dl_try` compared the new list word for word with the base's list, and on a match ran the in-place update keeping every sprite. `dl_fin` aborted if any entry would be converted below the split set. The split refusal no longer counted toward the back-off.

| Build | Change | bench9 late | frames with drops | sprites dropped |
|---|---|---|---|---|
| `an5` | (baseline) | 4.54% | 0.10% | 9,985 |
| `an6` | skip; 6 lines reserved when split, "no time" otherwise | 5.31% | 0.08% | 7,599 |
| `an7` | as `an6`, but declines instead of "no time" | 5.95% | 0.09% | 9,509 |

- Drops fell by ~24% in `an6`, as estimated from the list dump, but late frames rose in most movies in both variants: a bad trade. The likely cost is the work on every try in split scenes (no back-off: table allocation, `fx_start`, the comparison) plus the updates themselves. This was not isolated further.
- **Reverted:** `hal/dl.s` is the `an5` version again (verified: the rebuild `work/out_an5r` is byte-identical to `out_an5`, a3be3035). Variants are kept as `work/bk7/dl.s.an6` and `dl.s.an7`.

### HUD one-frame blink: cause found, fixed in `an5h` (2026-10-16)
- **Rate before the fix:** one-frame dips over three 200k-frame movies: `u8` 10, `an3` 10, `an5` 7, `an6` 14. The original shows none.
- **Cause:** when a player respawns, `player_spawn` (0x1987e) remakes the 1P HUD object (type 2, slot 0x101300 / original 0xff0300) at the end of a game frame. Its active byte goes 0x81 → 0x01 (new, handler not run), and the object's handler (0x1cb74) sets 0x81 again at the start of the next frame's object loop.
  - **Original:** the builder is its own task (0x2be50: build, then frame wait) and samples mid-frame. Under the debugger at bot200k frame 108240-108241, the 0x01 window was lines 219-239 and the builder ran at lines 115 and 134, so it always saw 0x81.
  - **Neo:** the walk samples at the game-frame boundary (line 229), inside the window, so it skips the object. Its strips are then cleared by the HUD pass and rewritten by the next walk.
  - **Measured over three bot movies:** the original had 3 such resets and 0 label dropouts; `an5` had 10 and 8.
- **Fix (`hal/fx.s`, DIRECT; `fx_hud_pend`):** a strip shown but not taken this walk is kept when a HUD/text object (type 2 or 3) among the pass-1 slots has its active byte 0x01.
  - The scan runs once per walk, only when needed (130 slots, charged FXU_HPEND 200), and not while the tilemap text owns the fix layer.
  - **Result (`an5h`):** 17 resets, 0 label dropouts at a visible HUD, one-frame dips 7 → 0.
  - **Regression:** vis-violations 0/0, resets 0, GAME OVER as before, hudpix dropouts 0/0.
  - **Backup:** `work/bk7/fx.s.pre_hpend`.
- **Left:** at a continue (HUD object 0x00 → 0x01 → 0x81, the continue text replaced by the HUD), the label can be blank for one frame. This happened in 1 of 2 continues (`an5`), 1 of 3 (`an5h`), and 0 of 1 in the original. It is rare and a separate transition.
- **Tools:**
  - `work/play/hudtrace.lua`: fix writes, HUD queue, dl state in windows;
  - `objhud.lua` + `runobj.sh`: HUD object byte + 1P label pixels around changes, orig or neo;
  - `oddbp.lua` / `origbp.lua`: debugger breakpoints via `-debug -debugger none -debuglog`.

### Cheaper identical check (`an8`): no clear gain (2026-10-16)
- **Change:** a precheck while split (list length, first and last entries, ~250 cycles); only on a match, the back-off is skipped and the full compare and all-kept update run. Otherwise exactly `an5`.
- **bench9:** late 5.07%, frames with drops 0.08% (`an5` 4.54% / 0.10%). Regression clean. Not adopted; `dl.s` is the `an5` version (variant `work/bk7/dl.s.an8`).

### Bench noise
- `an5h` differs from `an5` only by the HUD fix (a few cycles a walk, the scan every ~30 frames at most) yet benched 5.26% late vs 4.54%: per movie up to ±2.7 points.
- So one 9-movie bench resolves only differences of roughly ≥ 1 point. The late-frame increases of `an6` (+0.77) and `an8` (+0.53) are within that, and `an7` (+1.41) is borderline.
- Deciding such changes needs more movies (e.g. 18 seeds) or a paired measure that does not depend on the route (cycles per conversion).

### Current DIRECT build
- **Build:** `work/out_an5h` (p1 CRC 8ad37a37): `an5` + the HUD fix.
- **Exact / assist:** exact 9f6956ff / c40c610b, assist 87a9a660 unchanged.
- **MiSTer:** has `out_an5h` (see below).
- **Deployed** `out_an5h` to the MiSTer 2026-10-16 (p1 md5 746fec62) and boot-tested (work/mister_an5h/); the `out_an5` p1 is kept as 538-p1.p1.an5_a3be3035.

## 13. In-place updates on a split set, out-of-order matching (2026-10-16)

User request: "Allow in-place updates on a split set and match sprites out of order". Implemented in `hal/dl.s`; works correctly, but the matching does not finish in time in the scenes where it is needed. **Switched off by default** (`DL_OOO` / `DL_SPLIT` = 0). Three pre-existing bugs found along the way are fixed (on).

### The feature (`DL_OOO`, `DL_SPLIT`; DIRECT, off)
- **Out-of-order matching:** a new entry may keep any unused base entry with the same shape, zoom, attributes and tiles (hash of the base list on `w3 & 31`, chains in `DL_NEXT`). It takes the candidate with the highest column that keeps the draw order where it matters, checked per 32-pixel cell (10 × 7):
  - its column must be below every kept one before it over its cells (`DL_MINC`, columns halved into a byte: conservative);
  - it may not lie under a new one before it (`DL_NCOV`).
- **Split base:** when the split set is shown and is the ring's only set, the entries not kept are converted into the hole between its runs, below the top run (which grows down: `SPJ`, via `spr.s .hoff`; `dl_done` gives the set its end back):
  - a kept sprite of the lower run may lie under a new one before it; one of the top run may not;
  - a new sprite under a kept one of the lower run before it demotes those (and, by their cells, the ones in front of them) to converted too: `dl_odem`, from per-entry cell records (`DL_LKC`, 36 at most).
  - Only tried when a new set of the list would not fit the hole (cheap column sum); a waiting split base and a ready one are exempt from the back-off; a matching left from an earlier slot restarts as a new try.
- **Model first** (`work/play/sim/holesim.py` on `dumpl2.lua` dumps at split drops, 110 frames): with cell order checks and the demotion cascade, ~62% of the list's columns kept, the rest always fits the hole.
- **Correctness:** `kschk4.lua` (every commit's kept pairs: same tiles/size, base sprite's width intact in VRAM) and `chainchk_z.lua` (every shown sprite's columns chained) clean with the feature on (`oo3`/`oo4`: bot movies 8 and 9, 60k frames each, and movie7).

### Why it is off
| Build | Change | movie7 late frames | note |
|---|---|---|---|
| `ox` / final | fixes only | 543 | |
| `oo3` | out of order for every base + split | 1330 | full-list matching on every try |
| `oo5` | out of order only for a split base | 916 | |
| `oo7` | + only when the list would not fit the hole | 612 | bench9 5.84% late / 0.06% frames with drops (`ox` 4.71% / 0.10%) |

- The whole list matched costs ~1000 cycles an entry (view, cells, floor, coverage, candidates).
- With the gate, split-base updates were tried at the right moments but **never finished**: a dense scene's slot leaves time for ~20 of its ~65 entries (`phtap2.lua`: 39 hole tries begun, 0 matched, bot movie 8, 60k frames). Carrying the matching into the next slot (`oo11`, list protected) still did not finish, and blocked that slot's conversion. So `oo7`'s bench differences come from side effects, not from updates.
- **What it would need:** a much cheaper match (e.g. the walk producing each entry's key and cells as it builds the list), or matching only the entries that changed.
- Variants: `work/bk8/dl.s.oo3` … `dl.s.oo11`.

### Pre-existing bugs fixed (on)
1. **Hidden heads never chained again** (`hal/spr.s` reclaim `.dead`): an update hides the base's heads not kept (height 0, `dl_flip`), but they are no longer among the set's heads, so the reclaim left them at 0. A later set whose non-head column landed there lost that sprite's columns from it on.
   - `work/play/chainchk*.lua`: frames with a broken shown sprite, movie7 10000: `an5h` **1618 → 0**.
   - Fix: a set reclaimed with `DL_DEAD` chains all its columns again (both runs if split; then the new tail, `SPR_PB` and guards 0 as before); its time counted (~8 lines at most).
2. **A pending update's list overwritten** (`hal/fx.s` `fx_snap_begin`): its buffer was protected only by `FX_CBUF`, which a set completed after it takes; the walk then reused it before the update's flip, and the set was shown with another list (its next update kept heads by it: wrong tiles/sizes). The walk now also skips `DLP+D_BUF`.
3. **Entry tables shorter than their list** (`hal/dl.s` `T_N`): a list still being walked when matched or converted grows afterwards; its table covered only the entries then present, and the later ones' stale slots were kept by the next update. Each table records the entries it covers; `dl_try` clamps the base list to it.
4. **No free list buffer** (`fx_snap_begin`): with the pending buffer also excluded, all five can be in use; the fallback took buffer 0 (once in 100k frames: a pending update's list). Now the slot's list is the last one again (no walk: a late frame).

- `ox` (fixes 1-3) costs nothing measurable: movie7 late 543 (`an5h` 575), bench9 4.71% late / 0.10% frames with drops (`an5` 4.54% / 0.10%, `an5h` 5.26% / 0.08%).
- Tools: `work/play/chainchk*.lua`, `kschk4.lua`, `whytap.lua`, `gatetap.lua`, `begtap.lua`, `phtap*.lua`, `vramw.lua`, `start_chk.sh`, `benchq.sh`.

### Current DIRECT build: `work/out_fin3` (p1 CRC 122a98a1)
- `an5h` + fixes 1-4; `DL_OOO` / `DL_SPLIT` off.
- **bench9:** late 4.60%, frames with drops 0.10% (`an5` 4.54% / 0.10%).
- **Regression:** movie7 late 543, vis-violations 0/0, HUD dropouts 0/0, resets 0, GAME OVER as before.
- **Broken shown sprites** (`chainchk_z.lua`): 0 over 200k frames each of bot movies 7 (198k), 8 and 9, and movie7 (`an5h`: 1618 of movie7's 10000 frames).
- **Exact / assist:** 9f6956ff / c40c610b, 87a9a660 unchanged.
- **Deployed** to the MiSTer 2026-10-17 (p1 md5 b2eb9469) and boot-tested (work/mister_fin3/): attract, plane select, coined play with explosions, continue, title. The `out_an5h` p1 is kept as 538-p1.p1.an5h_746fec62.

## 14. Reusing columns: back-suffix sharing (2026-10-17)

User request: pursue option 1 (reuse hidden columns) and evaluate. Earlier retained/resident experiments (`hal/sprr.s`, `hal/rs.s`) showed per-entry reuse bookkeeping costs more than converting on the 68000; their note recommended keeping the ring converter and borrowing reuse only for column capacity. So this is narrow: **`SPR_SHARE`** (`hal/spr.s` hooks, `hal/dl.s` `sh_match` / `sh_flip` / `sh_drop`). **Correct; no clear net gain; off by default** (build = `out_fin3`; on: `AEROFGT_DEFS=SPR_SHARE=1` = `out_sh5`).

### Design
- In a split scene, the shown set S has its lower run at the bottom, directly below the hole. A set N begun in the hole, whose list does not fit the hole, takes over S's lower run for its back entries: matched from the list's back, in order (8 S entries looked at each), same shape, zoom, attributes and tiles. It converts only the entries before that suffix (`FX_AEND`), anchored low in the hole so no hole columns get locked inside it.
- The shared sprites are N's back entries and lie below everything N converts, in S's order (= N's): draw order holds without per-cell checks.
- At match time the shared heads become N's first slots (explicit slots in its table, `T_NXT` after them) and leave S's head list. At N's flip, after S's hide, only their SCB4 (x) is written (~30 cycles each). Then the ring changes: S keeps its top run, N runs down to S's old end (guard inside, 0), the ring is no longer split, zoomed columns move to N, and N's columns are all chained again at its reclaim.
- No new set or update begins before N's flip (`SH_ON`).

### Bugs found while building it
- N's `SS_HNEXT` was left stale, so an in-place update of N right after its flip converted over the lower run: attract vis-violations 10 → 0.
- Sharing in every split scene anchored N low and blocked the next set in light scenes: movie7 late 543 → 843. Gated on the list not fitting the hole: 341.
- Vblank work: SCB3 of the shared heads is written by N's normal show loop. Only x is written extra.

### Results (`sh5` vs `fin3`)
| | `fin3` | `sh5` |
|---|---|---|
| bench9 late | 4.60% | 5.25% (noise range ±0.7) |
| bench9 frames with drops / sprites dropped | 0.10% / 10,885 | 0.08% / 10,799 |
| 3-movie drop frames: shown set split | 332 | **152** (−54%) |
| 3-movie drop frames: converting set splits itself | 262 | 411 (+57%) |
| 3-movie drop frames total | 628 | 597 |
| movie7 late (regression) | 543 | 341 |
| vis-violations, resets, GAME OVER | clean | clean (movie7 HUD label dropout 1 frame) |
| broken sprites (`chainchk`) | 0 | 0 (bot 7 200k with 100 shares, bot 9 100k); `kschk` 0 |

- **Why little net gain:** the drops move rather than disappear. After a share, N holds a whole list in the middle and bottom of the ring. The next set starts at the top, runs into N and splits itself, and its lower run has no room below N. The capacity floor (two consecutive dense lists > 338 columns) still applies to every frame that does not share.
- **Next step, if pursued:** share at that self-split too: when a converting set reaches the tail, take over the newest set's back suffix as its lower run (the mirror case). Back entries would then pass from set to set without conversion every frame. It happens mid-conversion, and the newest set may not be shown yet, so it is more involved.
- Variants: `work/bk9/` (`*.sh1` … `*.sh5`).

## 15. MiSTer "snow": palette RAM accessed during the display (2026-10-17)

- **Symptom** (HDMI capture `work/vid/snow_att.mkv`, deployed `out_fin3`): every frame, one scanline carries a row of single dots, 22 Neo pixels (44 CPU cycles) apart, in varying colours; the row moves with the work's timing. MAME does not show it.
- **Cause:** on the hardware and the MiSTer core, a CPU access to palette RAM during the active display takes the pixel being drawn. The HAL touched palette RAM during the display in two places (found with `work/play/paltap.lua` / `palrtap.lua`, which tap palette RAM by LSPC line):
  1. **`hal_pal_stage`** (DIRECT) converted changed palettes into palettes 128+ of palette RAM (unshown, but still palette RAM): one write per colour.
  2. **`hal_pal_scrub`** read one palette per frame from palette RAM, comparing it with the original: 15 reads, a 44-cycle loop. This was the constant one.
- **Fix** (`hal/video.s`, DIRECT only):
  - **Stage:** moved to work RAM (`G_PALSTG` = original 0xffc280, 2 KB). The game never touches 0xffc280-0xffd35f: 5 runs incl. 3 whole bot playthroughs (`work/ramuse/`, `ramuse2.lua`).
  - **Scrub:** compares against the stage, which holds what the commit last wrote. Every DIRECT palette write goes through it.
  - **Palette RAM:** now accessed only in the vblank (taps: 0 accesses on visible lines after boot).
- **Result:**
  - **MiSTer capture, attract** (`snow_fix2.mkv`): frames with a dotted row (`snowdet.py`) 47.9% → 6.1%; the rest are false positives on regular background patterns (checked by eye).
  - **MiSTer capture, gameplay:** 7.5%, all of them background patterns.
  - **Regression:** clean (movie7 late 565, vis 0/0, PALMISS 0).
- **Build:** `work/out_sn2` (p1 CRC 7162fdbb). **Deployed** to the MiSTer's main set 2026-10-17 (p1 md5 481a8664; the `out_fin3` p1 is kept as 538-p1.p1.fin3_b2eb9469) and boot-tested (`work/mister_sn2/`: attract, select, play, continue, title). A 90 s recording (`work/vid/snow_sn2_main.mkv`) shows no dotted rows by eye; the detector's hits there are foliage and vent textures.
- **Exact build:** unchanged (9f6956ff). It still scrubs palette RAM during the display, so it would show the same snow on hardware.

## 16. No sound (MiSTer, and MAME too): sound driver start race (2026-10-17)

- **Symptom:** the MiSTer's HDMI audio (capture box USB audio input) is digital zero for Aero Fighters, even on a coin insert, while Ginga Ninkyouden plays at −36 dB. MAME `-wavwrite` of the same build: also −91 dB (silent). The regression runs use `-sound none`, so this went unnoticed. It applies to every build checked (exact, `an5h`, `fin3`, `sn2`).
- **Cause** (`work/play/z80pc.lua`, `sndtrace.lua`): the HAL starts the original sound driver by sending 0x55 then 0xaa to the Z80 shim (`z80/shim.s`), which echoes each one. The shim echoes 0x55 as the first instruction of its NMI handler, before it records the state and returns. The HAL sends 0xaa at once on seeing the echo, so the second NMI nests inside the first (Z80 PC 0x788a). It is then taken for a game command, the start is lost, and the Z80 idles in the shim (0x7830) for good.
- **Fix** (`hal/hal.s` `hal_sound_start`, DIRECT only, so the exact build's p1 is unchanged): after the 0x55 echo, wait ~200 µs (the handler returns in ~15 µs), then send 0xaa. If it is not echoed, repeat the handshake (4 tries).
  - Diagnostic builds record each byte's wait and reply at 0xd00f50, shown in the dump (`hal/diag.s`).
- **Result** (`work/out_sd1`, p1 CRC d751d165):
  - **MAME:** 0xaa echoed at the first try, the Z80 runs the original driver from ~frame 290; movie7 audio −25.6 dB mean.
  - **MiSTer** (diagnostic set `aerofgtnd`): −33 dB in attract and gameplay.
  - **Regression:** clean.
- **Exact build:** still silent (same race). Fixing it changes its p1 (9f6956ff), or the shim (m1) for every build: echo after recording the state, and treat an NMI inside the BIOS-phase handler as BIOS phase.
- **Not deployed** to the main set yet (main set: `out_sn2`, silent).

out_sd1 deployed to the main set 2026-10-17 (sn2 p1 kept as 538-p1.p1.sn2_481a8664); boot-test work/mister_sd1/: attract, GAME OVER, map, play; audio -33.2 dB attract / -32.9 dB play.

## 17. Attract mode: MiSTer vs original (2026-10-17)

Recordings: MiSTer HDMI capture of out_sd1 from power-on, 400 s (work/vid/att_cmp.mkv -> work/attcmp/mister.rgb, 3.7 cycles); MAME original aerofgt and out_sd1, 22000 frames each, per game frame (attcmp/orig, attcmp/neo) and per screen frame (attcmp/s_orig, attcmp/s_neo, attcmp/scr.lua). Scenes were labelled against the original's cycle (scratchpad att/: thumbs.py, align.py, label.py; lab_*.txt), then compared at full resolution (odiff.txt original vs Neo, mdiff.txt MiSTer vs MAME Neo).

- Scene order is the same in all three recordings: logo, intro, title, demo 1, staff 2, demo 2, staff 3, demo 3, staff 4, demo 4, ranking, repeat. No scene is missing or cut short. Non-gameplay scene lengths are within 0-4 frames of the original (Neo vs original: title +4, staff +1..3, ranking +2). MiSTer matches MAME Neo within about 1 frame. The black gaps before demos 2 and 3 are 11-15 frames longer on the MiSTer.
- DEFECT (every build, including exact 9f6956ff, MAME and MiSTer): the staff-credits panel (AERO FIGHTERS logo, colour 58, and the STAFF name list, colour 53) is missing on all three staff screens; the panel area shows plain black. Cause, at frame 2600: tilemap 1 fills the panel with cells 0x10f0, a solid pen-0 tile that is not a block and not k*0x800. hal_bg_odd_in sends those cells to the fix layer (fix tile 0x01c, palette 8, columns 26-39, rows 2-29). The fix layer is drawn above all sprites, so it hides the panel's sprites (Neo sprites 299-314 are in VRAM with valid tiles and palettes; per-line count at most 75). In the original those sprites have colour bit 5 set and draw over tilemap 1. The panel shows briefly during each staff screen's exit wipe, when tilemap 1 is not 8-pixel aligned and the fix layer is cleared. Possible fix (DIRECT-1 only): draw blocks of four identical solid-pen tilemap-1 cells as a solid C tile in the tilemap-1 sprite column (uniform block 9 is already solid pen 0) instead of on the fix layer.
- Not defects: the intro explosion layout differs from the original (the DIRECT build's RNG diverges); the demos run longer than the original's (demo 2 ~645 vs 505, demo 3 ~1490 vs 1107, demo 4 ~745 vs 669; the exact build matches the original); the GAME OVER blink phase differs; logo, title, ranking and staff pictures match. MiSTer-only differences are single-frame timing (an intro flash, the ranking portraits' scroll phase, the edges of the staff wipes) and capture colour.

### 17a. Staff-panel fix (2026-10-17, work/out_sp1, DIRECT-1 only)
- hal/bg.s hal_bg_odd_in `.fix`: before sending a tilemap-1 odd block to the fix layer, hal_bg_solid1 checks for four identical cells of a solid opaque tile (SOLIDPEN: a nibble per physical tile, P ROM 0xe8000, gfx.solid_pen_table) and draws the block in the tilemap-1 column as C tile SOLID_BASE (0xc030) + pen with the cell's palette. The panel's sprites now draw over it.
- MAME staff screens 2-4 show logo, STAFF and the name lists (work/spfix/grid.png, left fixed / right original).
- runall sp1: vis-violations 0/0, resets 0, game over ok, overruns m7 2 / att 4 (sd1 1 / 6), drops att 1243/148 (sd1 1412/163); one 1-frame m7 dropout at 2952 (route noise).
- Exact p1 9f6956ff / s1 c40c610b and assist 87a9a660 unchanged.

## 18. Overruns toward zero (2026-10-17, DIRECT only)
Overrun = the slot (sched.s) ends more than 2 lines past its deadline (the game loses those lines). Diagnostics build switch `OVR_DIAG` (hal.s: per-commit step times OVD_T, copied at an overrun; work/play/ovstat.lua + runov.sh log one "O" line per overrun; all diag RAM in 0xd00f00-0xd00f3f).
- **Cause 1 (275 of 280 per 540k frames): palettes.** A fade copies all 64 palettes (~28 lines) and the copy's check did not keep time for the commit steps after it. Fix (video.s): `hal_pal_apply` runs after the flip with `HAL_RESV = PAL_TAIL` (5 lines).
- **Cause 2: palette staging in the commit was unbudgeted** (palettes marked while the game ran in a yielded slot; ~600 cycles each). Fix: time-checked staging (`HAL_PALSTT`, 0xd00873); out of time -> the whole update waits (existing deferral).
- **Cause 3: the dirty scans themselves** (64 flags twice, ~9 lines in a fade with mixed groups), then copying nothing. Fix: `PAL_SCAN` guard (10 lines) before scanning; fast paths for groups of four staged palettes.
- **Cause 4: walk remainder in the commit (17 per 1.8M)**: `fx_q_put` wrote the oldest HUD queue entry at once when the 12-entry queue was full, uncharged (2 x ~1050 cycles a moved strip). Fix (fx.s): `FX_QFLN` counts those, `FXU_QFL` 72 units each, HUD pre-check `FXU_HUD+2*FXU_QFL`.
- Remaining (diag, 1.8M frames before cause 4's fix): flip taking ~20-22 lines (5), commit sprite work over its budget (2).
- bench9 (1.8M frames): overruns `an5` 512 -> `ov4` 15 / `ov4n` 13 (causes 1-3).
- Pitfall: stamping inside hal_spr_work (OVS) broke the diag build's game (frame counter jumps); left out.

## 19. dl doubling back-off (2026-10-17, `DL_EXPB`, default 1)
Dense window profile (out_sp1, bot 7 frames 6300-6800): 202.7k cycles/frame; game ~50k, walk ~67k (~1500 per object), conversion ~37k, dl ~15k. dl there: 21 updates vs ~377 failed tries (reasons 12, 14, 11 after a full matching). Back-off after DL_FAILMAX failures now doubles (8, 16, 32, 64; `DL_BOFF` FXS+$6da), reset by a success.
| bench9 | late | frames with drops | overruns |
|---|---|---|---|
| `ov4n` (palette fixes, no back-off) | 4.21% | 0.07% | 13 |
| `ov4` (+ back-off) | **3.12%** | 0.12% | 15 |

## 20. Mirror sharing at the self-split (2026-10-17, `SPR_SHARE2`, default 0)
Probe (work/play/dumpl2.lua + ssan.py, 3 movies): at 197 of 245 self-split drop frames the converting set's whole rest matches the shown set's back entries in order (LOOK 8). Built `sh2_try` (hal/dl.s; hook hal_spr_go .spl), `sh2_flip` / `sh2_drop` (flip hook), new sets blocked while `SH2_ON`. Chain checks clean (work/play/chainchk2.lua knows SH2_ON).
- v1 (X absorbs S's whole run): drops much worse (bot8 2491 vs 757 at 20k; bot9 1827 vs 5) - S's other columns locked.
- v2 (X split: top run + lower run = S's back region, guard above it; S keeps the hole's heads): still worse (1418 / 524) - the lower run sits where S's back was, mid-ring: split fragmentation (section 10).
- v3: only when S ends within `SH2_LOW` of SPR_PB: 16 -> no shares at all in 30k frames x2; 48 under test.
- **Cause 5: flip HUD text under-charged** (strip write ~1200 cycles, charged 960 / 900 in dl_flip): `FX_HSTRIP` 1250 in both (spr.s, dl.s). Flip probe: work/play/flipt.lua (debugger bpset logerror at the flip's steps).
- **Palette trade-off.** With the palettes after the flip, a fade that no longer fits waits a frame (`HAL_PALDEFER`). Deferral reasons (`OVR_DIAG=2`, work/play/pdstat.lua): first mostly the fixed 10-line scan guard -> scaled by dirty groups (`PAL_SCANG`); `PAL_TAIL` 5 -> 2 brought overruns back (463 / 1.8M) because the copy estimate was low: copy measured ~370 cycles a palette + ~70 a clean one in a dirty group -> `PAL_CD` 400, `PAL_CG` 320; groups of four staged tilemap-1 / sprite palettes copied as one 128-byte block (`PAL_C4B` 760).
- **Final (`work/out_ov10`, p1 6a247871):** bench9 late 3.14%, frames with drops 0.10% (8,984 sprites), **overruns 10** (an5 512); regression clean (vis 0/0, resets 0, game over as before, m7/att overruns 0/0). Palette deferrals m7 120-240 / attract 299-373 (sd1: 49 / 106): in ~1-6% of frames flip + palettes + the rest do not fit the vblank + 10 lines; the palettes wait a frame instead of the commit overrunning (sd1 hid this with a ~25% low estimate). Exact 9f6956ff / c40c610b, assist 87a9a660 unchanged.
- Mirror sharing (section 20) final: v3 with SH2_LOW 48 (`s2d`): bench9 drops 0.10% (no gain), overruns 49. Rejected; left in the tree behind `SPR_SHARE2=0`.
- Step 2 (CPU) other findings: dense-frame profile flat (no routine > 9%); flip cost estimation ~1.3k cycles every flip (fixed overhead, not the HUD queue loop). Remaining micro-optimisations each < 1% of a frame.


## 21. Per-frame profile of the whole playthrough, the lost-logic-frame discovery, and the road to zero (2026-10-17)

User request: audit everything so far, generate new ideas for zero drops/overruns/delays, profile every frame of a full playthrough on the latest build, then list the options.

### Method (new tools, `work/play/fp/`)
- `fprof.c`: streams a MAME instruction trace and splits every game frame's cycles (frame = the handler's vblank-flag `addq.b` at 0x9e8) into 48 categories (game subsystems from the function catalogue, HAL routines by label from the build's `hal.lst` via `fmap.py`), plus the cycle offset of markers (idle entry `sch_idle`, timer entry `sch_timer`, `hal_vid_commit`, `hal_spr_flip`, `fx_snap_begin`, `hal_inputs`, `ORIG_IRQ`).
- `fprof.lua`: at the same instant (a write tap on the handler's frame counter at 0x9e2) 100 values per frame: all HAL counters, slot state (K0, deadline, busy, early stage, converting set, ring sets/starts/ends/split, list buffers and piece counts, dl state and failure reasons, dirty palettes/tilemap columns) and an object census (active slots 0x101000..0x1070c0 step 0x60, by sprite category).
- `runfp.sh` / `runfp_all.sh`: 20 chunks of 10k frames, each a power-on run of `bot200k.txt` traced only in its window (so no save-state boundary artefacts), in parallel (~2.5 h); `fpmerge.py` -> `frames.npz`; `fpana.py` -> `report.txt` (copied to `work/catalog/profile_ov10_perframe.txt`).
- `lag2.lua` / `runlag.sh` / `benchlag.sh` / `lagsum.py`: cheap per-frame probe (no trace) of the game's vblank flag at the handler, LATE, holds, busy, drops, overruns, unfinished walks; `benchlag.sh` = bench9 with these columns.
- Alignment of the two streams verified (busy flag vs timer marker, 59/59 frames); the category sums match the older per-routine profiler.

### Result 1: the game's own logic was losing one vblank in five
The idle loop (0xb84 `cmpi.b #1,flag` / 0xb8c / 0xb8e `clr.b flag`) **clears** the flag, so when the handler finds it already set, the logic frame spans two vblanks and one is lost (the game runs in slow motion for that frame). Nobody had measured this: "speed" counted handler frames, which are exactly one per real frame under the no-hold policy.
- `out_ov10`, bot movie 7, 200k frames: **20.7% of vblanks lost** (coast/river 24%, cities 23%, desert 30%, bases 16%, intro/map 3%). Dense frames (>= 45 objects): 88% busy.
- The **original arcade game** on the same bot route: **6.6% lost** (`orig_disasm` 0xb8e 186,221 of 200,000; `lag_orig/`).
- Mechanism (from the profile): the slot order was walk -> conversion; a walk that ate the slot left no conversion begun -> post-commit hold (SLOWB, 56% of frames) -> the game's vblank came late -> the game was still in its logic at line 226 -> timer-started slot (52% of frames) whose walk sampled a half-updated object table -> 1.33 walks per logic frame (64% of all sprite work ran in timer-started slots). Per logic frame the HAL cost 172k, the game 88k: 1.28 frames -> ~22% lost, matching the measurement.

### Result 2: a one-line slot reorder removes it
`CONV_FIRST=1` (hal/video.s stage table: the last list's conversion `.spr` before this slot's walk `.wk`; switch `ifnd` in hal.s, default 0, DIRECT p1 f1bb543c unchanged; exact 9f6956ff / c40c610b, assist 87a9a660 verified) = `work/out_wi3` (p1 70b127b2).

| 60k frames, bot 7 | lost logic frames | sprite-late | sprites dropped (frames) | overruns | holds | timer slots |
|---|---|---|---|---|---|---|
| `ov10` | 21.3% | 2.96% | 710 (129) | 0 | 34,441 | 31,980 |
| `WALK_IDLE=1` (no walk in a timer slot) | 0.24% | 18.0% | 8 (2) | 1 | 3,405 | 1,092 |
| `WALK_IDLE=1,SCH_EXTB_MAX=0` | 0.18% | 27.6% | 0 | 44 | 0 | 279 |
| `WALK_IDLE=1,CONV_FIRST=1` | 0.19% | 34.9% | 0 | 1 | 1,981 | 293 |
| **`CONV_FIRST=1` (`wi3`)** | **0.68%** | **0.30%** | **50 (7)** | 5 | 8,189 | 3,230 |

Whole bench (9 bot movies, 1.8M frames, `benchlag.sh`): **`wi3` lost logic 0.84%, late 0.25%, frames with drops 0.010% (1,154 sprites), overruns 79**, holds 17%, timer slots 7%, walks unfinished in their slot 13% (the list then spans two logic frames), carried conversions 4%. `ov10` on the same bench: **lost logic 21.24%**, late 3.14%, frames with drops 0.099% (8,984 sprites), overruns 10, holds 56%, timer slots 53%, unfinished walks 4.3%.
Regression `runall.sh wi3`: vis-violations 0/0, resets 0, GAME OVER in one frame, m7 LATE 41 (sp1 271) / attract 32 (404), drops 0 / 6, overruns 0 / 2, one 1-frame m7 HUD dip (9226), chain checks clean (movie7 10k, bot 8 60k: bad 0). Not deployed.
WALK_IDLE alone shows the honest deficit: with the walk only after complete logic frames, the game runs at full speed and the sprites take the whole hit (18-35% late): walk + conversion + the rest must fit between the idle entry and the vblank.

### The profile itself (`ov10`, per vblank frame, means; a frame is 202,750 cycles)
- game logic 46.2k + gx 17.2k = **63.5k**; HAL 138k = walk 52.3k (scan 12.0k, emit 31.3k, HUD 3.8k, control 3.1k, sort 1.4k), conversion 22.5k, dl 12.0k, tilemaps 7.6k (+ scrub filler 17.6k), palette 4.6k, scheduler/commit/time checks 11.0k, sprite control 6.0k, flip 2.8k, reclaim 2.0k.
- Saturated frames (no filler, 63% of frames): walk 59k, conv 27k, dl 15k, bg 8.5k, pal 4.8k, fixed 9k, spr_ctl 6.7k, flip 3k, reclaim 2.2k; game 49.5k + gx 16.6k.
- Dense frames (>= 45 objects, 19%): HAL-filler 142k (walk 66k, conv 33k, dl 14k), game 59k; late 11.5%, busy 88%.
- Flat costs that do not depend on content: walk scan 10-12.6k every frame (258 slots); time checks 2.7-3.6k; scheduler 3.3k; commit/early dispatch 2.6k; palette predict/scrub/stage 2.7k with nothing dirty.
- Late frames (6,013): 85% timer-started, 88% held, 82% carried conversion, 42% unfinished walk; 28% have a tilemap load > 15k, 12% a fade > 10k; objects 48 vs 31, columns 106 vs 72 (p50). 64% of them have **no** 3-frame work deficit (scheduling), the rest: cutting 10k/frame fits 89%, 20k 96%.
- Stages: coast/river late 4.9%, desert 4.7%, cities 2.6% (drop frames 0.39%), bases/attract 1.3%, intro/map 1.2%.
- Drop frames (230): columns 334 (p50, the ring's 338), 53 objects, 2 sets in the ring, always split; census **explosions 18.6** objects (others 5.0), buildings 8.4 (1.4), ground 6.5, enemy bullets 6.1.
- Tilemap deferrals 23,562 (12% of frames; rows past the deadline, mostly out of view) and palette deferrals 2,589 are the other "delays"; both are logged slips.
- Walk per object 1.76k (p50, incl. the flat parts), conversion per column 330.

### Options to get to zero (ranked; estimates are per saturated frame unless stated)
**A. Scheduling (the lever)**
1. **Adopt `CONV_FIRST`** (measured above). Open items before shipping: (a) overruns 10 -> 79 per 1.8M: run `OVR_DIAG` on `wi3` (the commit's walk-rest and conversion steps are the suspects); (b) 13% of walks now spill into the next slot and mix two logic frames: hold the game for the walk's rest (a SLOWB-like post-commit hold, usually a few k cycles) or shorten the walk (C1-C3); (c) 7% of slots are still timer-started: finish the pending conversion and commit there, but let the walk wait for the idle entry (WALK_IDLE's rule applied only to the walk, not to the conversion).
2. Preemptive conversion slices: run the pending conversion in short timer-driven slices during the game's logic (safe: it reads a finished list), so the set is ready whatever the idle-entry line; ~300 cycles per slice. Only needed if 1 leaves late frames.
3. Hold policy under `CONV_FIRST` (SCH_HOLD_VPOS 200, SCH_EXTB_MAX 2): holds are 17% of frames now; sweep.
4. `FX_DELAY=0` with the scroll FIFO stage adjusted (the game delays scroll 3 vblanks at 0x940-0x9ae): one frame less latency; no CPU change.
5. **Bench with lag**: make `benchlag.sh` the standard (late, lost logic frames, drops, overruns, unfinished walks); every earlier result (dl back-off, anchoring) was judged without the lag column.

**B. CPU: HAL (saturated-frame means in brackets)**
1. Walk scan [12.6k, flat]: an active-object list filled by gx_upd (one `move.l` per active object) plus the existing activation hooks, instead of scanning 258 slots x 5 passes: -6..9k.
2. dl matching [15k, 7% success in gameplay]: try only when the slot would otherwise idle (the scrub filler would run) or when the predicted headroom allows: -10..14k in saturated frames (79% of dl's cycles are spent there).
3. Walk emission [40k in late frames]: build-time compiled emitters per piece table for the multi-piece types (explosions 0x09, items, shadows, ground enemies); the one-piece path fx_o1 already exists: -5..10k dense.
4. Fixed bookkeeping [sched 3.3k + vid 2.6k + tcheck 2.7k + spr_ctl 6.7k + reclaim 2.2k + flip 3k = 20k]: inline the time check, trim the slot's polling loop, cheaper hal_spr_where/anch sums: -4..8k.
5. Tilemap columns [bg 8.5k; 15% of frames > 15k; 12% of frames defer rows]: precomputed Neo column words per ROM map block, copied at the writer hooks (tm.s already gets the block address) instead of converted (10 lines -> ~2 per column): -5..10k in those frames, scene loads 1.6 frames -> ~0.3.
6. HUD take [3.9k]: skip when score/lives/bombs words and their lookup entries are unchanged (walk-level cache): -2k.
7. Small-bullet pool (0x2d/0xcb/0xca, 1x1; enemy bullets 13.6 per late frame vs 5.5): pool slot ~160 cycles vs walk+conversion ~700: -3..5k dense, and columns.
8. Conversion [27k]: near its floor (330/column; VRAM writes ~100); only fewer entries help. If real MVS hardware accepts 8-cycle VRAM write spacing (the MiSTer core needs 12): -2..3k; needs a hardware test.
9. Palette: fades (8% of frames > 10k) are already deferred rather than overrun; nothing cheap left.

**C. CPU: game side [49.5k + gx 16.6k]**
1. Collision [gx_col 13k + game hitbox/overlap 11-18k]: x-bucketed candidate lists rebuilt per frame (plus the verified activation hooks and a movement margin), the original hitbox code only on candidates: -10..20k dense; exactness checked with the GX_MISS harness.
2. obj_calc_hitbox / obj_cull_outside_rect [objgen 8.9k, 13.9k late]: cache per object per frame (wrap-safe): -2..4k.
3. dir_speed_velocity [math 3.2k]: premultiplied tables instead of mulu: -1.5k.
4. The handler [g_irq 1.5k]: little left (its palette copy loops never run).

**D. Drops (0.010% frames after A1; capacity floor 338 columns)**
1. Shed from the list's back (behind sprites) when the walk's column sum exceeds the free columns (spr_begin_anch already sums): the dropped sprites become shadows/ground instead of HUD/player.
2. Explosion-heavy frames (18.6 explosion objects in drop frames): under ring pressure emit explosions' secondary pieces every other frame.
3. Lend empty tilemap-1 columns to the ring (dynamic top like the bullet pool's RING_TOP): +up to 21 columns covers the overshoot median 5 / p90 24.
4. Small-bullet pool (B7).

**E. Overruns (79 on `wi3`)**: OVR_DIAG round, then the charge of the step found; the flip's HUD strips and the commit's walk rest are the known under-chargers.

**F. Correctness/visibility items found**: mid-logic walks in timer slots (now 7%), two-logic-frame lists (13%), tilemap deferrals 12% of frames (check the slip log for in-view rows), one 1-frame HUD dip per 10k frames in m7 (route noise, present since sp1).

**Budget check**: with A1 the port already loses fewer logic frames than the arcade board (0.84% vs 6.6%). To reach zero in dense scenes the saturated frame must lose ~15-25k: B1 + B2 + B4 alone are -20..30k, C1 another -10..20k; D1-D3 address the last drops; E the overruns.

## 22. CONV_FIRST taken further: it was shedding load by accident (2026-10-17)
- Overruns on `wi3` (OVR_DIAG, 143/1.8M): all in the commit's tail: the walk rest (`fx_snap_step` after `fx_hud_flush`) ran up to ~20 lines over its unit budget (the HUD pass's slot checks/back-offs/end ~390 units uncharged, strips under-reserved) and the tilemap blast could run to the deadline after a fade. Fixes (DIRECT only, kept): `FXU_HPASS` 400 charged when the HUD pass is entered, `FXU_HPRE` 600 per strip, `WALK_TAIL` 3 (the commit's walk rest reserve), a 2-line check after the palettes (`.out` when it fails), `BLAST_LINES` 6: overruns 2 per 600k (cf4d).
- `WALK_HOLD` (hold the game for an unfinished walk): lost logic 10.9%, holds 69%: rejected (switch off).
- **The defect:** with the conversion before the walk, a conversion or in-place update starts on a list whose walk is unfinished in 13% of frames (4% in the old order, where the list is then nearly complete) -> the shown set lacks the objects not reached: one-frame dropouts of most sprites (`work/c3_cf3/m7` frames 2943, 5790, 5860). Guard `fx_listrdy` (hal/fx.s; `hal_spr_work .new`): no conversion/update of a list still being walked.
- With the guard the real budget shows (60k frames, bot 7; lost logic / late): `cf6` (guard, holds 2) 1.5% / m7 LATE 3253, 24% late over 600k; `cf6n` (guard, no holds) 0.18% / 36.6%; `e0` (walk first, FX_DELAY=0, guard) 23% / 2.8% and the sprites wobble against the tilemap (rel.py 45/33 changes vs 0: the scroll stage would have to move); `e0n` (no holds) 0.18% / 34.5%; `g1` (walk first, guard, the overrun fixes) 23.8% / 4.0%, drops 0. The post-commit holds are at once the HAL's throughput mechanism and the lag amplifier; every regime only moves the dense-scene deficit (~10%) between lost logic frames, late sets and incomplete sets.
- B1 (walk scan from the game loop / activation hooks): dead - 86 decentralised activation writer PCs (`work/play/fp/actw/w.txt`), and a list from gx_upd would miss same-frame spawns. B2 (`DL_GATE` time gate on dl_try): any gate (10/25 lines + 3/piece) raised late 0.24% -> 0.65-0.85% and drops 2x; updates in place buy lateness; `dl_chunk` costs ~700 cycles an entry (34k/frame in a scene updating every frame) -> a cheaper match is the lever, not fewer tries.
- Tree default: walk first + guard + overrun fixes (`work/out_g1`, p1 bda07013); switches `CONV_FIRST`, `WALK_IDLE`, `WALK_HOLD`, `DL_GATE` off; exact 9f6956ff / c40c610b, assist 87a9a660 unchanged. Not deployed (MiSTer: `ov10`).

## 23. Back to ov10 as the default; the cycle budget per logic frame; what "no compromises" needs (2026-10-17)

User request: switch back to ov10 as default, re-evaluate, look for new options to hit the targets without compromises.

### Default restored
- The DIRECT default build is byte-identical to `work/out_ov10` again (p1 6a247871, s1 0d03fe97, the deployed build). The 2026-10-17 changes are switches, all off: `OVR_FIX` (BLAST_LINES 6, WALK_TAIL 3, the 2-line check after the palettes, FXU_HPASS/FXU_HPRE charges), `LIST_GUARD` (fx_listrdy: no conversion of a list still being walked), `CONV_FIRST`, `WALK_IDLE`, `WALK_HOLD`, `DL_GATE`. `AEROFGT_DEFS="OVR_FIX=1,LIST_GUARD=1"` = the g1 configuration (`work/out_g1b`, 4 bytes smaller than out_g1: `subq` for `subi`, same logic). Exact 9f6956ff / c40c610b, assist 87a9a660 unchanged (`work/out_exck7`).

### The budget per logic frame (`work/play/fp/fpbudget.py`: ov10 profile joined with its lag run, 199,550 vblanks = 158,107 logic frames)
A logic frame = a non-lag vblank frame with the lag frames that follow it. "Need" = its game cycles + ONE walk (the largest in the group) + ONE conversion + dl (capped 15k) + tilemap + palette + the fixed HAL costs: what the frame would cost with no scheduling waste at all.

| logic frames by objects | count | over 202,750 now | need p50 | p90 | game | walk | conv | dl |
|---|---|---|---|---|---|---|---|---|
| 0-20 | 36,426 | 5.5% | 143k | 191k | 52k | 33k | 10k | 6k |
| 20-30 | 50,707 | 16.0% | 180k | 206k | 74k | 46k | 19k | 9k |
| 30-40 | 37,034 | 54.9% | 205k | 310k | 90k | 56k | 25k | 21k |
| 40-50 | 21,500 | 80.3% | 277k | 365k | 105k | 63k | 32k | 33k |
| 50-60 | 10,804 | 74.4% | 269k | 377k | 112k | 64k | 35k | 22k |
| 60+ | 1,636 | 89.9% | 309k | 380k | 137k | 73k | 42k | 7k |

- Dense logic frames (>= 45 objects, 13% of all): need p50 275k = game 111k + walk 65k + conv 35k + dl ~15k + tilemap 9k + palette 8k + fixed 21k. **The dense frame is ~60-70k over the Neo frame even with perfect scheduling.** What the HAL does today on top (the waste): 1.33 walks and 1.3 conversions per logic frame (extra walks 46k + extra conversions 19k per over-budget logic frame), a feedback loop: lag -> an extra timer slot -> less CPU for the game -> more lag.
- Per piece in dense frames: 51.7 objects, 47.5 list pieces (pair bullets are pool records, HUD strips fix cells); walk 1,275 cycles an object (emit 941 a piece), conversion 689 a piece (330 a column). The intrinsic work (clipping, lookup, ~9 VRAM writes a column at 12 cycles) is ~250-350 a piece: the pipeline costs 4-5x its floor because every piece is encoded into a list, decoded again, charged twice, placed, and matched by dl (7% success in gameplay).
- The game itself: p50 75k a logic frame, p90 130k, p99 184k; > 163k (the arcade's whole frame) in 3.0%.

### What the targets mean
- The arcade board loses 6.6% of its vblanks on this route (coast/river 7.5%, cities 7.2%, desert 8.5%, bases 3.2%, intro/map 2.9%); ov10 loses 20.7% (24.0 / 22.7 / 29.5 / 16.3 / 3.4). The game's real-time speed is 1 - that share: arcade ~93%, ov10 ~76-80% in the stages. Holds and lost logic frames are the same loss in two accountings; a mid-logic walk (timer slot) is a set the arcade never shows (its builder runs after the vblank wait, from the finished objects; a lag frame repeats the last list).
- **"No compromises" = parity with the arcade**: lose a logic frame only where the arcade would (its own logic over 163k), every shown set complete, from one finished logic frame, in order and in step with the tilemaps, no drops, no overruns. "Zero" lag would make the port faster than the arcade in the frames the arcade itself cannot finish; parity is the honest floor (the game logic in those frames is the arcade's own).
- Modelled lost-vblank share after a cut of X per logic frame (no smoothing, so pessimistic by ~9 points at X = 0 against the measured ov10), stage: now / -20k / -40k / -60k / -80k / -100k -> arcade: coast/river 24.0 / 21.4 / 19.3 / 15.1 / 9.5 / 5.7 -> 7.5; cities 22.7 / 19.9 / 18.6 / 15.0 / 8.8 / 4.6 -> 7.2; desert 29.4 / 24.5 / 22.7 / 17.9 / 10.7 / 6.9 -> 8.5; bases/attract 16.3 / 14.6 / 13.7 / 10.9 / 6.1 / 2.8 -> 3.2. **Parity needs 60-80k less per dense logic frame; the HAL's dense cost (~150k with one slot) must roughly halve.** No scheduling policy does that (section 22: every regime moved the same deficit between lag, late and incomplete sets); the alive CPU items of section 21 (B3-B7, C1-C3: -40..55k optimistic) fall short on their own.

### Options (no compromise in the picture; dense-frame estimates)
1. **Fused direct conversion (the structural one, -45..60k)**: the walk writes the Neo columns itself (SCB1 tiles from the lookup run, SCB3/SCB4, the head record, column allocation from SS_HNEXT) instead of 4 list words that spr_go decodes again: one clip test, one charge, no list, no second visibility test, no shape dispatch; per piece ~350-450 instead of ~1,630. dl, FX_KTAB, the carried-conversion machinery and the list ring go; the sort pass keeps collecting pointers (fx_sort) and emits after. The set is complete when the walk ends (a walk that stops for time resumes in the same set). Needs: (a) sprites one frame earlier than now with the game's scroll FIFO stage moved with them (section 21 A4; `e0` wobbled only because the scroll stage was not moved), else the ring holds three sets (shown, waiting, in work) and the 338-column floor bites; (b) the overrun charges per shape (the sprfast tables exist); (c) static scenes lose dl's free frames (attract: a full conversion every frame, ~15-20k, affordable there). Essentially a rewrite of fx.s + spr.s's DIRECT paths (~4,000 lines today), the largest single item and the only one sized for the gap.
2. **Game side (-15..20k)**: C1 collision x-buckets (g_coll 12.4k + gx_col 8.1k dense), C2 hitbox/cull cache (objgen 10.4k), C3 premultiplied velocity tables (math 3.6k). Exactness checked with the GX_MISS harness as before.
3. **Fixed HAL bookkeeping (-6..8k)**: spr_ctl 6.8k + sched 3.4k + vid 2.7k + tcheck 2.3k + reclaim 2.3k + flip 3.3k: fewer stages and time checks once the pipeline is one pass; inline hal_late_n; cheaper hal_spr_where/anch sums.
4. **dl cheaper match (-8..10k, only if 1 is not done)**: dl_chunk compares 8-byte entries against DL_LOOK candidates (~700 cycles an entry): a per-piece 16-bit key written by the walk (w2/w3 + sizes) and compared first drops it to ~100 an entry.
5. **Tilemap columns precomputed per ROM map block (B5, -5..10k in loading frames)**, HUD compare skip (B6, -2k), small-bullet pool (B7, -3..5k): as in section 21.
6. **Scheduling, after the cut**: one walk per logic frame only (no mid-logic walks: the walk after the idle entry, the conversion gone), the virtual vblank held for the walk's rest only (a few lines), FX_DELAY 0 with the scroll stage moved. With the frame fitting, holds and timer slots become rare and the lag feedback loop disappears.
7. Rejected again on the numbers: hold/order policies (22), WALK_IDLE/WALK_HOLD, time gates on dl (B2), activation-hook scans (B1, 86 writer sites), resident sprites (per-object reuse bookkeeping ~1,000 cycles an object, 2026-10-15), high-water scan skips (actives spread to slot ~117), pre-decoded list entries (net ~60 a sprite: the list itself is the cost, not its format).

### Plan proposed
1 first (it alone covers most of the gap and changes what 2-6 are worth), with an A/B harness: the same bot movies, per-frame set checksums against ov10's sets (complete, same order), `benchlag.sh` for lag/late/drops/overruns per stage against the arcade's per-stage lag. Then 2 and 3. Ship ov10 meanwhile (the MiSTer has it).

## 24. Fused direct conversion: the design (2026-10-17)

User request: start on the fused direct conversion design (section 23, option 1). Design only; no code yet. The default stays ov10.

### The timing facts the design rests on
- The arcade's chain (hal/spr.s header, AUDIT 21 line 557, orig_disasm 0x2be50-0x2bfc4): the sprite-list builder is **not a task of its own but the main task's frame loop** at 0x2be50: the frame's object handlers run, then the builder (0x2bee0-0x2bf9a) builds the list from the finished objects (mid-frame, lines ~115-134 in the debug frame), then the frame wait. Handler j copies the list into sprite RAM; MAME buffers sprite RAM at vblank j+1 and draws it at vblank j+2. So **the objects as they stand at slot j (before handler j) are shown at vblank j+2**, and the scroll the handler writes at j (its 2-stage FIFO 0xff8ca8 -> 0xff924e -> 0xff9256 -> 0xff925e) is the game's own compensation for that.
- The HAL today: walk at slot j (list j), conversion in slot j+1 (`FX_DELAY` 1), flip at commit j+2: **exact**. `e0` (FX_DELAY 0, shown at j+1) wobbled because it was one frame early. The fx.s header's "list k-2 / slot k+3" text is stale (FX_DELAY was 2 then).
- A logic frame that overruns its vblank: the arcade's handler finds no new list (the build has not happened, or is mid-build: lock 0xff9236) and copies nothing; the last list is shown again at j+2. That is the only kind of "lost" frame the arcade has, and parity means exactly that behaviour and no other.
- Why not one pass in the HAL slot writing columns at once (section 23's first sketch): the ring would hold four sets (shown, two complete, one in work), 84 columns each, unless sprites are shown at j+1 with the game's scroll FIFO shortened: a game patch and a latency the arcade does not have. Rejected here in favour of the design below, which keeps the arcade's timing and three sets.

### The structure: two halves, the cheap one at the arcade's own build point
1. **Object half, in game time, at the builder's point** (0x2bee0 jumps to it in DIRECT builds the way it jumps to 0x2bfaa today; it ends with `jmp $2bfaa`; register conventions as hal/dx.s: d2/d3 kept). It walks the object tables in the builder's order (pass 1 0xff0000.., pass 2, the group sorted by x unless 0xff90e6, pass 3; hal/dx.s dx_pass/dx_group are this walk already) and writes **one 16-byte record per active object** into the next free record buffer:
   - +0 l C table ($1a) | flags in bits 0-1 (zoom from the object: type 0x2e; colour from the object: b5 bit 7)
   - +4 l B/A table ($44, 0 none) | bit 0 B (b43 bit 7), bit 1 A (b43 bit 6), bit 2 b43 bit 4 (B/A without the object's colour)
   - +8 w y ($e), +10 w x ($10)
   - +12 b C pieces - 1 (b4), +13 b B/A pieces - 1 (b43 & 15)
   - +14 b the w2 byte as fx_objg composes it (colour, bit 5 from b19, flips from b2a or 0 = the pieces'), +15 b zoom nibble (b1) | pass-1 flag (HUD eligible) | pair-bullet flag (type 0x18)
   plus a header: record count, the pieces' column sum (the anchor estimate, see open points), and the **completion stamp** = HAL_FRAMES at the end of the build. No clipping, no pieces, no lookup: ~150-200 cycles an object (12 loads, flag composition, 4 long stores) + the slot scan (~5k, the 8-way `tst.b` loop as fx_walk) + the sort: **~15k in a dense frame, in game time**, which is where the arcade pays 48-61k for the same thing.
   - Because it runs where the arcade's builder runs, it never sees half-updated objects (no mid-logic walks, no mixed sets, no `btst #0,3(a3)` guard, no fx_hud_pend: a new HUD object is 0x81 by then, as the arcade sees it), and a logic frame that overruns produces no record set for that vblank: the previous set stays shown. **Parity scheduling by construction**; WALK_IDLE/WALK_HOLD/CONV_FIRST and the hold policies of section 22 have nothing left to decide.
   - The stamp decides when the records are due: a buffer completed with stamp s is converted in slot s+2 and shown at commit s+3 (normally s = j-1 for the records of the objects at slot j: converted in slot j+1, shown at j+2, as today). A build interrupted by a timer slot (the game busy at PHASE_LINE: the arcade's handler mid-build) completes with the later stamp and is shown a frame later, as the arcade shows it.
   - Buffers: 4 x 96 records x 16 bytes = 6 KB in the old lists' sprite RAM (0x1d0000.., the 5 KB of FX_LISTS plus dl's and sprr's 1 KB; FXS state stays at +$1000). A buffer is free when it is neither due, nor being converted, nor waiting; none free (a conversion carried two slots) -> no build this frame, the last records repeat (a late frame, logged), as fx_snap_begin does today with 5 lists.
2. **Piece pass, in the HAL slot (hal_spr_work's framework)**: the due record buffer **in the list's order** (the first record first, the tables B, C, A, the pieces from the first). Correction found in stage 1: the DIRECT conversion already went UP the walk's list from its first entry (fx_start: a5 = the first entry; hal_spr_go's DIRECT .ent advances), so the first list entry gets the highest columns and is drawn on top (the pool note in hal/fx.s: 'slots before theirs' are in front); the non-DIRECT header's 'last entry on top' describes the original list's own buffers. The pass keeps that order, so the ring's descending allocation, the drop policy (the list's end dropped first), the split and restart paths, reclaim and flip all stay as they are, and the sets come out identical to ov10's. Per piece it does what EMIT does today up to the words (the builder's clip test, the Neo-screen test with the wrap, oy/ox with the scroll offsets, zoom, colour/flips, map) but **leaves them in d2-d5 and jumps into the generated shape routine** (`spr_fast_jt`, tools/gen_sprfast.py: charge, column allocation from SS_HNEXT, head record, SCB4, SCB1 tiles from the lookup run, zoomed shapes' SCB2) exactly as hal_spr_go dispatches today. The list is never written or read; the entry decode (.ent/.fxp), the second visibility test, the wrap path's re-read of the words (d2-d4 are intact: `spr_go_wrap` just continues), FX_KTAB/FX_DELTA, dl, the carried-list bookkeeping and FX_DELAY's buffer arithmetic go. The HUD take (fx_hud_take on pass-1 pieces with map 0x3fc0+) and the pair-bullet pool decision (fxb_obj: pool record or 2x2 sprite) happen here, before the dispatch, as in EMIT today; the HUD pass (fx_hud_draw, the queue) at the pass's end; the queue flushed and bp_apply run at the flip that shows the set, as today (the queue then holds one pass's strips, not two walks').
   - Resume state (a budget stop): record pointer, table, piece index (HAL_SPR_RA5 becomes 3 words). Head-slot limit: `cmp a4` per piece instead of hal_spr_glim's list arithmetic.
   - Charges: per object 10 units (record load, table set-up) + 5 units a piece (the test path, ~70 cycles, invisible pieces included) up front; each visible piece then charges its shape's constant as now, with PRE_MAX recomputed for the new pre-dispatch path (~330 cycles worst: EMIT's tests and composition, the index). Today's walk charges 34 units (544 cycles) a piece up front and stops walks that had time; that over-charge goes too.
   - The ring, flip, reclaim, where/begin/lim, hal_spr_refill/klim/left, the zoom general path (.gen/.zoom), .drop/.spl/.rst, spr_lo_v/z, SPR_ANCH: unchanged. `spr_begin_anch` takes its column sum from the record header instead of the list.
3. **Schedule (hal/video.s, hal/sched.s, DIRECT)**: prep: pick the due records (replaces fx_snap_begin); early stages .bg1, .car (a carried pass), .spr (the due pass), .bg2, .scrub (the .wk walk stage goes); commit: place, flip (+ HUD flush, bp_apply), palettes, blasts, the pass's rest (SPR_TAIL), bg (the WALK_TAIL stage goes). sched.s: FX_SDONE/WALK_HOLD/FX_PON/FX_DELTA references go; `sch_ready`'s hold (SCH_EXT_MAX 0) and `.hold` (SCH_EXTB_MAX 2: the due pass not begun) keep their meaning. NSPRSETS 3, FX_DELAY semantics kept (records due two slots after their stamp).

### What goes (DIRECT builds; the exact build is untouched)
hal/dl.s entirely (2,816 lines: dl_try/dl_step/dl_chunk/dl_flip/dl_skip/dl_nod/dl_done/dl_begin, DL_SETS, SPR_SHARE/SPR_SHARE2 and sh_*/sh2_*), hal/rs.s and hal/sprr.s paths, hal/fx.s: fx_ltab/FX_LISTS/FX_PHYS/FX_LN/FX_LSEQ/FX_WP/FX_KMOD, fx_start/fx_dupq/fx_listrdy, fx_snap_begin's buffer choice, fx_snap_step, fx_walk's pass machine and its slot scan, fx_obj/fx_objg/fx_o1/fx_o1chk, EMIT/EMIT1's list writes (their computations move into the pass), fx_hud_pend, FX_CBUF/FX_SBUF; hal/spr.s: hal_spr_go's .ent/.fxp/.skp/.off decode for DIRECT, hal_spr_glim's list form, hal_spr_end/fx_start, bp_cost's and fx_hud_count's list scans at the flip (per-set counters written by the pass instead), the FX_DELTA/FX_DHOFF/DL_HOLEC branches in .hoff/.fin/hal_spr_flip. hal/dx.s becomes the object half (it is the builder walk already; it writes records instead of attribute words). Kept: the HUD on the fix layer, the pool, the shape generator (its DIRECT PRE_MAX branch changes), the ring.

### Cost model (dense logic frame: 51.7 objects, 47.5 visible pieces, ~30 invisible)
| | today (ov10) | fused |
|---|---|---|
| per object (scan, set-up, record) | ~330 | ~200 game time + ~120 pass |
| per visible piece | EMIT ~400 + conversion ~690 = ~1,090 | ~250 (tests, oy/ox, compose) + ~60 (index, dispatch) + ~150 (charge, alloc, head, SCB4, attributes) + 60-180 (columns) = ~520-640 |
| per invisible piece | ~70 (+ the 544-cycle up-front charge) | ~70 |
| dl | ~15k | 0 |
| list, carry, stage bookkeeping (fx_snap_*, hal_spr_end, FX_*, DL_*) | ~5k | ~1k |
| one slot's HAL sprite work | walk 65k + conversion 35k + dl 15k = 115k | object half 15k (game) + pass ~35k |
| the waste (1.33 walks, 1.3 conversions a logic frame, AUDIT 23) | +46k +19k per over-budget logic frame | 0 by construction (one build a logic frame, one pass a record set) |

- Direct cut per dense logic frame: **-45..55k** (pieces -24..29k, dl -15k, bookkeeping -4k, the walk's over-charge). On top, the waste (-30..65k in over-budget frames) disappears structurally, which is what the scheduling experiments of section 22 could only move around. Dense frame after: game 111k + build 15k + pass 35k + tilemap 9k + palette 8k + fixed ~18k + flip 3k = ~200k against 202,750: at p50 it fits, at p90 it does not. **The game-side cuts (C1-C3, -15..20k) and the fixed bookkeeping (-6..8k) are still needed for parity's margin; the plan order of section 23 stands.**
- Honest floor: lookup fetches and VRAM writes (>= 12 cycles apart, 3 a column minimum) and the head records are inherent to the double-buffered flip; resident sprites (hal/rs.s) and in-place updates (dl) were the attempts to avoid them and both cost more than they saved.

### Open points (decided in stage 1 by measurement, each a switch)
1. Anchor estimate for `spr_begin_anch` (it needs the set's columns before the set begins): (a) the object half sums each piece's xsize+1 from the piece graphics (~20 cycles a piece, game time, unclipped: an upper bound, starts the set higher than needed), (b) HAL_SPR_PREV only (the pre-anch behaviour: 95% of the drops then), (c) the object half clips too (~70 a piece, exact). Start with (a), measure drops with benchlag.
2. Record buffers: 4 (6 KB) vs 3 with "no build when none is free". Start with 4.
3. SS_HNEXT/SS_HMIN in registers across the pass (the generator's alloc code uses memory: ~30 cycles a piece): after the pass works.
4. The pair-bullet pool: keep as is first (its gain is columns, not cycles); the 2x2 fused path costs ~250 a bullet without it.
5. The record's 16 bytes assume the table pointers are even (they are: the odd-pointer case was the mid-rewrite guard, which the build point makes impossible); a `fail` check at build and a count of odd pointers in diagnostics.

### A/B harness (before any of it is default)
- `fliphash.lua` (new): at every flip (a tap on hal_spr_flip's shown-set write, HAL_SPR_SHOWN), a hash of the shown set read straight from the Neo VRAM (the `:spritegen` m_videoram item, as work/play/chainchk.lua reads it): per head in SS_HADR order its SCB3 and SCB4, and the SCB1 tile/attribute words of all its columns; keyed by HAL_FRAMES. ov10 and the fused build on the same bot movies must agree frame by frame except where either run flags late/dropped/held (the sets are built by the same allocation from the same pieces in the same order, so equal content is the expectation, not a statistic).
- `benchlag.sh` per stage (lost logic frames, late, drops, overruns, holds) against the arcade's per-stage lag (6.6% overall: coast 7.5, cities 7.2, desert 8.5, bases 3.2).
- The attract comparison pipeline (test methodology memory) frame for frame: the fused build keeps the arcade's timing, so the comparison stays exact; `rel.py` (sprite vs tilemap relative motion) must stay at 0 changes.
- The MiSTer boot test and the HUD/pool pictures as in work/play/hud, bat_*.

### Staging (each stage a build under `FUSED` (ifnd, default 0: byte-identical to ov10), measured, none shipped until the harness passes)
0. Harness: fliphash on ov10 as the baseline (bot movies 7-15, 60k frames each), the tap confirming the builder point's order (0x2bee0 after the frame's object handlers, before the idle entry) over a few hundred frames.
1. Object half (hal/dx.s -> records) + piece pass (hal/spr.s: the record loop in place of .ent, EMIT's computations as a macro per table kind, dispatch into the shape routines) + schedule changes; dl/rs/sprr out under FUSED; the HUD and pool unchanged. Goal: identical fliphash to ov10 wherever ov10 was on time; benchlag per stage.
2. The charges (PRE_MAX recomputed, the per-object charge), SPR_TAIL/BEGIN_LINES retuned, open points 1-3.
3. Full playthrough per-frame profile (work/play/fp) of the fused build against the budget model (fpbudget.py): per-stage lost logic frames against the arcade's.
4. Then section 23's items 2 (game side C1-C3 with the GX_MISS harness) and 3 (fixed bookkeeping), and the scheduling clean-up (section 23 item 6) once the frame fits.

### Risks
- The object half runs in the game's task context (its stack, its registers): follow hal/dx.s's conventions exactly (it ran the whole playthrough as DIRECT=2's check build with the original builder after it, so the conventions are known).
- The game's boot RAM test wipes sprite RAM (the records) and G_SPRBUF (set states): the magic/reset path of fx_magic covers the records' header too.
- Record overflow (> 96 active objects): the object half stops at 96 (the back is dropped, as the list's FX_LMAX dropped it) and flags the set (a slip).
- The HUD take and the pool need the HAL's state (FX_HOK, BP_*) at the pass's time, not the build's: they stay in the pass; nothing of the HAL's is read in game time but the free record buffer index and HAL_FRAMES.

### Stage 0 and stage 1: status (2026-10-18)

**Stage 0 (harness).** `work/play/fh/ordtap.lua`: in every idle-entry slot of ov10 (1,694 of 1,694) the game's builder point (the lock clear at 0x2bfaa, PC 0x2bfb2) is the last object-table write before the slot; the other per-frame hit on the lock is the vblank handler's own clear (0x9dc). New tools: `fliphash*.lua` (per-flip VRAM hash of the shown set: the first form mixed the column addresses in, the second chained into the ring's neighbours; `fliphash3/4` hash each head's own column, `4` with the game's logic round), `fhcmp.py`/`fhround.py`, `fhdump*.lua` (the heads of the shown set at a frame / at a round), `entries.lua` + `encmp.py` (the entry sequence per logic round: ov10's list at the walk's end vs the pass's dispatched words, FZ_DW in FZ_DIAG builds, pool records tagged), `fzdiag.lua`/`fzdump.lua` (the pass's state, stop causes, tail timings), `ovd.lua` (OVR_DIAG: lines past the deadline and the commit steps at each overrun), `wtap.lua` (writers into a RAM range), `tests/harness.lua` `HARNESS_BY_ROUND=1` (the movie's inputs applied per logic round instead of per handler: two builds that lose different numbers of logic frames then play the same game round for round; the game's vblank-count timers - animation phases, some spawns - still diverge after ~300 rounds, so the exact A/B window is the intro and spot checks after it).

**Stage 1 (`FUSED=1`, hal/fz.s; the default stays byte-identical to ov10: p1 6a247871).** Built as designed with these corrections found on the way:
- The game's RAM gap 0xff9aa0.. is NOT free (hal/bg.s's column staging writes there: hal_bg_column) and FXS+$700 is hal/tx.s's (FX1_HL/FX1_MASK). The records live in the sprite RAM the walk's lists and hal/dl.s had: 3 buffers of 80 records (the playthrough's most is 77 active objects) at G_SPRRAM+$510, +$a20, +$1800; the pool records at +0, the pass state at +$300.
- The piece tables are only word-aligned: no flags in the pointers (the first format masked 0x4fea to 0x4fe8 and read the wrong pieces). The record is one per TABLE (B, C, A of an object in the builder's order), 16 bytes: table, piece routine (resolved at build time), y, x, w2 byte | charge << 8, pieces - 1, zoom nibble; a pair bullet is one record with fz_bul as its routine.
- Direction: the DIRECT conversion goes UP the list (the first entry on top), so the pass runs the records in list order (section 24's text corrected above).
- A buffer is stamped with HAL_FRAMES at completion, before the builder point increments the round: its records belong to the round after the stamp's (the A/B keys allow for it).
- "Nothing due" (the game made no new round two slots ago) must set HAL_SPR_DONE, else hal/sched.s holds the frame waiting for a pass that cannot come: a feedback loop that put the fused game ~80 rounds behind ov10 by frame 300.
- MAME's write tap fires before the write: a probe reading the written word back sees the previous value (the "swapped maps" red herring).
- Charges: PRE_MAX for FUSED 620 (fz_next + fz_em_* + fz_disp), FZU_TAB 26 (fz_ntab measured ~370 cycles), FZU_PIECE 8, FZU_HUDT 40 (fx_hud_take), FZU_GO 16 (fz_go), the HUD pass's 5-line reserve, ANCH_LINES 8 (fz_anch, the anchor from the records: an unclipped upper bound). The commit's tail (OVT 7 -> 8) overran by up to 17 lines at the first bounds, by 1-5 lines now (`ov_fz8o`: 809 overruns in 12,000 frames, 2-7 lines past HAL_KDL): the bounds are still ~15% under somewhere; open.

**Correctness.** `encmp.py` with `HARNESS_BY_ROUND=1`: rounds 8-297 (the intro, before the vblank-count divergence) 267 of 267 rounds identical in entries, order and pool records between ov10 and fz7 (maps masked for 10 rounds where only the animation phase differs). The VRAM content per sprite is identical (fhdump at gf 76 / 330: same SCB3/SCB4/tiles, the heads in the same order; the start column differs only by the anchor). The pass retries a piece after a budget stop (the first try writes nothing; `encmp` collapses the repeat).

**Lag (bot 7, 20,000 frames, `benchlag` columns; ov10 on the same movie: lost logic 20.8%, late 3.0%, overruns 10/200k).**
| build | lost logic | late | holds | busy | overruns | carried | coast/river lost / late |
|---|---|---|---|---|---|---|---|
| fz1 (first) | 2.5% | 13.4% | 3099 | 3287 | 4219 | 4778 | - |
| fz4 (hold fix) | 2.9% | 12.2% | 2588 | 3135 | 1677 | 3501 | 3.4 / 16.1 |
| fz7 (per-table records, trims) | 4.3% | 15.2% | 3147 | 4208 | 1763 | 3930 | 5.5 / 19.9 |
| fz8 (charges) | 3.0% | 10.7% | 2245 | 2763 | 1061 | 3447 | 3.5 / 13.7 |
| ov10 | 20.8% | 3.0% | 111260 | 104351 | 10 | 13719 | 24.0 / 4.9 |
(The arcade: coast/river 7.5% lost. ov10's holds gave the HAL the game's time; without them the same deficit shows as late sets. SCH_EXT_MAX 0 = the user's 2026-10-15 choice: full speed, late sprites rather than holds.)

**Cost (per-frame profiler, fine split `work/play/fp/fmap_fine.py`; a light coast window, 19 objects, fz5 vs ov10's coast frames):** sprite path 65.9k vs 67.6k: NO net gain. The piece work fell as designed (emit 22.6k -> 12.2k, shape routines 15.9k -> 10.0k, dl 4.9k -> 0) but the record round trip ate it: fz_rec 530 cycles an object (the decode + 4 stores), fz_ntab 370 a record (the state copies, the charge), fz_build/fz_pass/fz_group 8.1k (the slot scan 5k + the loop), fz_disp 130 a piece, fz_go/begin/due/anch/fin 3k. The 68000's absolute-address state traffic (16-20 cycles an access) is the cost; the design's estimates (200 + 120 an object) were 3x too low. After the trims of fz7 (single-piece records dispatched straight, the charge precomputed at build time), a second window (fz7, frames 84000-86000, which the fused game reaches at a lighter point: 12.7 objects) against ov10's frames of the same stage and density (13.3 objects): sprite path 46.2k vs 55.9k (-9.7k, -17%); there fz_rec still costs ~675 cycles an object and fz_ntab ~390 a record. So the per-object overhead of the record structure is ~1,000 cycles against the old walk's ~300, and the per-piece saving ~500: in a dense frame (52 objects, 47 pieces, pair bullets pooled) the two nearly cancel: ~52 x 1,000 + 47 x 860 + fixed 8k = ~100k against ov10's 115k, -15k, nowhere near the -45..55k of section 23. The record round trip is the structure's cost and cannot be trimmed below ~600 an object on a 68000 (every piece of pass state is a 16-20 cycle absolute access, and the decode has to happen once somewhere).

**The fork.** The record trip exists only to keep the arcade's sprite timing (shown two slots after the objects' round) with three sets in the ring. The alternative, "the pass in game time at the builder point": one routine at 0x2bee0 reads the objects and writes the set's columns at once (the decode ~300 an object, no records, no due/begin/fin, no slot budget: the pass runs to completion in the game's round, as the arcade's builder did), the HAL slot only flips; a round that overruns its vblank leaves the old set shown, exactly the arcade's lost frame; late sets and carried passes disappear by construction. Cost ~52 x 400 + 47 x 830 = ~60k in game time against ov10's 115k of slot work: -55k dense, the design's number. The price: three sets in the ring need the set shown ONE slot after its round (the arcade: two), i.e. sprites one frame earlier than the arcade (less input latency, not a visible error), with the game's scroll FIFO shortened by one stage (a 2-instruction patch at 0x940-0x9ae, DIRECT builds only; `e0` showed the wobble without it) so sprites and tilemaps stay aligned; the palettes are applied by the HAL at the commit before the sprites appear, so no colour glitch; tilemap CONTENT changes land one frame nearer the sprites than on the arcade (two rounds apart there, one here). Also needed: the VRAM address/modulo registers are shared with the slot's interrupt, so each piece's column writes run with interrupts masked (~40 cycles a piece, the timer slot delayed by at most one piece), and reclaim moves into the game-time build. This changes the picture's timing relative to the arcade by one frame for sprites: the user's call, not mine.

### The game-time pass tried (`FUSED=2`, 2026-10-18) and the parity metric

User decision: go with the game-time pass. Built as `FUSED=2` in hal/fz.s (fz_gt: reclaim, a free set, hal_spr_begin, the objects walked straight into the shape routines with interrupts masked per piece (fz_gt_piece / fz_next restore FZ_SR), the HUD pass, the set complete with RDY = its round's slot + 1 + FZ_SHOW; the slot's hal_spr_work a stub; hal_spr_refill/left "plenty"; the generator without charges; the handler's scroll registers read the game's FIFO 2 - FZ_SHOW stages fresher (tools/aerofgt2neo.py: 0x8e5/0x8fb/0x915/0x92b); a wait at the ring's tail resumed in the slot's tail when the slot is still ahead (fz_gt_wait/resume), and a largest-free-run allocator with the nearest-set limit (fz_gt_where/lim, hal_spr_where/lim under FUSED=2) because the slot's allocator left the hole below the shown set unused). Correct: entries identical to ov10 (266/266 rounds); sprites and tilemaps aligned (flipscroll.lua: the same set content with the same scroll in both builds, 26/26).

**Measured against the only metric that means parity** (`work/play/fh/parity.lua`: at each flip, the frame the arcade would first show that round's list in = the first slot after the round's builder point + 2 (sprite RAM double buffered), against our frame; bot 7, 15,000 frames):
| build | earlier | parity | 1 late | 2 late | lost logic | drop frames /20k |
|---|---|---|---|---|---|---|
| ov10 | 0 | 96.4% | 3.5% | 0.03% | 20.8% | 230/200k |
| fz8 (records) | 0 | 89.6% | 9.9% | 0.4% | 3.0% | 32 |
| fz12 (game time) | 99.9% (one frame) | 0.06% | 0 | 0 | 8.7% | 1,330 |
(ov10's set numbers are the walk's slot, shown two later = parity. The lost-logic and "late" lag columns of lagsum.py overlap: a lost round is a flip without a new set.)

**Why the game-time pass loses**: (1) its per-object control costs ~1,080 cycles (profile, bases 35 objects: fz_gt* 37.8k) - the same ballpark as the arcade's own builder (48-61k dense at 10 MHz), so its round = the arcade's round + the column writes (shape routines 14-25k) that the arcade's hardware does: with the pass in the round, rounds overrun the slot more often than the arcade's overrun its vblank (8.7% vs 6.6%; bases 5.2 vs 3.2, coast 13.2 vs 7.5). (2) The ring: at a build three sets are live (shown, the complete one waiting for its flip, the one in work), and in an overrun round the pass cannot wait for the flip that frees the oldest (the game goes on, the objects with it), so dense busy sequences drop sprites (1,330 frames with drops in 20,000); the records pass in the slot straddles its own flip and never has to. (3) One frame earlier than the arcade by construction (FZ_SHOW=0, two earlier, drops more: 609 by frame 2,750). The game-time pass stays in the tree as FUSED=2 (switch off) and is not the way.

**The records pass (FUSED=1) is the base**: parity 89.6%, the rest one frame late = the pass did not finish by its flip, because it was allowed to begin only two slots after the round (slot j+1 for records made before slot j), i.e. in dense sequences two busy slots' slack (~2 x 30 lines). fz13: it may begin in slot j's commit tail already (right after that flip, which frees the set it converts into: three sets still; RDY unchanged): fz_due's "a slot early, after its commit's flip".
- fz13 (the pass may begin in the previous slot's tail): parity 96.0%, one late 2.7%, one EARLY 1.2% (hal_spr_work's RDY = the slot after the one the pass began in: wrong for a pass begun early; fz14 sets RDY from the records' stamp), lost logic 1.9%, 16 frames with drops in 20,000, overruns 946 (1-5 lines), coast/river lost 1.7%.
- fz14 (RDY from the stamp): parity 94.0%, one late 6.0%, none early; lost logic 2.8%, 22 frames with drops in 20,000, overruns 1,671 (1-5 lines). (Runs differ in game state once their lag differs: +-2 points between runs.) Current best: `work/out_fz14` = `AEROFGT_DEFS="FUSED=1"`; the default stays ov10.

### Late sets, overruns, drops, the round trip (2026-10-18, fz16-fz21)
Tools: `work/play/fh/fzev.lua` (event log of the pass with CPU-cycle stamps: record dispatch, refills (`FZ_COST=1` diag writes in hal_spr_refill), run start/end, buffer states, begins, flips, frames, busy; write taps only - MAME's read taps never see ROM/opcode fetches; the pass's code addresses from the build's `hal.lst` via `LST=`), `fzcost.py` (actual cycles against the charge per record, per refill segment, per HUD pass; tail runs' end lines), `fztl.py` (per pass: completion, begin, runs, flip delta, and the sets never shown), `work/play/fp/batsum.py` + `F=60000 benchlag.sh` (9 seeds x 60k frames, ~5 min). Single-seed lag runs of different builds play different routes (the bot's inputs land on different rounds): only the 9-seed battery compares builds, and even its stage mix drifts.

**Overruns (1,188 per 20k frames in fz14, all in the commit's tail)**: the per-record and per-piece charges were right (actual 2.6% under the charge over 8,142 tail runs); the under-charge was one path: pieces in the HUD's lookup range (score digits, texts: `fz_em_xxx1` -> `fz_hud` -> `fx_hud_take`) were charged `FZU_HUDT` 40 units (640 cycles) and cost 1,340-1,430 each, 3.7 of them in nearly every pass. `FZU_HUDT` 90: overruns 8 (fz16), 4-7 later; the battery: 49,026 -> 29-57 per 536k frames. The two remaining large ones (31, 59 lines) are commits that start 40+ lines late at a stage change (the game's RAM test with interrupts masked), not budget.

**`ANCH_LINES equ 6+2*(FUSED>0)` was 4**: vasm's true is -1. Now `ifne FUSED` 8 / 6.

**One-late sets**: late passes are the dense ones (44 records, ~81k cycles, 4-5 runs); the pass was allowed to begin only two slots after its round (stamp + 2; stamp + 1 only in the commit's tail), a one-frame window: after a burst the queue could not catch up although the HAL idled with the next buffer complete. `FZ_EARLY` (hal.s, default 1): a buffer at stamp + 1 is due whenever nothing older is (fz_due's a3). But the post-commit hold (sched.s `.hold`) then held the game for sets not needed at the next flip: `fz_urgent` (RDY of the set in work <= HAL_FRAMES + 1) gates it. The flip's "newest eligible wins" then SKIPS a late set when the next one is on time (freed unseen): `fztl.py` counts these never-shown sets - 2.0% of passes in fz14, 3.0% in fz16, 0.5% in fz21 - which `parity.lua` never saw. Two logic rounds in one frame (after a lost one) made two buffers with the same stamp; the early path converted both (the first freed unseen): fz_build now drops an older complete buffer with its stamp (`FZ_NDUP`).

**The round trip**: per-record set-up (fz_ntab) ~370 -> ~300 cycles: a terminator record (routine `fz_toh`, the HUD pass) instead of the end compare, the HUD-phase test once per run in fz_go instead of per record, the zoom nibble pre-rotated at build time (record +14 b zoom << 4, +15 b pieces - 1; `FZ_BSZ` 1312, B1 at +$a30). Measured (invisible 1-piece records = set-up + one clip test): 560 -> 477; 1-piece shapes 1,486 -> 1,417; HUD pieces 1,738 -> 1,666. Per visible piece the rest is fz_next 40 + fz_em ~450 (two clip tests, four words) + fz_disp 90 + the shape routine 330-470 (VRAM writes): near its floor without precomputed piece descriptors (a tool-side table per ROM piece: shape index, w2/w3 contributions, ~-200/piece) or a HUD fast path (~-300/piece x 3.7 per pass). fz_rec (game time, 530-675/object) is branchy per-instance tests on the object's bytes; ~10% at most.

**Crashes (every FUSED build up to fz23; found on the MiSTer, "a few seconds into the attract, after the boat launches its missiles")**: (1) fz_group's emit loop counted in d6, which fz_rec clobbers: the loop ran on into stale stack entries - garbage records (the "16-piece table at y 1078") - and at the missile launch a stale object pointer took the builder into an address error; the game's error vector (0x436) reboots the game ("MEMORY CHECK" at 0x400, the RAM-test patterns over the sprite RAM). There is NO stage-change wipe: ov10's attract and playthroughs have no frame-counter resets at all; every FUSED run so far rebooted at the first attract scene (~game frame 1781) and again whenever the attract's missile scene recurred, the bot re-coining through its movie - all numbers before fz24 are from those rebooting games (the game after the reboot is the sparse first minute again and again). (2) The record builder copied the table pointers raw where fx_objg clears bit 0 (the game's flag; an odd table = address error): now cleared, and the first version of that fix clobbered d1 (the pair bullet's fxb_ok index) so fz_bul indexed fxb_k at an even offset: fz23's reboot 66 s into the attract. fz_reset's abandon of the set in work and hal_spr_work's FX_MAGIC check (fz21) stay as hardening: after a reboot's RAM test the HAL must not resume a pass through wiped pointers (that secondary loop was what made fz17-fz20 look different from fz14-fz16). Attract check: `runfh.sh <rom> <out> 12000 fzev.lua work/play/attract.txt` (no inputs): no HAL-frame stalls, no RAM-test writes, no "frame counter jumped" in the harness log (fz24: clean for 12,000 frames; the MiSTer attract passes the scene).

**Drops**: 0 frames with drops in fz21's 20k run (fz14: 22); the battery 0.314% of frames (fz14b 0.335%, fz21e0b 0.373%; route-dependent: seed 11's coast/river 227 frames, seed 10's 2). The patterns seen: split-set fragmentation at capacity (a 120-column shown set split around a 115-column hole), and in fz17 the duplicate conversion's freed set stuck behind the shown one. The records-based anchor (fz_anch) is an unclipped upper bound over the first 96 pieces; an exact clipped need would cost ~60 cycles a piece per begin and only changes the top/bottom decision; not done.

**Real-game numbers (fz24, the first FUSED build that does not reboot; the bot now reaches cities/desert/ocean, 31 records a pass on average)**: parity.lua 20k: on time 12,561, one late 299 (2.3%), two late 22; FZ_EARLY=0: one late 1,207 of 11,840 (10.2%). fztl: on time 93.6%, never shown 0.5%. Overruns 5; drop frames 36 per 20k; entries = ov10 rounds 1-297. Battery 9 x 60k: fz24b (FZ_EARLY=1) lost logic 7.07% / lag2-late 17.5% / drop frames 1.85% / holds 231k (coast 7.4, cities 6.6, desert 15.0, ocean 9.4); fz24e0b (FZ_EARLY=0) 3.97% / 23.3% / 1.14% / holds 126k (coast 5.5, cities 3.3, desert 5.0, ocean 6.2); ov10 (section 21) 20.7%. FZ_EARLY buys 8 points of on-time sets for 3 points of lost logic - above the arcade's 6.6% in the dense stages - and 0.7 points of drop frames; the default is still 1, the user's call (`AEROFGT_DEFS="FUSED=1,FZ_EARLY=0"` = out_fz24e0). The MiSTer has fz24 (p1 77ce58de): attract through two cycles and coined play tested.

**Numbers of the rebooting games (fz21 = `AEROFGT_DEFS="FUSED=1"`; kept for the record, NOT comparable: the game restarted at the first attract scene)**: parity.lua 20k: on time 13,791, one late 48 (fz14 749, fz16 438), two late 1; fztl: on time 98.8%, never shown 0.5%; overruns 7; drops 0 frames; entries identical to ov10 for rounds 1-297 (by-round harness). Battery (9 x 60k): fz14b lost logic 3.47% / drops 0.335% / overruns 49,026; fz16b 3.14 / 0.296 / 29; fz21b 3.44 / 0.314 / 57 (holds 110k vs 80k: FZ_EARLY's earlier passes are more often the urgent set at a commit); fz21e0b (FZ_EARLY=0) 3.09 / 0.373 / 29, its parity.lua one-late 409 of 13,256 (3.1%). FZ_EARLY buys ~5.5 points of on-time sets for ~0.35 points of lost logic (the arcade loses 6.6%); the hold policy (SCH_EXTB_MAX 2, fz_urgent) is the knob left.

## 25. Game-side cuts C1-C3: analysis only (2026-10-18)
Per vblank frame from the ov10 profile (the game code is the same in every build; `work/play/fp/ov10/frames.npz`, frames >= 450): dense frames (>= 45 objects, n = 35k): game + gx 59.1k = coll 12.3k (p90 22.5k) + objgen 10.3k (p90 19.9k) + math 3.6k + main 5.4k + gx_col 8.0k (p90 19.8k) + gx_upd 4.9k + the rest; medium frames (20-44, n = 124k): coll 12.8k, objgen 9.9k, math 3.4k, gx_col 12.1k, gx_upd 6.7k. Per call (catalog): obj_calc_hitbox 0x29ee6 308 cycles (2.12M calls), hitbox_overlap_clip 0x2a1f6 107 (3.97M), collide_obj_hits_player 0x29fbc 168 (1.10M), obj_move_dir_speed 0x2b940 106 (2.55M), obj_in_rect 0x2b2d4 12 (2.67M).
- **C1 collision**: the shot handlers scan the enemy slots (gx_col, the HAL's 8-slot scanner, ~1.6k per scan) and call hitbox_overlap_clip on every candidate (b0 & 0x31 = 1). A rebuilt-per-frame x-bucket index is NOT exact: membership follows the slot's state byte (written at ~100 activation sites, see section 24's note on hooks) and the hitbox RAM as it is at the test (a fresh slot may be tested with its previous occupant's hitbox); an index must mirror both. What is exact: gx_col doing the overlap's own x-range compare (~20 cycles) before the 107-cycle call, since the overlap test is a pure function of the two hitboxes and the scan's end state is already reproduced. Saves ~3-5k per dense frame (the AUDIT's earlier -10..20k assumed the index). Batching the scans (D1) reorders the hits: rejected before (RAM-equivalence).
- **C2 hitbox cache**: obj_calc_hitbox recomputes from position + the type's table every call; a per-slot cache keyed on (y, x, table entry) skips the recompute for objects that did not move (ground structures, items, parked bosses): ~60 instead of 308 when it hits. Exact if the routine has no other side effect than the hitbox fields (to verify: flags/registers its callers use). -2..3k per dense frame (30% stationary).
- **C3 velocity tables**: obj_move_dir_speed multiplies speed x direction (mulu ~70 of its 106 cycles); the speeds come from a small set, so a per-speed premultiplied table (built at boot into work RAM from the same direction table, bit-exact with the mulu + shifts) replaces the multiply: ~40 per call, ~35 calls per dense frame: -2.3k.
- Total -8..10k per dense frame (~5% of the frame), all three with the GX_MISS / RAM-equivalence harness. Not implemented (the user's instruction).

### C1 and C3 implemented (2026-10-18; user: "make the game side logic tweaks where exact, do not pursue the x-bucket index")
- **C1 `GX_XPRE`** (hal/gx.s 4, in gx_col's candidate path): the overlap test's own sixteen x instructions first, with the same registers; no x overlap -> on at 0x2a1a0 exactly as the failed test leaves things (d0/d1/d3 as it sets them, C clear as its exit `andi #$fffe,sr` at 0x2b8ba leaves it, X untouched by either); else into the test's y block at 0x2a22c with the return address 0x2a19c pushed as its bsr would. The twin scan (gx_col2, 4 calls a playthrough) is left alone.
- **C3 `GX_VEL`** (hal/gx.s 5): jmp gx_vel at 0x2b950 (its `tst.w d0; beq`). The game's speeds are a small set (69 distinct |speeds| over a 6k-frame playthrough and the attract, `gxhist.lua`; 7, 10, 36, 48, 4, 8, 20 ... up to 288), so the table is sparse: a byte per |speed| 0..367 (its slot, $ff none) then 54 slots x 32 directions x (dy, dx) longs = 14,192 bytes at `GXV_AT` 0xdc800 (the 14 KB free below 0xe0000; the tool writes it after every other table and asserts the room is still free). A negative speed negates the two products (muls of the negated multiplier: exact); a |speed| outside the map takes the original's lookup and muls at 0x2b956. Out as the original: d0 kept, d1 = (dir & $1f) << 2 with its lsl the last X-setting op, d2/d3 the products, a2 = 0x2b976, N/Z of d3 (`tst.l`), V/C clear.
- **Verification**: `AEROFGT_GXCHECK=1` (GX_VERIFY) runs the original beside each: a failed pre-test calls the whole overlap test and counts a C set in HAL_GX_MISS; gx_vel calls the original's muls path and counts a differing product (GXV_MISS), the speeds outside the map (GXV_OUT) and the largest seen (GXV_BIG), plus the |speed| histogram (GXV_HIST, sprite RAM past the records); `gxcheck.lua` / `gxhist.lua` read them. Attract 4,000 frames: XPRE 0 misses, VEL 26,399 calls, 0 misses, 20 outside the map. The built table is checked entry by entry against the ROM's direction table (scratchpad tabchk.lua): 0 bad.
- **C2 not done**: an exact cache must also validate the stored hitbox words (the slot's init clears them, other code may write them), which costs about what the recompute saves at the likely hit rate (moving objects dominate dense frames), and needs ~1.6 KB of HAL RAM that is not free.
- **Measured (profiles fz24p vs fz25p, frames 2701-7700, the game's own categories; routes differ so +-1k is noise)**: coll 17.0k -> 12.2k a frame on average, 20.8k -> 12.1k in dense frames (>= 45 objects); the pre-test's own cost (66-134 cycles a candidate, ~100 on average) lands on the HAL side, so C1's net is ~45 cycles a candidate: ~1.5k a frame on average, ~2.7k dense. math 4.2k -> 1.7k BUT gx_vel's path costs ~268 cycles a call against the original's ~174 (its two muls.w are 43 cycles each with the game's small multipliers - the catalog's 102.6M cycles over 2.38M muls; the section's "mulu ~70" premise was wrong): **C3 is a net loss of ~90 cycles a call and stays off** (`GX_VEL` 0; the code, the table generator and the self-check are kept for the record). The candidate build is `AEROFGT_DEFS="FUSED=1,GX_XPRE=1"` (work/out_fz26, attract 4,000 frames clean), not deployed.
- Lessons: a MAME write tap over the whole object area (0x101000-0x1070bf) that reads CPU state crashes MAME (segfault, even split in three) - measure such things inside the build (GX_VERIFY counters) instead; `beq.w` to a game address is out of reach (jmp); an indexed displacement is 8-bit.

## 26. Where things stand: fz26 against the arcade (2026-10-18)
Build `work/out_fz26` = `AEROFGT_DEFS="FUSED=1,GX_XPRE=1"` (p1 5a1b3f6a), deployed on the MiSTer. The same nine bot movies (seeds 7-15, 60,000 frames each) on the original arcade game in MAME (`work/play/fp/benchlag_orig.sh` -> `lag_orig.lua`), on fz26 and on ov10 (its older 200k battery). Routes still diverge per build after the first minutes, so the per-stage rates are the comparison, the totals only roughly.

**Logic slowdown (lost vblanks = game frames the logic did not keep up with)**

| stage | arcade | fz26 | fz26 FZ_EARLY=0 (fz24e0b) | ov10 |
|---|---|---|---|---|
| all | 5.76% | 7.08% | 3.97% | 21.2% |
| bases/attract | 3.1 | 3.5 | 1.7 | 16.6 |
| coast/river | 7.9 | 7.9 | 5.5 | 24.2 |
| cities | 6.4 | 5.3 | 3.3 | 22.6 |
| desert | 8.9 | 13.6 | 5.0 | 32.0 |
| ocean | 5.9 | 10.1 | 6.2 | 33.0 |
| runway | 13.7 | 16.9 | 9.6 | 26.7 |

fz26 is at the arcade's rate in the first three stages and 4-5 points worse in the dense later ones; with the early-due rule off it is below the arcade everywhere but ocean, at the price of late sets (next table). The game-side pre-test (C1, ~1.5-2.7k a frame) does not move these rates (fz24b 7.07% -> fz26b 7.08%): the HAL's holds dominate (230k holds per 536k frames).

**Sprites: delayed, dropped, overrun (20k-frame runs, fz26)**
- Delayed: `parity.lua` (the set shown at each flip against the slot the arcade shows that round's list in): on time 12,158, one frame late 342 (2.7%), two late 23; `fztl.py` on the event log (a slightly different route): on time 92.8%, one late 6.2%, two late 0.5%, never shown 0.6% (a late set superseded by the next on-time one). fz24 with FZ_EARLY=0: one late 10.2%. ov10: 3.1% (in its own numbering).
- Dropped (a set out of ring columns, sprites left out of one frame): 210 frames of 20,000 (1.05%) in the fz26 run, 954 drop events, every one with a split set in the ring (the 338-column capacity: a split shown set fragments the free columns, section 24); the battery 1.87% of frames (fz24e0b 1.14%, ov10 0.10% - ov10's lists were sparser because its game ran 21% slower and its walk shed the rest). The remaining lever is load shedding (which sprites to leave out) or fewer columns per set; not done.
- Overruns (the commit running past its deadline): 6 per 20,000 frames (fz14: 1,188), 56 per 536k in the battery; the two large ones are commits that start 40+ lines late when the game masks interrupts.
- Tail budget: the pass's charges are now 9.8% over the actual cost (conservative; refill segments 4.4% under on average, +-1 line).

**Exactness**: entries identical to ov10's walk for rounds 1-297 of the by-round harness; the game-side pre-test 0 disagreements over 20k + 4k frames (GX_VERIFY); the attract clean for 12,000 frames (no reboots - every FUSED build before fz24 rebooted at its first scene).

**Profile (fz26p: frames 2701-12699, 10k frames traced, map_fz26.txt; `work/play/fp/fz26p/report.txt`)**. Per frame, means (a real frame is 202,750 cycles): game logic 52.6k + gx 23.5k (the HAL's object/collision loops and the record builder's slot scans) = 76.1k; the records pass: walk_emit 14.7k (fz_em: clip, four words) + walk_ctl 14.5k (fz_ntab) + conv 11.9k (shape routines, 205 cycles a column) + spr_ctl 7.5k + flip 2.5k + reclaim 1.8k; the builder fz_rec (walk_scan) 23.8k in game time; tilemaps 9.3k, palettes 5.5k, fixed 10.4k, scrub 19.2k (filler only). Dense frames (>= 45 objects, 12.7%): game 80.9k, HAL 117.8k, the pass 72k + 15.6k conversion; 29.5% of them are "late" (lag2's late: the flip had nothing new). Late-frame tags: pass > 60k in 75% of them, demand over the frame 56%, post-commit hold 60%, conversion carried 71%; cutting 10k a frame would fit 86% of the late frames into three real frames, 20k 93%. Sparse frames (<= 6 objects) still cost the HAL 85.5k against the game's 14.9k: sched 7.2k, vid 6.7k, tcheck 9.1k, spr_ctl 7.4k, walk_ctl 5.5k, walk_scan 12.4k (the builder's slot scans), bg_conv 3.4k, pal 2.7k, flip 2.3k - the fixed bookkeeping of section 23 item 3 is still there. Drop frames in this window 9 of 10k (58 objects, 125 columns; enemy bullets 16.9, explosions 15.7, ground 10.3 of them on average). Timer-started slots (the game busy at line 226) 31%; frames with filler (the HAL not saturated) 47.6%.

**Where the time goes, in order**: (1) the pass's per-piece path (fz_em + fz_ntab + shape ~41k a frame, 72k dense) - section 24's piece descriptors and the HUD fast path are the remaining structural cuts; (2) the record builder in game time (23.8k a frame; ~700 a record); (3) the fixed HAL bookkeeping (~45k in sparse frames); (4) the game's collision/objgen (coll 10.3k, objgen 11.2k, both exact-only now); (5) holds: the policy knob (FZ_EARLY on: 7.1% lost logic, 2.7% late sets; off: 4.0% / 10.2%).

## 27. Piece descriptors and the HUD fast path (2026-10-18, fz27/fz28)
**Piece descriptors (`FZ_PD`, hal/fz.s FZPD, tools/aerofgt2neo.py fz_pd_prepare)**. The game's handlers read only the first word of a piece entry (the end-of-animation sentinels $ffff/$fffe and a sign test) and the link after a $fffe entry; the other 12 bytes were the sprite-list builder's, which DIRECT builds replace. So the catalogue's 1,735 piece entries (1,130 tables, work/catalog/sprites/objects.json; the 9 sentinel entries it lists are skipped) are rewritten in place as descriptors: +0 the pointer's high word | $0100 (the first byte's bit 0 is the flag; still positive, no sentinel), +2 the map (bit 15: in the HUD's lookup range), +4/+6 y/x as before, +8 (header byte 0 | zoomy << 4) << 8 | byte 0, +10 the same of byte 1 and zoomx, +12 the colour nibble | the flips as FZEM composes them, +13 the HUD slot. fz_rec picks the routine table by the table's first byte (fz_emt for tables not in the catalogue - exact either way - fz_pdt, fz_pdht for HUD pieces); fz_anch and fz_bul's general way follow the flag. The 16 FZPD routines produce the same four words with no header read, no per-piece zoom/colour/flip composition and no map range tests; fz_disp's index stays (shared with the old path). Measured on the event log (fz26c -> fz27c): 1-piece shape records 1,413 -> 1,288 cycles, 2-piece 2,870 -> 2,543, HUD records 1,666 -> 1,516 and 3,193 -> 2,840.

**HUD fast path (FZPD \5, fz_pdh_*)**. A per-slot cache in the sprite RAM's free end (FZ_HKEY at G_SPRRAM+$1d20: per HUD slot the key of the record whose piece last took it - y, x, w2, zoom, table, the lookup RAM's generation FZ_LUTGEN, bumped by fz_lutld hooked at the game's loader 0x2bbca; FZ_HCOK: slots fx_hud_draw left shown). A HUD piece whose slot is not taken this walk, is shown and holds its record's key is exactly what fx_hud_take would find unchanged: marked seen and same, the take skipped. fz_hud stores the key after every take (and clears the slot's shown bit until the draw confirms). Hit rate 99.6% (10,790 of 10,837 HUD pieces in 2,500 frames). HUD records now 681 (1 piece) / 1,335 (2) cycles. A first version collided with hal/tm.s's TM_DIRTY at G_SPRRAM+$400 (the free-RAM note in fz.s was wrong): keys erased, tilemap marks corrupted; moved.

**A cache hit costs ~450 cycles** (two dozen absolute-address accesses), not the ~170 estimated; charged only the record's FZU_PIECE it ran dense tails 1-2 lines past the deadline (overruns 17,844 per 536k frames, every one a tail ending 1-3 lines late). The hit path now charges FZU_HHIT 24 units with the usual refill-or-stop (`.hnt`: this piece again), and fx_hud_draw counts its added cycles in the units it returns: overruns 8 per 20k frames again, the tails ending at or before the deadline.

**Deployed 2026-10-18 (p1 4ddbe519)**: the first deployment (8a14793f) lost the 1P label and score after a game start on the MiSTer: fx_hreset clears every strip's cells when the HUD's work-RAM state loses its magic (the game's RAM clear at a game start), but the cache's shown bits (sprite RAM) survived, so the take was skipped for strips that no longer existed and constant strips were never redrawn; MAME never showed it because the bot coins before the attract. fx_hreset now clears FZ_HCOK; a late-coin movie (work/play/latecoin.txt: the attract first, the bot's inputs from frame 2500) shows the score strips at 95% of flips after the start; the device shows the full HUD in coined play (work/mister_fz28d).

**Second device-only defect (user: "still does not show the HUD when you first start the game, but it comes in later after dying")**: MAME never reproduced it, coin during the demo included, because every MAME run starts with fresh backup RAM. The MiSTer keeps the backup RAM (the sprite RAM with the cache) across sessions and the boot RAM test leaves FX_MAGIC intact there, so the previous session's keys and shown bits survived while the game cleared the strips' own RAM at boot: the take was skipped for strips never drawn this session until the HUD objects changed (the lives after a death). Fix (p1 ecd33910, deployed): a cache hit now also tests the strip's cells (FXH_COL+4, fx_hud_take's own test), so the shown bit can never outlive the strip, and hal_video_init clears FZ_HCOK at boot; FZU_HHIT 28. Verified across a session boundary on the device (play, reboot, reload, coin during the demo: the full HUD in the first seconds of play, work/mister_fz28g) and in MAME (entries = ov10 rounds 1-297, attract clean, coin-during-demo movie work/play/latecoin2.txt: the score strips at 306 of 309 flips after the start).

**Exactness** (final fz28, p1 ecd33910): entries identical to ov10 for rounds 1-301 (by-round harness, fz28g); the shown HUD strips (FX_HSHD, every slot, logged at every flip by `hudlog.lua`) identical between the cache-less fz27g and fz28g for every logged round; attract 12,000 frames clean. **Numbers**: record cycles per pass 52.9k (fz26) -> 42.0k (fz27) -> 39.1k (fz28) at ~31 records; parity.lua 20k: one late 342 (fz26, 2.7%) / 167 (fz28, 1.2%); fztl on time 98.0%, never shown 0.6%. Battery (9 x 60k): fz28b lost logic **4.72%** (fz26b 7.08%, the arcade 5.76% on the same routes), drop frames 1.44% (1.87%), overruns 90 (56), holds 215k (231k); by stage: bases 2.9 (arcade 3.1), coast/river 5.6 (7.9), cities 4.3 (6.4), desert 11.6 (8.9), ocean 9.1 (5.9). Not deployed (fz26 on the MiSTer).

**Third device defect, the real one (user: "The build on the MiSTer still isn't showing the HUD"; fz28 ecd33910)**. Reproduced to order on the device with a scripted flow (work/mister_*_chk7: load, 100 s of attract, coin, coin, start at the title; after the game over the same again for a second game; screenshots at 20/26/32 s): fz26 (no cache) shows the HUD in both games, fz28 shows CREDIT and PRESS 2P (the fixed-table strips, slots 8-12) and none of the 1P label, score, bombs and lives (the lookup-RAM strips, slots 0-7). MAME reproduces it with the same two-game flow (work/play/twogames.txt; the snapshot at real frame 6000: fz28's game-over screen without a HUD, the fixed build's with 1P 200 / 2P 00 / bombs / lives). hudlog.lua could never see it: it logs the shadow's header (words, column, cells count), not the cells, and the cache skips the draw that would change them.

**Cause**: the key's lookup generation FZ_LUTGEN was bumped at the bulk loader (0x2bbca) only. The game writes the HUD's entries straight: player_hud_refresh 0x192be, when the player's HUD-dirty bit is set (score, bomb and life changes), runs 0x2a63e (bombs), 0x2a676 (lives) and 0x2a6c4 (score digits) into entries 0x3fc0-0x3fff - the only writers of that range in play (write tap by PC, work/play/fh/lutw.lua, lutw2.lua: the others, 0x4aa, the loader's copy loop and the HAL's takeover, at boot only). A strip drawn before its refresh (blank entries at a game's start) kept its key, so every later pass hit the blank strip until the key changed (a death: the lives table). On the MiSTer the game's first refresh lands after the HAL's first take (its timing model); in MAME's usual flows before - and when the score changed in play the same stale hit froze it there too.

**Fix (fz29 -> fz30, p1 58f7397a, deployed)**: `fz_hudrf` hooked at 0x192c6 (the refresh's first jsr: addq FZ_LUTGEN, jmp $2a63e; tools/aerofgt2neo.py next to the loader hook). fz29 alone then wrecked the cache's cost: the key store cleared the slot's shown bit after every take, and a slot the refresh rewrote alike (lives, bombs) is found unchanged by the take - no draw ever set the bit again, so the slot left the cache for good: overruns 1,806 per battery (fz28b 90), lost logic 5.50%. fz30: the key store sets the shown bit when the take found the strip unchanged (fx_hud_take verified cells, words and entries), and FZU_HUDT 118 under the cache (the failed prologue, ~450 cycles, before the take). Hit rate 85-96% per 1,000 frames (FZ_DIAG counters: work/play/fh/hccnt.lua), 15-186 lookup generations per 1,000 frames (the refreshes). A switch `FZ_HC` (default 1) builds the descriptors without the cache (fz30h) for the A/B.

**Verification**: ground truth in MAME (work/play/fh/hudlog3.lua: the live lookup entries of the 1P score strip against slot 0's shadow copy at every flip): the cache-less fz27g and fz30 differ from the live entries at 39-40 flips of ~5,400 shown, the longest run 2 flips (the update's lag), alike; attract 12,000 frames clean; the device's scripted flow with fz29 and fz30: the full HUD in the first game, at the game over (1P 500 / 2P 00) and in the second game (work/mister_fz29_chk7, work/mister_fz30_chk7). Exactness: the records are untouched (the hook is one jsr in the game's refresh); FZ_PD=0 builds byte-identical to fz26, the DIRECT default to ov10, the exact build unchanged.

**Numbers** (battery 9 x 60k; the lag.txt totals are in bench_<name>.txt): fz30 lost logic **5.40%**, late 14.88%, drop frames 1.80%, overruns 449; fz28b 4.72% / 14.00% / 1.44% / 90 - flattered: it never redrew the HUD; fz29 5.50% / 15.84% / 1.66% / 1,806; fz26b 7.08% / 17.48% / 1.87% / 56; the arcade 5.76%; **fz30h (FZ_HC=0: the descriptors without the cache) 6.08% / 16.52% / 1.91% / 138** - the cache is worth 0.7 points of lost logic and 1.6 of late sets at three times the overruns (449 against 138 per 540k frames, each a commit tail 1-3 lines past its deadline); kept on. Event log 20k (fzev + fzcost, ovctx.py): overruns fz30c 24, fz29c 77, fz28c 8, fz27c 10 (single-run routes differ: the battery is the comparison); the two-piece HUD records (tables 0x50f7a, 0x50fa4: 27k of the 29k) 1,822 cycles mean = two hits, 10% at >= 3,900 = the refresh frames' two takes.

**Lessons**: a cache keyed on a proxy for content needs every writer of that content hooked - tap the range by PC in play before trusting a hook; comparing shadows between builds cannot show stale content when the cache skips the draw that would update the shadow: compare against the live source; the device's timing model reorders the game's writes and the HAL's passes within a frame, so a MAME flow proves nothing about order-dependent state - script the device flow and look at the screen.

**Overruns on refresh frames (user: "Look into the overruns on refresh frames"; fz31-fz33)**. fzev.lua now logs FZ_LUTGEN writes (`U`); work/play/fh/ovctx2.py ties each overrun to the pass before it: 22 of fz30's 24 overruns per 20k frames follow a refresh (22% of passes do). The tail of such a pass began with the four HUD records (0x50f7a, 0x50f6c, 0x50fa4, 0x50f96), every piece a miss: the key's generation had moved, so each went the full take (~2,000 cycles) only to find the lives and bombs strips unchanged - 10k cycles of HUD records in a tail of 11 lines, and the stop landed 2-3 lines past the deadline. Three changes: (1) the cache check is charged first (FZU_HHIT before the prologue, hit or not; FZU_HUDT back to 90 on top of it), so a stop lands before the work; (2) on a generation mismatch alone the prologue compares the strip's live entries with the shadow's copy (fx_hud_take's own compare, ~250 cycles, charged FZU_HLUT 20) and renews the key on a match - a wrong index at first (the descriptor's map lacks bit 13, which the dispatch ORs into w3: the compare read another sprite's entries and never matched; found with the FZ_DIAG exit counters FZ_HX and hcdiff.lua); fixed, hits 85-96% -> 99.1% of HUD pieces (1,099 renewals, 64 real changes per 4,000 frames), HUD two-piece records 1,822 -> 1,610 cycles mean; (3) the refill's tail margin: SPR_TAIL (68 units, "each sprite is charged an upper bound") assumed the charges bound the way to the next check, but a record's way to its shape's own check is ~900 cycles against 544 charged, so the last refill of a tail (3 lines left -> 38 units) let the pass run two lines past the deadline. `FZ_TAILX` (56 units, FUSED builds only; the DIRECT default stays ov10) adds that way to the margin: tails end at lines 7-9 instead of 9-10.

**Battery** (9 x 60k): fz32 (1+2) lost logic 5.36%, late 14.77%, drop frames 1.58%, overruns 1,145; **fz33 (1+2+3, p1 cf6cc684, deployed)** lost logic **5.16%**, late 15.04%, drop frames 1.67%, overruns **121**; fz30 5.40% / 14.88% / 1.80% / 449; fz28b (stale HUD) 4.72% / 14.00% / 1.44% / 90; the arcade 5.76%. Single-run event logs (seed 7, 20k): overruns fz30 24, fz31 51, fz32 38, fz33 7. Staleness against the live entries unchanged (hudlog3: 40 flips of 5,428, longest run 2); the device's scripted flow shows the HUD with fz32 and fz33 (work/mister_fz32_chk7, work/mister_fz33_chk7). The remaining overruns are the same granularity in the HUD pass (its draws run up to 5 lines over their units, FZ_HUDRES) and dense tails; refresh frames are no longer special.

## 28. Autofire and boss-bomb profile: arcade against conversion (2026-10-18, fz33)
**Method (user: "Run a new profile with auto fire enabled and bombs deployed fully during boss fights...")**. tests/harness.lua takes `HARNESS_BOTFILE`: a Lua bot over the movie's rows (`HARNESS_BOT(game_frame, v)`), the same for both targets. work/play/fp/botfire.lua: the shot pressed every other frame for both players (autofire, 30 Hz edges), the movie's own bomb presses dropped, a bomb press 2 frames in every 24 while an object of one of the 41 boss types (work/catalog/type_handlers.tsv, category bosses) is active in any pool and the player has bombs (+0x1e of the player object); per frame it logs boss state, bombs, active objects (the five pools, 0x60 a slot) and the boss type (bot.txt next to lag.txt). botsum.py: totals overall and in boss fights, lost logic by active-object bins; bfana.py: the per-frame profile (fprof, map_fz33.txt - fmap.py now files the descriptor piece code fz_pd_* as emit) joined with the bot's log. Batteries: 9 seeds x 60k, the conversion fz33 (bl_bf33_*) and the arcade in MAME (bl_bforig_*, lag_orig.lua) on identical inputs; the profile: bfprof (frames 14000-17000 and 20000-23000 of seed 7: the ocean boss, types 0x77/0x78, and the finale orbs 0x91/0x92; 2,371 boss frames). The bot's 24k test run showed the first boss at frame 14,830 (plain movies never spend bombs: the first version scanned the stage pool only and saw no boss; bosses sit in every pool).

**Totals** (535,959 frames each; the boss fights are 30% of them, 163k frames, ~1,300 bomb presses a run):

| | lost logic | boss fights | late sets | drop frames | overruns |
|---|---|---|---|---|---|
| arcade (MAME) | 1.71% | 2.47% | - | - | - |
| conversion fz33 | 2.07% | 2.28% | 8.23% (boss 8.20%) | 1.17% (boss 2.07%) | 136 (boss 59) |

Lost logic by active objects (conversion / arcade): 40-49 2.3 / 1.3%, 50-59 9.7 / 7.7%, 60-69 20.9 / 20.3%, 70-79 33.3 / 35.3%, 80+ 43.6 / 46.5%; in boss fights 50-59 5.3 / 5.2%, 60-69 21.5 / 22.8%, 70-79 34.2 / 36.5%. By stage the conversion loses more in the "other" bucket (5.8% against 3.3%: an unmapped stage hash, 15% of the frames) and less in the cities, runway and desert. Autofire halves the load on average (plain bot: fz33 5.16%, arcade 5.76%): enemies die sooner; the heavy frames are the player's own shots.

**The boss-fight frame** (bfana.py, mean cycles per frame, 200k a frame): game logic 49.1k (objgen 11.1k, collision 10.7k, main 7.5k, math 3.4k, player 3.3k), records (fz_build/fz_rec/fz_group, game time) 26.0k, pass control (fz_ntab/fz_next/fz_disp, hal_spr_*) 24.5k, pass pieces 11.9k, shapes 16.5k, gx (the collision scan) 13.0k, bg+tm+tx 37.8k (63.1k outside the fights: the scroll), palette 3.4k, sched/vid/other 12.6k, HUD 0.9k, bullet pool 1.4k, flip+reclaim 4.4k, idle 1.3k. The frame is full either way; the fights trade background work for objects.

**By load** (slope per active object, cycles): game logic 796 (objgen 296, collision 284, main 104, math 70, enemies 46), records 349, pass control 335, pass pieces 143, shapes 193, gx 219, bullet pool 21; bg -1,778 (the scroll stops). The HAL's sprite path is ~1,020 cycles an object, the game's own ~1,015 with gx. At 60-70 objects: game 60.0k, records 30.5k, control 33.9k, pieces 12.0k, shapes 15.3k, gx 24.4k, bg 6.3k, sched 8.6k: 194k before the flip. The census there: **player shots 24.7**, other 7.9, explosions 5.7, items 4.1, ground 2.9, HUD 2.1, players 2.0, boss 1.8; at 70+ shots 26.7, boss 3.0, explosions 5.9, items 6.6. The heavy frames are shot frames: every shot is an object through the full round trip (record, set-up, piece, shape) and through the game's and gx's collision scan.

**Correction (2026-10-18, section 30): the bot's autofire never fired a main shot.** The game counts a button once it is held two consecutive frames (0xde2: the raw input ANDed with the previous frame's) and fires on that held value's edge, then while held (0x18718, the auto-fire counter +0x2f); botfire.lua pressed the shot on even frames only, so the debounce never saw it, while the movie's own shot presses were stripped. The "autofire" batteries above therefore played with NO main shots (the "player shots" census counted the items of type $0f and the hit sparks), which is why their load was half the plain bot's; the comparison between the arcade and the conversion on those inputs stands, the "heavy frames are shot frames" reading does not. botfire.lua and botsel.lua now hold the shot three frames in four.

**Options for the heavy frames, in order of expected yield**
1. **Player shots as a homogeneous batch** (exact; HAL side). The shots are one table, one piece, unzoomed, unflipped: a shot-specific record (the builder has y/x; the four words precomputed at build time) and a pass routine that skips fz_ntab's generic set-up and the piece code, dispatching straight to the shape: ~400 of the ~1,020 cycles a shot; 25 shots in a heavy frame -> ~10k cycles (5% of the frame) exactly where the frames are lost. The bullet pool (pair bullets) is the precedent. Shots must keep their order among the entries (the same entries as ov10: the by-round check).
2. **Charges from measured costs** (HAL side). The records are charged 15% over their actual cost (fzcost: fz_pd_0011 0.81, 0110 0.85, 0111 0.81, 0010 0.86) so tails stop with credit unused; with FZ_TAILX covering the way to a shape's check, per-routine charges from the measured ratios would let tails finish ~15% more records before a stop: fewer slot runs a pass (1.8-2.0 now), fewer late sets (8.2% here, 15% on the plain bot). Measure overruns after.
3. **gx's scan** (exact; game side): 219 cycles an object, 24k a frame at 60+ objects, scaling with shots x enemies. The x-bucket index is off the table (user); the remaining exact cut is section 25's C2 (the scan's loop order and early outs), not yet done.
4. **The game's objgen/collision** (580 an object): the arcade pays the same; exact rewrites only (C1 is in, C3 measured as a loss). Nothing cheap left there.
5. **Drop frames in the fights** (2.07%, the ring's 338-column floor, section 23): a boss plus 25 shots exceeds the columns; a priority order for shedding (shadows, items last shown) is the only lever and is not exact - measure first what is dropped in the fights (dropwhy.lua on bl_bf33_7).
6. **Late sets** (8.2%): the FZ_EARLY policy knob and the slot time (PHASE_LINE) - unchanged by load; not boss-specific.
7. Not a heavy-load cost: the background path (77k in light frames, 6k at 60+ objects), the palette, the HUD (0.9k, the cache).

## 29. Fast records, the hoisted collision scan, and the charges measured (2026-10-18, fz35-fz40)
**User: "Implement the shot-specific batch records where exact, charges from measured costs, then the collision scan's loop order and early outs"** (section 28's options 1-3).

**Fast records (`FZ_FAST`, default on with FZ_PD; hal/fz.s fz_rec, fz_ntab, fz_fast, fz_anch).** Not shots only: any object whose record would be one C table of one unzoomed piece of a descriptor table that is not a HUD strip and, in pass 1, not in the HUD's lookup range (the take) gets a fast record - 73% of all records in the tails of a 20k-frame playthrough (52,346 of 71,700, fzcost). The builder composes what the piece routine and fz_disp would: +0 the shape's own routine (spr_fast_jt's entry by (w2 bits 13-15) << 6 | ysize << 3 | xsize, the zoomed table for a zoomed piece, the front routine for an entry behind tilemap 1), +4/+6 y and x with the piece's offsets, +8 w2 (the piece's colour nibble and flips masked as the FZPD flags say, bit 5, pass 1's $1000), +10 w3 (map & $3fff, | $2000 in pass 1), +12 the charge, +13 $ff (the flag: a w2 byte is at most $ef), +14/+15 the descriptors' header bytes (w0/w1's high bytes). fz_ntab tests the flag after its charge (16 cycles on the general path) and fz_fast does the screen tests, the two adds, spr_lo's part for an entry behind tilemap 1 (SS_PRIO, LO_UNITS) and the dispatch, with no FZ_W2/FZ_Y/FZ_ZOOM/FZ_LEFT set-up, no piece routine and no index computation; a budget stop in the shape routine steps back onto the record (a5 = the record, a0 = fz_fast_rd, FZ_LEFT 0). fz_anch takes the xsize from +15. Per single-piece record in the tails: 1,267 cycles (fz33c) -> 958 (fz35c, the shape routine included). The charge FZU_FAST 15 is given back at the dispatch with FZU_FASTX more (the shape routine's charge keeps PRE_MAX ~620 cycles for the general way; the fast way is ~500 at most).

**The collision scan (`GX_SCAN`, DEFS switch like GX_XPRE; hal/gx.s 6, jmp at 0x2a142).** shot_collide's three pool scans from one routine: the overlap test's x block compares the candidate's x range against the shot's AND the playfield's bounds (0x50858's table) - max/min once a call, two compares a candidate instead of four with their loads; the second hitbox (76(a2), 0x2a26a) the same way; and a slot that is active but no target ((b0 & $31) != 1: every enemy bullet) costs the original's six instructions, not gx_col's eight-slot round trip (82 cycles against 52 - gx_col was slower than the original on active slots, and a storm's pools are full of active bullets). The registers a failed x block leaves (d1, d3) are set as the original's, d0 is dead, X is the last slot's subq (0x2a1b8's own code ends the scan, 0x2a1c0's own code the hit); d4-d6 saved on the game's stack. Exact: GX_VERIFY (gxsv84/92: the original test after every failed cheap test, C or d1/d3 unlike its counted) 0 misses over the attract 4,000 + a 20k-frame playthrough; the entries per logic round identical to ov10's (by-round harness, rounds 8-297: 275 identical, 10 by the map word only, 5 absent on one side = rounds whose buffer was dropped) for the fast records (fz35r) and with the scan (fz36r) alike.

**The defect of fz35-fz39 (found on the device, confirmed in MAME).** The fast record stored spr_fast_jt's entry as its routine; for an entry behind tilemap 1 (w2 bit 13 clear) that entry is spr_lo_v/z, which flags the set and re-dispatches through d1 = the table offset - which the fast path never set (d1 held the charge word): a jump through garbage, an address error, the game rebooting into its memory check (the lag batteries of fz35-fz38 ran through reboots: their stage-hash sequences return to the boot's, their lost-logic figures - 2.7-3.8% - are void; the by-round entries check saw nothing because FZ_DW is written before the dispatch). On the MiSTer: fz36's scripted trial happened to pass, fz39's showed garbage text sprites over the game-over, pilot-select and second game's screens (work/mister_fz39_chk7); in MAME the two-game movie shows fz36 and fz39 rebooted before real frame 4500 (the memory check under garbage) while fz40 reaches the second game. Fixed in fz40: the builder stores the front shape's routine (offset | $100) and fz_fast does spr_lo's part when w2 bit 13 is clear.

**Battery (9 x 60k, plain bot; no reboots in any seed - the boot's stage hash in rows 1-40 only):**

| | lost logic | late sets | drop frames | overruns |
|---|---|---|---|---|
| fz33 (deployed before) | 5.16% | 15.04% | 1.669% | 121 |
| **fz40** = fz33 + FZ_FAST + GX_SCAN + FZU_FASTX 6 | **4.32%** | 12.78% | 1.500% | 3 |

(The arcade on the same movies: 5.76%.) fz35-fz38's figures (3.77 / 3.11 / 2.94 / 2.73-2.99 / 2.79%) are not comparable (reboots); the charge experiments below were run on them, so their overrun counts stand only relative to each other.

**Charges against measured costs (fzcost, 20k frames, the tails).** fz33c: single-piece records charged 1,523 for 1,267 actual (0.83), fz_pd_0011 0.82, 0110 0.85. fz35c (fast records): fz_fast 0.90 (958/1,064), fz_pd_0110 0.93, 0011 0.92, 1110 0.94, 0010 1.04, the HUD cache paths fz_pdh_001 1.08 / 011 1.04; refill segments 7.7% over their consumed credit (the partial record before each failing check is in the actual, not in the consumed). So the 15% slack of section 28 is 10% now, and FZU_TAB 26 / FZU_PIECE 8 / FZU_FAST 15 are the measured costs within that. Lowering them (fz37: FZU_TAB 18 and 12 more units given back at a fast dispatch) made the records under-charged (fast 1.10, pdh 1.17, segments 21% over, 1-3 lines) and the tails stop 1-2 lines later than FZ_TAILX covers: 1,093 overruns a battery against 12. Each alone: FZU_FASTX 12 -> 172 overruns, FZU_TAB 18 -> 18; FZU_FASTX 6 (the fast records' measured slack: 0.90 of 1,064 cycles = 106 = ~6 units) -> 18, FZU_FASTX 8 -> 18. **FZU_FASTX 6 is the default** (all four charges are `ifnd`-overridable in hal/fz.s); with the reboot-free fz40 the overruns are 3 a battery.

**Device**: fz40 deployed to the MiSTer (p1 md5 ca27839f; backups 538-p1.p1.fz33_cf6cc684, .fz36_1275f51d) and put through the scripted trial (/tmp/chk7.sh: two coined games): HUD strips, pilot select and play as fz33's (work/mister_fz40_chk7).

**Lessons**: a routine taken from a jump table may be a stub with its own register contract (spr_lo's d1) - check every table entry's expectations before dispatching through a stored address; a picture check (snapshots of a fixed movie, pixel-compared between builds) belongs beside the entries check and the lag battery, since neither sees a reboot; a kill pattern's target text anywhere else in the same command line defeats the bracket trick (the shell killed itself again: kill by PIDs listed beforehand); the shape routines' PRE_MAX covers a way the fast records do not walk, which is where the measured slack sits.

## 30. Fresh audit of fz40: every nation, autofire that fires, the ring's drops, the full game (2026-10-18/19)
**User: "Do another fresh audit with fz40 and don't only run playthroughs for Keaton but all characters. See if there is a way to optimize handling for each ship's shot type. Also, review the ring capacity and see if it can be increased or reworked to avoid drop frames and overruns. Profile the full game from start to finish and see if there are still any areas where the conversion loses logic frames over the original arcade behavior. For each playthrough use autofire and bomb through bosses."**

**The pilots and the bot (work/play/fp/botsel.lua).** The pilot-select handler (0x8e6c) keeps one cursor (0-3, a nation) for both players and stores it at 0xffc000 every frame it runs: P1 gets the nation's first pilot, P2 its second, so the two-player movies (a coin at 100 and 120, both starts at 150 and 170, then a coin and both starts every 600 frames for the continues: 334 credits over 200k frames) cover all eight pilots in four runs. The bot taps the store (0x10d000 in the conversion), replaces the movie's inputs while the screen is up, presses right until the cursor is `NATION`, then the button, and logs per frame the stage index (0xffc110) and id (0xffc100[index - 1]), the pilot, lives, the active objects and the shot-type counts. **Every earlier "autofire" run never fired a main shot**: the game counts a button once held two consecutive frames (0xde2) and fires on that value's edge then while held (0x18718); a press on even frames only is invisible to it (the inputs of the random movies change every two frames, which is why they fire). The bot now holds the shot three frames in four (section 28 corrected in place). The stage ids: 0 night fleet (the hash the earlier summaries filed as "other"), 1 cities, 2 coast/river, 3 bases, 4 desert, 5 ocean, 6 runway, 7 final; each nation's home stage is zeroed in the order table (0x9468) and played last.

**Per-nation shot types** (botsel's census, seed 7, play frames; per frame on average / in frames with 60+ objects): nation 0: types $11 1.9 + $12 1.7 (P1 twin, P2 levels), 8.7 shot-class objects (10.4); nation 1: $11 1.7, $17 (homing) 0.3, 9.5 (12.0); nation 2: $11 2.1, $12 1.5, $16 (sparks) 0.2, 8.9 (10.2); nation 3: $11 1.6, $18 (blasts) 1.2 - **12.0 a frame at 60+ objects**, 8.4 (8.8). Every shot object is one unzoomed piece of a C table (objects.json: $11/$12 32x16, 48x48, 32x32, 48x64 by level; $17 16x16; $16 32x16; $0e sparks 16x16) - all on the fast record path already; the $18 blasts are the pair-bullet pool's (two pieces of one of four tables, 2 columns a bullet through bp_apply, no record pass at all) when the pool is on, else one entry (fz_bul). On the game's side a shot's cost is its handler plus shot_collide (0x2a142, ~6.4k a call in the arcade's own profile: three pool scans, now GX_SCAN's) every frame: identical for every ship but for the homing missile's angle (0x2b9f6) and the sparks' every-frame hit test.

**The ring: why the fights drop, and the rework (`FZ_SPLANCH`, fz42).** work/play/fh/dropwhy2.lua logs at every drop the sets' states, START/END/HNEXT/HMIN, the split (HAL_SPR_SPS/SPJ/SPG), HAL_SPR_PREV, the heads, and the columns the records left would still take. Over the boss window of seed 7 (frames 0-17000, botfire): fz40 drops 1,150 sprites in 184 frames, every one of them with a SPLIT shown set and two live sets, the set in work out of room with a median of 5 columns still needed - and ~110 columns free at the ring's bottom. The geometry: a set that began at the top and ran into the live set below it continues its lower run at HAL_SPR_BEGG, the column below the previous set's end as of its begin (hal_spr_go .spl); the non-fused builds' spr_split_anch moved that run down to SPR_PB + its own size, but it reads list entries and was left out under FUSED. So the lower run sat mid-ring (e.g. 153..163), the next set went into the hole above it (164..276) and ran out, while 43..152 lay stranded below the lower run. On top of that HAL_SPR_PREV ("the columns the last complete set took", hal_spr_where's estimate of the next set's room) was START - END for a split set - the hole included (228 for a set of 57 heads, ~115 columns), so every placement after a split was sized for twice the set. fz42 adds fz_split_anch (hal/fz.s: the records from the one in work, up to SPLN, their pieces' columns unclipped as fz_anch counts them, + 4; the lower run starts at the lower of BEGG and SPR_PB + that, its column's SCB3 cleared as the non-fused code does) and the split correction of PREV (START - HNEXT - (SPJ - SPG)); `FZ_SPLANCH=0` is fz40 byte for byte. Same window, same inputs: **13 drops in 2 frames** (the median shown set 48 columns, one split sample in 331). Content unchanged: the sets' flip hashes by logic round (fliphash4 / fhround) match fz40's for 251 of 257 sets in the intro window (rounds 0-300, where the scroll is static; later rounds are not comparable by this hash, as before); the two-game movie's snapshots clean (work/play/fh/tg_fz42).

**The ring's capacity itself.** 43..380 = 338 columns, 274 while the bullet pool holds the top 64; three sets in flight (shown, complete, in work) under FZ_EARLY. The sets are smaller than the earlier accounting said: in the fight window the shown set has a median of 48-59 columns, p90 134, the largest 280 (a boss with its explosions); the 177 + 173 pairs of section 13 were the walk's lists, not these records. With the split placed right, capacity is no longer what drops: the remaining drops are sets over ~250 columns meeting one over ~90. Two levers remain, both measured: (1) `FZ_EARLY=0` (fz41: the due buffer converted in its own slot only, two sets in flight): lost logic 4.32 -> 2.27%, drop frames 1.50 -> 1.18%, overruns 3 -> 0, holds 227k -> 100k, but late sets 12.8 -> 18.6% - the policy knob of section 24 again, not a free gain; (2) lending the two tilemaps' 42 sprites (1..42) when a tilemap column is empty (a dynamic SPR_PB) - not done: the tilemap writers (hal/tm.s) own those sprites every frame, and the gain is bounded by 42 columns.

**fz42 on the plain battery (9 x 60k, the movies' own shots):** lost logic 4.70% (fz40 4.32%), late 13.11% (12.78%), **drop frames 394 = 0.074% (fz40 8,040 = 1.50%)**, overruns 3 (3). The sets that were dropped are now converted whole: that is the half point of lost logic, the honest cost of complete sets (the routes also differ between the two batteries: bases 208k against 217k frames).

**The catalogue was Keaton's (fz43).** The descriptors (section 27) come from work/catalog/sprites/objects.json, a census of one playthrough: the other nations' planes, shots and stage objects use piece tables it never saw, which the pass takes the slow way (fz_em_*: ~3,000 cycles a record, no fast records - 1,161 of 28k records in nation 2's 20k frames, fzcost). work/play/fh/tabcen.lua logs every active object's C and B/A tables (table, pieces) over a run; tabmerge.py adds what the catalogue lacks under "nations" (444 tables from four 70k-frame runs, one per nation); fz_pd_prepare takes them like the rest but leaves a census table raw when a header's zoom nibble overlaps the piece's (25 of them, an assert for the catalogue's own). fz43 = fz42 + 2,312 descriptor entries of 1,548 tables (1,735 of 1,130 before). Per nation (fzcost, 20k frames): no fz_em records left; fast records 0.99-1.01 of their charge, the HUD cache paths 1.02-1.08, the multi-piece fz_pd_0110 0.85-0.90 (the remaining slack, bosses and enemies). Exact: the by-round entries against ov10 as fz35's (284 of 290 rounds, the rest absent on one side). The FZ_DIAG build outgrew the HAL's ROM room (0x80000..0xc8000: 294,912 bytes; the plain build has ~1,050 bytes left): the HUD cache's exit counters are behind `FZ_HCX` now.

**The full game, every nation, fz40 against the arcade** (3 seeds x 200k frames each per nation and target, identical inputs: botsel.lua's autofire and boss bombs; the stage by id from the game's own order table; "boss fights" = frames with a boss-type object active; the routes diverge between the two targets after the intro, so the per-stage figures are indicative, the totals the measure):

| nation | pilots | conversion lost | arcade lost | boss fights conv / arc | late sets | drop frames | overruns |
|---|---|---|---|---|---|---|---|
| 0 | the default two (Keaton's) | **3.63%** | 3.31% | 3.99 / 4.22% | 12.2% | 1.65% | 4 |
| 1 | | **4.59%** | 6.12% | 4.27 / 7.65% | 13.5% | 1.28% | 10 |
| 2 | | **7.80%** | 8.81% | 19.38 / 23.34% | 17.6% | 3.00% | 15 |
| 3 | | **7.38%** | 7.69% | 15.66 / 15.31% | 17.1% | 4.03% | 92 |

Per stage the conversion loses more than the arcade in: nation 0 desert 7.5 vs 6.8%, runway 4.8 vs 3.9, final 1.4 vs 0.6; nation 2 night fleet 7.9 vs 7.4, desert 13.2 vs 12.5, ocean 12.6 vs 11.0, final 9.9 vs 7.9; nation 3 night fleet 7.7 vs 6.4, desert 11.4 vs 9.3, its boss fights 15.7 vs 15.3 (with 70 of its 92 overruns there). Nations 2 and 3 are the heavy ones on both targets (the arcade itself loses 8-9% with them, 23% in nation 2's fights): their shots ($16 sparks every frame against the enemies, $18 blasts 12 a frame at 60+ objects) and their stages' objects; on the conversion they also ran through the uncatalogued tables (fz43). fz43's batteries follow below.

**Per-ship shot handling: what is left to optimise.** On the HAL's side nothing per ship: every ship's shot is one unzoomed C piece and already a fast record (the whole way from the builder to the shape routine ~500 cycles plus the shape's own), the $18 blasts go through the pair-bullet pool (2 columns a bullet, no pass at all) while it has slots, and the uncatalogued tables of nations 1-3 are descriptors from fz43 on. On the game's side a shot's frame is its handler (~400-700 cycles), shot_collide (0x2a142: three pool scans, every active slot visited; GX_SCAN's loop now; the arcade pays the same) and shot_vs_barriers (0x2b8c0: the barrier list, 411k calls over the catalogued run); the homing missiles' direction_to_point (0x2b9f6) is a table lookup (~350 cycles a call, 45M over the run) - nothing worth a table of its own (section 25's C3 lesson: the muls are cheap on the 68000's small operands). The per-shot cost that remains is the scan's visit of every active slot, which scales with the enemies and bullets, not with the ship; the x-bucket index that would cut it is the one thing ruled out as inexact (section 25).

**fz43 was wrong (found by its own batteries).** Three nations' runs froze in the coast/river stage (the players alive, the stage never ending, 0.04% lost logic) and the by-round entries against fz42 diverged from round 2593 on: the census (tabcen.lua) had taken every object with a non-zero state byte, but the builder draws only those with bit 7 set (fz_pass), so logic-only objects contributed their +0x1a field as a "table" - not a piece table at all, overlapping real tables and other data (the ROM also packs some 14-byte entries 12 bytes apart: a descriptor's +12/+13 lands on the next entry's pointer), and the rewrite changed bytes the game reads. The tool now drops census tables whose entries overlap another table's (the catalogue's own 30 overlapping tables are kept as they have been since fz27) and the census takes drawn objects only; AEROFGT_NATTAB=0 builds with the Keaton catalogue alone. The lesson stands beside section 29's: a census for a ROM rewrite must mirror the consumer's own tests exactly, and a rewrite's exactness check must run on every nation's route, not the intro's.

**What the game reads of a rewritten entry - measured on the arcade (work/play/fh/romhits.lua, fz46's 2,283 entries, four nations x 60k frames of the original in MAME with the same bot).** A read tap over the ROM (the boot checksum's reads skipped) by entry offset and reading PC: offsets +2, +8, +10, +12 are read by 0x2c0fa/0x2c11e/0x2c166/0x2c186/0x2c1c4/0x2c1cc only - the original's sprite-list builder (0x2bee0.., which the HAL replaces) - 6.8M times for the catalogue's entries, 1.3M for the census's, nothing else; offset +0 is read by the builder and by the handlers' sign and sentinel tests (0x1c8e8, 0x1caca, 0x1a07c, 0x1c50a, 0x1b7ac, 0x1a5e2, 0x1bb0c, 0x1b218), which the rewrite keeps true. So the descriptor rewrite is invisible to the game's logic for every table in fz46 (the census taken from drawn objects, overlapping entries and sentinel-bearing tables left raw); fz43's freeze came from the tables that are gone. The by-round entries comparison cannot test this past the intro (the game's vblank-count timers diverge between builds of different speed after ~300 rounds, section 24): a 354-table bisection on that oracle found "culprits" that were noise, two hours lost - the read tap is the tool for ROM rewrites (`AEROFGT_PDLIST=<file>` dumps the rewritten entries).

**fz46 (= fz42 + the nations' catalogue, 2,283 descriptor entries of 1,466 tables; p1 md5 cd50bfcb) - the plain battery (9 x 60k):** lost logic 4.67% (fz42 4.70, fz40 4.32), late 13.02%, drop frames 347 = 0.065%, overruns 3, no restarts. **The full game, every nation, fz46 against the arcade** (3 x 200k each; nation 1 seed 9 restarted from the memory check at frame 85,212 in its ocean stage - see below - its later frames count as a fresh game):

| nation | conversion lost | arcade lost | boss fights conv / arc | late sets | drop frames | overruns |
|---|---|---|---|---|---|---|
| 0 | **3.63%** | 3.31% | 4.04 / 4.22% | 12.2% | 0.14% | 4 |
| 1 | **5.34%** | 6.12% | 5.21 / 7.65% | 14.0% | 0.07% | 5 |
| 2 | **7.37%** | 8.81% | 17.25 / 23.34% | 17.3% | 0.30% | 9 |
| 3 | **5.21%** | 7.69% | 14.61 / 15.31% | 12.1% | 0.63% | 75 |

Against fz40 (the same inputs; routes diverge): nation 1 4.59 -> 5.34% (seed 9's restart), nation 2 7.80 -> 7.37%, nation 3 7.38 -> 5.21%; drop frames 1.3-4.0% -> 0.07-0.63% everywhere. Where the conversion still loses more than the arcade, per stage: nation 0 desert 7.1 vs 6.8%, runway 4.8 vs 3.9, final 1.2 vs 0.6 (the ending's loop), bases 2.8 vs 3.1 even; nation 1 night fleet 7.9 vs 7.5; nation 2 night fleet 8.0 vs 7.4; nation 3 night fleet 6.8 vs 6.4, desert 10.3 vs 9.3. Everywhere else, and in every nation's total and boss fights, the conversion loses fewer logic frames than the arcade board does on the same inputs. The night fleet (stage 0, the one the earlier summaries filed as "other") and the desert are the two stages left where the conversion is behind, by 0.4-1.0 points.

**The restart was a race in the record buffers (fz47).** The one run that restarted (fz46, nation 1 seed 9, frame 85,211): the exception probe (work/play/fh/excv.lua, a read tap on the vector table) caught a line-F exception with PC 0x4d0138 in the pass, with the record in work holding a y/x pair where its routine should be; a write tap on that record (recwr.lua) showed the next round's builder writing a fast record into the slot the pass was reading; fzev.lua's buffer-state events gave the order: the builder's duplicate-stamp loop (fz_build .same: "a complete buffer with the same stamp is freed") read buffer 0 as complete, the slot interrupted it, fz_due took that buffer into the pass (state 2), the builder resumed and cleared the state anyway, and the following round's build took the "free" buffer while the pass was in it. Latent since the duplicate-round logic of fz21, needing the slot to land between two instructions; the faster pass and the 200k-frame runs found it. fz47 runs the test and the clear with interrupts masked (eight instructions). fz42 and fz40 run the same seed without an exception, so the plain batteries above stand; the fix is in fz47 and every build after it.

**Closing the race, three ways measured (fz47-fz50; the plain battery, 9 x 60k; fz46 = 4.67% lost logic, 0.065% drop frames):**
- fz47: the builder's test-and-clear with interrupts masked (eight instructions): **5.21%**, busy 31.5% - the slot is interrupt-timed, a masked window shifts it; rejected.
- fz48: no free in the builder at all - each buffer carries its build number (FZB_SEQ) and fz_due keeps the later build of two with one stamp: **6.40%**, drop frames 0.43%, duplicates caught 143 instead of 1,293 per 20k frames (fzcnt.lua): the duplicates meet in fz_due's "a slot early" branch (age 1), untouched by that change, so the earlier build was converted first and the later after it - a stale set shown, two passes for one round; rejected.
- fz49: the early branch dropping the earlier build by its number too: duplicates 1,409, drops 50 per 20k, but **5.12%**: the earlier buffer stays taken until the slot frees it, and a round that needs it meanwhile builds nothing (FZ_SKIP 123 against 72 per 20k).
- **fz50: the builder frees the earlier duplicate as before, through TAS** (bit 7 set atomically; fz_due passes a buffer with bit 7 by; the byte still $81 is the builder's to clear, $82 means the slot took it meanwhile and only bit 7 is cleared), FZB_SEQ kept as the slot's safety net: **4.84%**, late 13.5%, drop frames 0.146%, overruns 6, the crash seed clean through 90k frames (excv.lua), duplicates 1,237 per 20k as fz46's. fz50 is the build (p1 md5 8c349bd5).

**The full game, every nation, fz50 against the arcade** (3 x 200k frames each, the same inputs; no restart in any run; the device trial clean, work/mister_fz50_chk9):

| nation | conversion lost | arcade lost | boss fights conv / arc | late sets | drop frames | overruns |
|---|---|---|---|---|---|---|
| 0 | **3.52%** | 3.31% | 4.18 / 4.22% | 11.6% | 0.12% | 6 |
| 1 | **5.81%** | 6.12% | 5.26 / 7.65% | 14.5% | 0.09% | 2 |
| 2 | **7.94%** | 8.81% | 20.39 / 23.34% | 17.5% | 0.35% | 16 |
| 3 | **7.26%** | 7.69% | 15.45 / 15.31% | 16.4% | 0.81% | 87 |

Per stage, the conversion still loses more than the arcade in the night fleet (nation 1 9.3 vs 7.5%, nation 2 8.1 vs 7.4, nation 3 7.0 vs 6.4), the desert (nation 0 8.3 vs 6.8, nation 3 11.8 vs 9.3), nation 2's ocean (13.7 vs 11.0) and the endings' loops (final: 1.1 vs 0.6, 11.4 vs 7.9 on 3,408 frames); everywhere else it loses fewer, by 1 to 5 points in the cities and bases and in nations 1 and 2's boss fights. Nation 3's overruns sit in its cities and its boss fights (the $18 blasts, 12 a frame at 60+ objects, the pool full and the rest through fz_bul). **Where the conversion is still behind the arcade: the night fleet and the desert, the two stages with the most ground objects and enemy bullets at once; the next profile should be of those two stages with nations 1 and 3.**

## 31. The night fleet and the desert: profile, plan, and the cuts (2026-10-19, fz51-fz56)
**User: "Profile the night fleet and desert stages and come up with a plan to get the conversion ahead or at minimum equal to the arcade, then implement and test thoroughly."**

**Profile** (work/play/fp/runfp.sh with botsel.lua on fz50; sprof3: nation 3 seed 7, frames 300-10900 (night fleet) and 20964-26800 (desert); sprof1: nation 1 seed 7, 31128-41027 (night fleet); work/play/fp/sana.py: by stage, by density, by boss frames, and by whether the game was still in its round when the slot began - BUSY frames, the ones that lose logic). The frame is full in both stages (idle ~1k of 200k). Mean cycles per BUSY frame, desert (52 objects) / night fleet (47):

| | desert | night fleet |
|---|---|---|
| game logic | 59k | 60k |
| record builder (game time) | 38k | 35k |
| collision scan gx (game time) | 22k | 23k |
| pass: control / pieces / shapes | 18k / 15k / 17k | 15k / 15k / 16k |
| bg conv+blast / scrub | 5k / 0 | 9k / 0 |
| palette | 6k | 3k |
| sched+vid+tcheck+flip+reclaim+HUD+pool | 15k | 15k |

The scrubs (tilemap 30-50k, palette) only run in idle frames: free. The arcade's own builder costs ~42k a frame averaged over a playthrough (0x2bfd0/0x2c0ec, 7.8G cycles); ours is cheaper than the arcade's, but the slot's work (the pass ~49k and ~25k of fixed stages) comes on top, so the game-side 119k meets a 126k budget where the arcade's ~115k meets 163k. The census: desert boss 11, bullets 7.5, shots 7, ground 4.5, items 4.5, explosions 4.4; night fleet bullets 12-16 (the pair-bullet pool does not take them: type $2d is a plain one-piece object), items 5, explosions 6, "other" 16 (the fleet's ships and turrets, types outside the category map). The builder's fast path costs ~875 cycles a record (counted: fz_pass ~60, the flags ~170, the tests ~165, the writes ~300, the shape index ~180), the pass's fast path ~350 and the shape routine ~250: every one-tile bullet or item is ~1,500 cycles a frame.

**Plan (exact, in order of yield):** (1) fast records charged only when clipped (the shape routine's charge keeps PRE_MAX for the way to it; the refund was already making it so): ~100 cycles a record of accounting in the slot; (2) the set anchor's column sum from a total the builder keeps (FZB_COLS) instead of walking up to 96 pieces at ~60 cycles each pass begin; (3) a 32-entry template cache in the builder for one-piece, unzoomed, no-B/A objects with the piece's own flips and colour - the record is a function of the table, the pass and the front bit alone but for y and x - replayed on a hit (~560 cycles instead of ~875), filled by the general fast path, verified in shadow mode (FZ_RCCHK: every record built the general way, a hit's template compared with it); (4) measured again, then the batteries, the nations, the device. Not in the plan: the collision scan (22k: every active slot visited per shot per frame; the x-bucket index is ruled out), the palette (dirty-driven already; the desert's cycling converts ~8 palettes a frame), the fixed slot stages (the slot's own mechanism).

**Implemented (fz51-fz53; the switches `FZ_FASTCHG`, `FZ_ANCHSUM`, `FZ_RC`, all default on under FZ_FAST; off together = fz50 byte for byte):**
- fz_ntab sends a fast record to fz_fast before any charge; fz_fast charges FZU_FAST only on the clipped exits (`.clip`, a stop there redoes the record as fz_hud's `.nt`), and the visible path keeps the FZU_FASTX credit (the shape routine's measured slack). fz52 had dropped that credit: the pass stopped ~3k cycles earlier each run and the plain battery lost 6.14% instead of 4.84% - a lesson in what the accounting is worth.
- fz_build keeps every record's unclipped column count in the buffer header (FZB_COLS, +6; the fast path from the descriptor's byte 10, the general records and the pair bullets through `.cols`); fz_anch reads it (+4) instead of walking up to ANLN pieces at ~60 cycles each pass begin; no cap any more.
- The template cache: FZ_RC_AT (sprite RAM +$1e00, 32 x 16 bytes, hashed by (table << 3) & $1f0): a one-piece, unzoomed, no-B/A object's fast record is a function of (table, its w2 byte d0 - the front bit, the object's flips and colour -, its routine flags d6) but for y and x; fz_rec probes after its flag prologue and replays a hit (the shape routine, w2|w3, the high bytes from the entry; y/x from the object plus the descriptor's offsets), ~500 cycles instead of ~875; the general fast path fills it. **Shadow mode** (`FZ_RCCHK=1`: every record built the general way, a hit's template compared with the record it would have replaced): 0 mismatches over four nations x 60k frames (fz52c: 51k/3k/29k/56k hits) and four x 40k on fz53c (63k/27k/23k/61k hits); in the desert window ~10 hits a build. The first key (fz52) excluded objects with their own colour or flips and hit ~1 record a build; keyed on d0/d6 it takes them all.
- Verification: the intro entries by round identical to ov10's (fz53r: 274 + 10 by the map word, 6 absent; a run WITH the bot differs in 35 rounds - the bot's own shots - so the reference comparison must run without it); the crash seed (nation 1 seed 9) clean through 90k frames; the plain battery fz53 5.16% lost logic (fz50 4.84%: the routes differ, see below), late 13.4%, drop frames 0.09%, overruns 1, no restarts.

**Same-route A/B (the stage order is a function of the random seed's low byte at the select's confirmation, stepped once a frame while the screen is up - so every build's lag gave it a different order; botsel.lua `SEEDSET=<hex>` writes the seed once the cursor is on the nation, at every select: the same order on every build, A/B runs only).** fz50 against fz53, nations 1 and 3, seeds 7 and 8, 60k frames: the stages come in the same order but the play still diverges (the vblank-count timers: deaths at different points), so the per-stage figures are indicative: nation 1 stage 0 (night fleet) 5.56 -> 7.18% (fz53's games ended in it more often), 2: 4.34 -> 3.68, 3: 5.18 -> 4.64, 4 (desert): 8.63 -> 9.36, 5: 6.93 -> 5.54, 6: 6.11 -> 2.38; nation 3 stage 0: 10.28 -> 10.08, 1: 7.15 -> 7.38, 2: 6.14 -> 5.24. The cycle profiles of the matched windows (work/play/fp/nf50, nf53, de50, de53; runfp.sh takes `MAP=` now - a profile must use its own build's map) are the measure of the cuts; the full-game nation batteries of fz53 the measure against the arcade.

**The cache measured (matched windows, nf50/nf53 night fleet frames 4000-7001, de50/de53 desert 26000-29001, nation 1, SEEDSET 6f48, each profile with its own build's map).** Builder (c_walk_scan+sort) per BUSY frame: night fleet 33.6k -> 36.0k, desert 34.1k -> 39.4k with the cache on - the probe on every miss (three tests, the hash, three compares, ~100 cycles) cost more than the ~10 hits a build gave back. **FZ_RC is off by default** (fz54 on; it stays in the tree, switched, and is not compatible with FZ_FINAL below).

**The scroll words are constants (2026-10-19).** G_DX_SCRX/SCRY (0xff8b4a/c), which every piece routine and fz_fast_rd add to y and x, have one writer in the original: the video init f_000ef4 (called from 0x45a and 0x51e), which copies six words from the table at 0xf68 - both halves (flip off: 1200 0000 1400 0000 **0000 0000**; flip on: f5ff 0000 f3ff 0000 **0000 0000**) leave them zero. The builder's own adds at 0x2c112/0x2c15a add zero 7.2M times a playthrough. Checked with a write tap (botsel.lua `SCRTAP=1`, the four bytes): conversion and arcade, nation 1, 30,000 frames each - writes at frame 0 only (the RAM test patterns), none after. So a fast record's final sprite words are known at the builder point.

**Implemented (fz54/fz55, `FZ_FINAL`, default on with FZ_FASTCHG; off together with the other three = fz50 byte for byte, fz55n):** in fz_rec's fast path, once y and x carry the piece's offsets, a piece on the screen whole (0 <= y < 224, 0 <= x < 320: no wrap, no clip; the y bound is FZ_FYM, set per build to 224 when `tst.l G_DX_SCRX` is zero and to 0 otherwise, so a non-zero scroll word would only send every record down the old path) gets w0 = high byte | y and w1 = high byte | x written final, the flag $fe; otherwise y and x raw with $ff as before. fz_ntab sends $fe to fz_fastv: `movem.w 4(a5),d2-d5`, the head-slot check, the credit FZU_FASTV (16 units: FZU_FASTX 6 + the ~160 cycles of tests not run), the behind-tilemap part, the shape routine - ~22 instructions and both FZ_SY/FZ_SX adds less than fz_fast_rd's visible way. fz_anch (ANCHSUM off) and fz_split_anch take $fe as $ff (w1's high byte still at +15). Cost moved into the builder: two compares and branches and the word compose (~50 cycles a record); saved in the slot ~240. **Lesson (fz54):** the first version stored x as a byte; x in 256..319 lost bit 8 - caught by the intro entries A/B (52 rounds differed, the entry 0c28**01**20.. as 0c28**00**20..) before anything else ran. fz55: the intro entries by round identical to ov10's again (rounds 8-297 without the bot: 253 equal + 10 by the map word + the 22/2 absent, exactly fz53r's figures); the crash seed (nation 1 seed 9) clean through 90,000 frames, no restart in any run (the boot hash never recurs after row 40); the plain battery (9 seeds x 60k) 5.07% lost logic, late 12.64%, drop frames 440 (0.082%), overruns 0 (fz53 5.16 / 13.36 / 472 / 1; fz50 4.84 / 13.48 / 784 / 6 - the routes differ between builds, so the stage mix differs: desert 45.6k frames in fz55's games against 22.5k in fz53's).

**fz55 against the arcade, the full game (nation batteries at the arcade's length: 3 seeds x 200,000 frames a nation, botsel.lua autofire + boss bombs, work/play/fp/bl_n<N>55L_<seed>; natsum.py 55L orig). Lost logic %, conversion / arcade:**
| nation | total | night fleet | desert | cities | coast/river | bases | ocean | runway | final | boss fights | late | drop frames | overruns |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | **3.10 / 3.31** | - | 7.33 / 6.77 | 5.04 / 7.36 | 2.14 / 3.34 | 2.40 / 3.07 | 4.39 / 5.86 | 3.27 / 3.93 | 0.73 / 0.63 | 3.39 / 4.22 | 9.98% | 0.14% | 3 |
| 1 | **4.59 / 6.12** | 7.67 / 7.54 | 6.99 / 7.95 | - | 2.55 / 5.84 | 3.10 / 4.51 | 6.19 / 6.97 | 7.50 / 8.54 | - | 3.83 / 7.65 | 12.07% | 0.05% | 2 |
| 2 | **7.63 / 8.81** | 7.74 / 7.40 | 11.95 / 12.49 | 9.28 / 14.11 | - | 4.31 / 5.30 | 12.41 / 11.01 | 12.95 / 14.07 | 5.31 / 7.94 | 18.50 / 23.34 | 16.33% | 0.48% | 6 |
| 3 | **7.11 / 7.69** | 7.56 / 6.43 | 9.69 / 9.28 | 7.27 / 10.10 | 5.56 / 6.03 | - | 7.36 / 8.42 | 8.61 / 10.28 | 4.74 / 6.30 | 14.52 / 15.31 | 15.39% | 0.90% | 62 |

fz50 on the same batteries was 3.52 / 5.81 / 7.94 / 7.26 (night fleet 9.31 / 8.05 / 7.04 for nations 1-3, desert 8.34 / 7.81 / 12.38 / 11.81): every nation's total is ahead of the arcade now, by 0.2 to 1.5 points, and 23 of the 28 stage cells. **The night fleet and the desert are within the noise of this comparison, not decided by it**: a conversion game and an arcade game on the same inputs diverge (the lag differs, so the shots land differently - nation 3's night fleet reads 7.04% on fz50 and 7.56% on fz55, a build that is strictly cheaper a frame), so a stage's figure moves by ~0.5 point between builds for reasons other than cost; the night fleet is behind by 0.1-1.1 points in nations 1-3 and the desert by 0.4-0.6 in nations 0 and 3, ahead elsewhere. The totals over 600k frames a nation are the robust figure. No restart in any run (the boot hash never recurs after row 40); the crash seed clean through 90k frames.

**Device (2026-10-19):** fz55 (p1 b853ea63) deployed to the MiSTer (backup 538-p1.p1.fz50_8c349bd5); the chk9 trial clean (work/mister_fz55_chk9/sheet.png: the night fleet, the cities with the HUD, game over and the staff screen, the second game's pilot select and cities).

**The switches measured one by one (split-category profiles, 2026-10-19).** The matched-window comparison by SEEDSET failed for fz55 (its window had 15 objects a frame against 36: the play diverges even on the same stage order), so the measure became each build's own densest 3,000-frame window of the night fleet and the desert in its nation 3 seed 7 game (bl_n3<build>_7/bot.txt, column 5), by density bin, with a map that gives fz_anch, fz_ntab, fz_fast, fz_fastv, fz_split_anch and fz_rec's `.cols` block their own categories (work/play/fp/map55x.txt, map50x.txt, map56x.txt: N/R lines appended to fmap.py's map; scratch splitana.py over frames.npz). Cycles a BUSY frame, desert (fz50 de50b2 at 62 objects, fz55 de55b2 at 57):
| | fz50 | fz55 | |
|---|---|---|---|
| builder (fz_build/pass/rec) | 39.4k | 41.8k + `.cols` 3.6k | FZ_FINAL +2.4k; **FZ_ANCHSUM +3.6k** |
| fz_anch (the pass begin's column walk) | 0.6k | 0.4k | what FZ_ANCHSUM saved |
| fz_ntab | 5.9k | 5.1k | FZ_FASTCHG |
| fz_fast + fz_fastv | 11.5k | 1.8k + 4.0k | **FZ_FINAL -5.8k**; 87% of the fast records final |
| total | 198.4k | 198.5k | |
The night fleet (nf50b/nf55b2, 53 objects) the same: builder 38.3k -> 41.8k + `.cols` 3.7k, fast 17.0k -> 1.2k + 4.3k, fz_anch 0.4k. So FZ_ANCHSUM was a loss of ~3k a dense frame of game time (plan item 2 assumed the walk cost 60 cycles a piece over up to ANLN pieces; it costs ~600 a pass): **off by default from fz56**. fz56's own split profiles (de56b2 desert at 61 objects, nf56b2 night fleet at 55): builder 42.0k / 42.5k (no `.cols`), fz_anch 1.0k / 0.7k, fz_fast + fz_fastv 1.4k + 4.2k / 1.3k + 4.4k, fz_ntab 5.5k / 4.4k; the HAL's sprite path (builder + pieces + control) 69.8k against fz50's 71.6k in the desert and 70.8k against 73.4k in the night fleet, per object ~-60 cycles net (FZ_FINAL: the pass -180 a fast record, the builder +60; the frame totals move with the game's own content more than with this). fz56 = FZ_FINAL + FZ_FASTCHG (fz56n with both off = fz50 byte for byte; the DIRECT default = ov10b; p1 bd96d06a).

**fz56 verified:** the intro entries by round identical to ov10's (254 + 10 by the map word); the crash seed clean through 90k; the plain battery **3.96% lost logic** (fz55 5.07, fz50 4.84), late 11.55% (12.64 / 13.48), drop frames 0.101% (0.082 / 0.146), overruns 4, busy 27.9% (32.5 / 30.6); no restart in any of the 25 runs. **Against the arcade (3 x 200k a nation), lost logic conversion / arcade:**
| nation | total | night fleet | desert | cities | coast/river | bases | ocean | runway | final | boss fights | late | drops | overruns |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | **2.99 / 3.31** | - | 6.00 / 6.77 | 4.56 / 7.36 | 1.63 / 3.34 | 2.45 / 3.07 | 4.09 / 5.86 | 3.41 / 3.93 | 1.20 / 0.63 | 3.00 / 4.22 | 10.67% | 0.18% | 7 |
| 1 | **4.27 / 6.12** | 6.57 / 7.54 | 7.56 / 7.95 | - | 2.55 / 5.84 | 2.73 / 4.51 | 3.35 / 6.97 | 6.19 / 8.54 | - | 4.05 / 7.65 | 11.85% | 0.06% | 4 |
| 2 | **6.68 / 8.81** | 7.86 / 7.40 | 11.71 / 12.49 | 8.20 / 14.11 | - | 3.86 / 5.30 | 5.81 / 11.01 | - | - | 15.78 / 23.34 | 15.48% | 0.32% | 6 |
| 3 | **6.46 / 7.69** | 6.56 / 6.43 | 10.18 / 9.28 | 6.58 / 10.10 | 5.18 / 6.03 | - | 6.48 / 8.42 | 8.72 / 10.28 | 4.11 / 6.30 | 13.65 / 15.31 | 14.95% | 0.75% | 74 |
Every nation's total ahead by 0.3 to 2.1 points (fz50: 3.52 / 5.81 / 7.94 / 7.26); the night fleet ahead in nation 1, level in nation 3 (+0.13), behind in nation 2 (+0.46); the desert ahead in nations 0-2, behind in nation 3 (+0.9 on 25k frames). The stage cells carry the play-divergence noise described above (~0.5 point); the totals over 600k frames are the robust figure. Device: fz56 deployed (backup 538-p1.p1.fz55_b853ea63), chk9 trial clean (work/mister_fz56_chk9/sheet.png).

**Left on the table (exact):** the builder's fast path is still ~900 cycles a record (the flags ~170, the walk's tests ~165, the word composition and the shape index ~480): per-descriptor ROM templates (w2 base, w3, the high bytes, the shape index base; 1,104 one-piece entries x 8 bytes fit the 14 KB free at 0xdc800) would cut ~300 of it, ~12k a dense frame - the one lever left that moves the night fleet decisively; the collision scan (17-23k) is at its exact floor; the small-bullet pool (~-18k) is not exact (draw-order slip over the player).




## 32. ROM templates for the one-piece descriptors (2026-10-19, fz57)

**The lever (31's "left on the table"):** the builder's fast path composed each one-piece record's words and shape index from the descriptor every time - the w2 byte masked by the routine flags, the map masked and tagged, the shape index from the header nibbles (~480 cycles of a ~900-cycle record). All of it but y/x, the object's d0 and the pass bits is a function of the descriptor alone.

**FZ_TPL (hal/fz.s, tools/aerofgt2neo.py; on in the shipped DEFS as `FZ_TPL=1`):** a 16-byte template per piece descriptor in the free ROM after the game's (FZ_TPL_AT 0x7b470 to 0x80000: 1,208 of them; the arcade's boot touches every word of the ROM at 0x4ea, a read loop with no sum, and nothing reads the region afterwards - romtap.lua on four nations x 40k frames, late reads 0): +0 l spr_fast_jt's entry for the piece's sizes and zoom, in front, no flips; +4 w y, +6 w x; +8 l the piece's colour | flips byte << 24 | the map; +12 w w0's high byte << 8 | w1's; +14 w w1's << 8. The descriptor's first word carries the template's index in bits 0-12 (0: none), and its flags move to bits 14 (a descriptor) and 13 (a HUD piece) - FZD_FD/FZD_FH in every flag test; the pointer's high byte, which the HAL never read, is gone. fz_rec: after the object tests (B/A, pieces, zoom) `move.w (a3),d3; andi.w #$1fff,d3; beq .gen; lsl.w #4,d3; lea FZ_TPL_AT,a3; adda.w d3,a3` replaces the descriptor/HUD/map-range tests; y/x and the high bytes as FZ_FINAL; w2 | w3 as one long (`andi.l #$c0ffffff` when the colour is the object's, `#$0fffffff` when the flips are, d0 rotated in, `ori.l #$10002000` in pass 1); the routine `(a3,d3.w)` from the template's entry + the flips' $200/$400 (swap, lsr #5, andi #$600). ~130 cycles less a record by the instruction counts (tests 184 -> 184 but the three descriptor tests gone, composition ~160 -> ~150, shape ~178 -> 62).

**Which descriptors:** 2,219 eligible (not HUD, not sharing bytes with another descriptor - 12-byte-packed pairs; a phantom table whose first entry is a sentinel makes no edit and is no clash, fz57's first rule excluded eight of the most drawn tables for it: 54e60 alone 22k records in 120k frames). The room takes 1,208: work/catalog/sprites/tpl_rank.txt (tplhist.lua on the FZ_TPLCHK build: every one-piece fast record's descriptor over nations 0-3 x 30k frames, 2.29M records, 693 distinct) first, then the one-piece tables' entries, then the rest by address. Every descriptor seen drawn one-piece has a template.

**Shadow mode (`FZ_TPLCHK=1`):** the template's record is built, copied to the stack, the general fast path builds the record again over it, and the two are compared (FZ_TPLHIT compares, FZ_TPLBAD mismatches, FZ_TPLMISS one-piece records without a template; the record kept is the general path's). tplchk.lua reads the counters (16-bit: they wrap), tplhist.lua the descriptors (write taps on the counters: a3 at the miss, the stacked descriptor at the hit).

**Two mistakes caught before anything ran long:** (1) the first index field (word bits 4-14) overlapped the flag bits (8-9: the first *byte's* bits 0-1): HUD descriptors pointed at template 48 - the intro entries A/B showed 86 differing rounds, the offline template-against-descriptor check 710 bad of 939; hence the flags' move. (2) `tpl` the parameter shadowed by `tpl = {}` in the tool: the switched-off build (fz57n) differed from fz56 in 4,471 bytes - the flag words of every descriptor - before `cmp` caught it. Rule kept: the offline check (every template's words against its descriptor's, from the built ROM) and `cmp` of the switched-off build run before any emulator.

**Verification (fz57, p1 ce142b9f):** fz57n (the switch off) == fz56; the DIRECT default == ov10b; the exact build == exck8. Intro entries by round against ov10: 253 equal, 9 map-word rounds, 23/2 absent (fz56r: 254/10/21/2). Shadow mode, four nations x 30k frames: 0 mismatches, 0 one-piece records without a template. Arcade ROM read tap on 0x7b46e-0x7ffff, four nations x 40k frames: 9,673 reads, all at boot (the loop at 0x4ea), none after frame 300. Crash seed (nation 1 seed 9, 90k): no reboot, 3,235 lost frames (fz56 4,367). No reboot in any of the 25 runs.

**Plain battery (nine seeds x 60k):** lost logic 3.05% (fz56 3.96%, fz50 4.84%), late 10.39% (11.55%), drop frames 420 = 0.078% (542), overruns 2 (4), busy 24.1% (27.9%). By stage: bases 1.5% (2.4), coast/river 3.8 (4.8), cities 2.8 (3.6), desert 9.1 (9.7).

**Nation batteries (three seeds x 200k each, lost logic conversion / arcade; fz56's conversion figure in brackets):**

| nation | total | night fleet | desert | boss fights |
|---|---|---|---|---|
| 0 | 2.61 / 3.31 (2.99) | - | 5.15 / 6.77 (6.00) | 2.49 / 4.22 |
| 1 | 3.91 / 6.12 (4.27) | 6.37 / 7.54 (6.57) | 5.45 / 7.95 (7.56) | 3.91 / 7.65 |
| 2 | 6.21 / 8.81 (6.68) | 6.39 / 7.40 (7.86) | 10.47 / 12.49 (11.71) | 15.65 / 23.34 |
| 3 | 4.71 / 7.69 (6.46) | 5.54 / 6.43 (6.56) | 7.69 / 9.28 (10.18) | 12.70 / 15.31 |

Every total and every night fleet and desert cell is ahead of the arcade now (fz56 had nation 2's night fleet and nation 3's desert behind). Overruns per nation 11/4/12/73 (fz56 7/4/6/74: nation 3's are its boss fights on these seeds, 64 of them). Device: fz57 deployed (backup fz56_bd96d06a), chk9 trial clean (work/mister_fz57_chk9/sheet.png).

**Split profiles (each build's own densest 3,000-frame window of the nation 3 seed 7 game, BUSY frames, cycles a frame):** desert, 59-61 objects: builder 41.95k (fz56) -> 37.86k (fz57), pass ntab 5.5k -> 5.1k, fast+fastv 5.6k -> 6.0k, total 199.0k -> 198.2k; night fleet, 55 objects: builder 42.5k -> 38.6k, pass unchanged within noise, total 199.0k -> 197.6k. About 4k a dense frame off the builder, ~110 cycles a record over the ~35 fast records of such a frame - the estimate was 130 by instruction counts; the rest of the builder (the prologue's flags ~170, the object tests, the pair-bullet test, the general path's objects) stands. The HAL sprite path is now ~65k a dense desert frame against fz50's 71.6k.

**Left on the table (exact):** the prologue (the routine flags from the object, ~170 cycles) and the object tests (~120) are what a one-piece record costs before its template; a per-object template would need the object's flags in its key (FZ_RC's lesson: a probe on every miss costs more than the hits give). The collision scan (17-23k a dense frame) is at its exact floor; the small-bullet pool (~-18k) is not exact.

## 33. fz57's attract mode: the template path took raw tables (2026-10-19, fz58)

**The report:** on the MiSTer, the attract mode missed sprites and drew the letter "H" in place of many. MAME reproduced it (`work/play/fh/snap_fz57`, the harness with `attract.txt` - no inputs - and a snapshot every 300 frames, against fz56): the ship's missiles, "INSERT COINS!", the red logo of the staff roll, the pilot portraits and the explosion scene were "H" tiles or gone.

**The cause (fz57's fz_rec, FZ_TPL):** the template path took the descriptor's first word, masked bits 0-12 and used them as the template's index when not zero - without testing bit 14, the FZD_FD flag that says the tool edited the entry. A raw table the census never saw keeps its ROM pointer there: a high word of 0-7, so a table whose pieces lie above $10000 drew template 1-7 (the most drawn descriptors: player shots and the like - an "H"-shaped tile at the wrong place and size). The play batteries never met one because the catalogue's census covers every object the game draws in play; the attract mode's intro and staff roll draw tables that are not in it, and no fz57 check looked at the attract mode (the by-round entries stop at round 297, the device trial photographs play).

**The fix (fz58):** `subi.w #$4001,d3; cmpi.w #$1fff,d3; bhs .gen` - the word must be $4001-$5fff: FZD_FD set, an index, and not FZD_FH. The first attempt tested the sign alone (`subi; bmi`), which sent a HUD piece's word ($6000, both flags) to slot $1fff - an address error: the DIAG build rebooted twice in the entries run. 8 cycles more a template record than fz57 (cmpi.w). Nothing in the tool changed.

**Verification (fz58, p1 31d0e643):** fz58n (the switch off) == fz56, the DIRECT default == ov10b, the exact build == exck8. The attract mode in MAME: fz58's 41 snapshots show what fz56's show. Shadow mode over the attract mode (12,000 frames): 61,015 compares, 0 bad, 24 one-piece records without a template (raw tables now on the general path); over nations 0-3 x 30k of play: 0 bad (nation 0: 144 without a template after frame 20,000, where fz57's run had restarted). Intro entries by round against ov10: 253 equal, 9 map-word, 23/2 absent, as fz57. No reboot in the attract runs, the entries run, the shadow runs, the nine-seed battery or the crash seed.

**Plain battery (nine seeds x 60k):** lost logic 3.50% (fz57 3.05%), late 11.20% (10.39%), drop frames 293 (420), overruns 2 (2). By stage the two are level - coast 3.7 vs 3.8, bases 1.5 vs 1.5, cities 3.1 vs 2.8, desert 8.7 vs 9.1 - and the totals differ because fz58's games went further: 24.8k ocean frames against 2.6k, 54k desert against 35k.

**The lesson:** a check on every mode the ROM reaches, not every mode the bots play: the attract snapshot run (`snap_<build>`, 12,000 frames, a sheet of 41) joins the pre-deploy set beside the by-round entries and the device trial, which now photographs the attract cycle first (`/tmp/chk10.sh`).

## 34. The demo's credit text over the 2P bomb HUD (2026-10-19, investigated, not fixed)

**The report:** in the attract demo with a credit, the centred "CREDIT: 1" draws over part of the 2P bomb HUD and corrupts it (MiSTer, fz58).

**What the arcade does (MAME aerofgt, `attract_coin.txt`: a coin at frame 1500, snapshots every 5 frames, `work/play/fh/snapb_orig`):** the text blinks - on ~35 frames, off ~40 - and while on, its colon and digit are sprites drawn after the 2P bombs, so they sit on top of whole bomb icons (the list is drawn last-to-first with pdrawgfx: the last entry on top).

**What the conversion does (`snapb_neo`, probe `hudtxt.lua` -> `work/play/fh/ht58/out.txt`):** the letters "CREDIT:" are plain sprites (their map is not a HUD lookup entry) and go under the fix layer. The digit is HUD strip slot 3 (lookup 0x3fd8): 2 cells at fix column 0, rows 18-19, which lie inside slot 6's strip, the 2P bombs, column 0 rows 17-28 (12 cells). Both are taken to the fix layer (fx_hud_take knows nothing of overlaps), so: at blink-on the digit's 2 cells overwrite the bombs' middle cells (the bombs cut, the colon hidden under the bomb cells); at blink-off slot 3 is gone and its clear wipes rows 18-19, and the bomb strip, "unchanged" by the shadow, is never rewritten: the bombs stay hollow slivers until something changes them. HAL_FIXUSED (tilemap-1 text) is 0 throughout the demo; it is not the tilemap text path.

**The fix to make (an overlap rule in the HUD take, both builds share fx_hud_take):** a strip whose cells meet a strip taken earlier in the same walk is above it (later in the list = on top); the earlier one must yield - stay a sprite and have its cells cleared - while the later one is present, with a hysteresis of ~64 walks so the blink does not flip-flop the bombs (a yield bit per slot + the walk number of the last sighting). The later strip is refused for that one walk (a sprite under the cells, one frame, at the first blink-on only). A strip meeting a shown slot not yet seen this walk is refused (that slot is above it, or gone and cleared this walk). The HUD pass must queue the gone/yield clears before the writes (today slot order: slot 3's write, then slot 6's clear wiping it) - either clears-first iteration over FX_HSEEN, or a clear invalidating the shadows it overlaps. The overlap check belongs on the `.full` path only (a new or changed strip; ~7 rectangle compares), the yield test at the take's start (one btst). Result expected: the arcade's picture - the digit on the fix layer above the bombs as sprites, the colon a sprite over the bombs in list order.

## 35. The HUD overlap rule (2026-10-19, fz59)

**The fix for 34 (`FX_HOV=1`, in the shipped DEFS; hal/fx.s, hal/fz.s):** two HUD strips that meet on the fix layer are resolved by the walk's order - the walk's first entry is drawn on top (hal/fz.s: the first entry gets the highest columns) - so the strip taken LATER in the walk is the one under, and it yields: it stays a sprite and its cells are cleared, while the strip above is seen, with 64 walks of hysteresis so the credit text's blink (on ~35, off ~40 frames) does not flip the bombs back and forth.
- `fx_hud_ov`, at a strip's take when it is new or moved (a strip changed in place skips it - the score digits never pay): against HUD slots 0-7 (the texts 8-12 sit in the screen's middle and meet nothing), two fix columns each, columns within 1 and rows meeting. One taken earlier this walk is above: this strip is refused, a sprite under its cells. One shown but not seen yet is under this one, or gone: it is marked a suspect (FX_HSUS, FX_HYTO = this slot) and this strip is taken.
- At every take's entry (fx_hud_take; the fused HUD cache's hit path sends suspects and yielders there too): a suspect yields (FX_HYIELD, FX_HYSEQ = the walk number) and is refused; a yielder is refused while its sighting is fresh (FX_WSEQ - FX_HYSEQ <= FX_HYAGE 64), else released. A suspect that never comes is simply gone (cleared by the pass as before).
- The HUD pass (fx_walk .hud): with yields, once a walk and before the slots' round, `fx_hud_round1` renews the sightings of the yielders whose strip above was seen (fx_hud_yref) and clears the yielders shown and not taken - so the yielder's cells go before the cells of the strip above are written (in slot order the digit's write came before the bombs' clear and was wiped).
- State at G_DX_LIST+$7c0..$7ed (FX_HYIELD w, FX_HYTO 13 b, FX_HYSEQ 13 w, FX_HSUS w, FX_HOVRAN b, FX_HR1 b), reset with the shadow (fx_hreset).
- Charges: FZU_HUDT +7 units (the two entry tests, the charge after the take: `sne`/`tst` around it), FZU_HHIT +3 (the cache's test), FXU_HOV 76 charged after the take when the loop ran (FX_HOVRAN; the credit may go negative - the next refill measures), FXU_HOV0 12 at the pass's start (its own test, every slot), FXU_HOV1 30 the round. Each one of these was found by the battery's overruns: 160 with the loop uncharged, 113 with it charged but the fixed overhead not, 40 with the two-round pass's loop overhead, 14 now (fz58 2; AUDIT 33's build). The overrun probe (`ovtap.lua`, OVR_DIAG build fz59o, seed 7): 0-3 overruns in 45k frames, in the flip's tail of heavy frames (OVD_OPC in hal_spr_flip, the commit's steps already late), none in frames with the loop or yields.
- The HAL outgrew 0x80000-0xc8000 (294,912 bytes; fz59 295,100): the tool now moves S_REMAP and L0VAR up in 4KB steps when the HAL does not fit (build_prom: assembled, the layout written again, assembled again; `the video tables moved up by 0x1000`); builds that fit are unchanged (fz59n == fz58, the DIRECT default == ov10b, the exact == exck8).

**Mistakes on the way:** the rule's direction (the arcade draws the list last-to-first with pdrawgfx, so the LAST entry is on top - but the walk's list is in reverse order of the arcade's, the first entry on top; the yield trace showed the digit visited before the bombs); a stale shadow taken for "under" (the digit's shadow after its blink-off made the bombs mark it yielding, and the renewal kept the wrong yield alive: hence suspects confirmed at their own take); the cache's hit path bypassing the take (the yield never engaged in the first demo); round 1 clobbering the pass's slot index (reboots in the coin attract run); the HUD pass's two-round loop costing ~340 uncharged cycles a walk.

**Verification (fz59, p1 e77c4f7a):** the demo with a credit in MAME (`attract_coin.txt`, 5-frame snapshots over both demo passes, `work/play/fh/snapd_fz59`, `snapb_fz59`): the colon and digit over whole bombs while the text is on, whole bombs while it is off - the arcade's picture; the state probe (`hudtxt.lua` with FX_HYIELD): the bombs yield from the first blink-on after they appear and stay sprites through the blinks. Shadow mode over the coin attract run and nations 0-3 x 30k: 0 bad; intro entries vs ov10: 253-254 equal, 10 different, as fz57/58; no reboot anywhere (the coin attract runs, the entries, the shadows, the battery, the crash seed). Plain battery: lost logic 3.69% (fz58 3.50%: noise, the stages differ), late 11.35% (11.20), drop frames 506 (293), overruns 14 (2); crash seed 3,083 lost (fz58 3,686), no reboot.

**Nation batteries (three seeds x 200k, lost logic conversion / arcade; fz57's conversion figure in brackets):** nation 0 2.30 / 3.31 (2.61), nation 1 3.90 / 6.12 (3.91), nation 2 5.71 / 8.81 (6.21), nation 3 5.71 / 7.69 (4.71); night fleet 6.09 / 7.54 (6.37), 6.07 / 7.40 (6.39), 5.60 / 6.43 (5.54); desert 6.05 / 6.77 (5.15), 5.59 / 7.95 (5.45), 10.15 / 12.49 (10.47), 8.86 / 9.28 (7.69). Every cell ahead of the arcade; nation 3 a point behind fz57 and nation 0 and 2 half a point ahead - the bench's noise (~1 point a cell). Overruns per nation 14/14/22/65 (fz57 11/4/12/73).

## 36. Scene cuts: a cleared layer off the screen (2026-10-19, fz60)

**The report:** a "purple line screen" between the attract demo and the hangar scene; a green title logo at the city stage's start on the MiSTer.

**What happens (MAME, `work/play/fh/tr6_neo` 2300-2520 every 2 frames against `tr6_orig`):** the game fades to black, then at frames 2397-2400 clears both layers (tm_clr0/1 -> TM_ALL) and rewrites them over 2397-2404 with the hangar's map, and sets the hangar's palette. The arcade shows black, one frame of the half-written map (orange sky below black), then the scene. The conversion showed the city's columns in the hangar's palette for two frames (2406-2410): a clear only marked the layer stale (hal_bg_layer_stale) and the reconversion of 21 columns takes ~10 frames; meanwhile the old columns stayed on the screen. Tilemap 1's own hide (hal_bg_l1hide, idle time) never ran during the burst. The green logo on the MiSTer is the same thing at the title-to-city cut (not visible in MAME, where the fade covers it).

**The fix (`BG_HIDECLR=1`, in the shipped DEFS; hal/tm.s, hal/bg.s, hal/tx.s):** at a clear (tm_apply's TM_ALL branch): layer 0 is hidden whole - HAL_BG_HID, its two chain heads written with height 0 at the commit (hal_bg_place, HAL_BG_POS bit 3) - until every column is converted (HAL_BG_PEND) and blasted (G_BGSTG), then shown again; layer 1 slot by slot - its masks emptied, FX1_PEND dropped, and at the commit (hal_bg_l1place, FX1_CLR) all 21 columns written height 0 with no heads; a column is a head again when its blast comes (hal_bg_mask1), and only once its rows in view are all converted (its PEND byte clear: a blast of the first rows alone showed the rest stale as a band). Now the cut is black, then the scene (layer 1's text and plane a frame before layer 0's sky). Hidden spans in 30k frames of play: 13-17 frames, at the scene changes only (the game-over/restart cuts); in the attract 27 frames at the title-to-city fade (black anyway).

**Verification (fz60, p1 76a1192a):** fz60n == fz59, the DIRECT default == ov10b, the exact == exck8. The demo-to-hangar cut clean (`cut_fz60c.png`), the city demo start as before, the attract sheet as fz59; intro entries vs ov10 254 equal / 10 different; battery lost logic 3.92% (fz59 3.69, noise), late 12.1%, overruns 12; crash seed no reboot. Probes: `cuttap.lua` (clears, dirty marks, tilemap RAM writes per frame), `hidtap.lua` (hidden spans), the VRAM dump's column heights.

## 37. The building jitter: the tilemaps placed for the shown set (2026-10-19, fz61)

**The report:** buildings in the city still jitter.

**Measured (MAME, `work/play/fh/jv60`: the Neo VRAM and the HAL's variables dumped every frame over the city demo, frames 1900-2020; every ring sprite matched between consecutive frames by its row and first tile, its x motion against the tilemap head's):** on every late frame (the sprite set shown a slot after its due slot: HAL_SPR_RDY) the tilemap moved its pixel while every sprite stayed - 142 sprite-frames at +1, none at 0 - and the frame after, the ground sprites moved 2 while the tilemap moved 1. The sprites are composed with the scroll of their pass's slot (FZ_SY/FZ_SX); shown a slot late, they lag the tilemaps, which hal_bg_place places with the current slot's scroll, by that slot's scroll step: a 1-pixel wobble of every ground sprite on ~10% of the frames (late 10-12%), plain on the buildings, invisible on the moving enemies. (The arcade's own lost frames freeze the list and the scroll together.)

**The fix (`BG_SETSCR=1`, in the shipped DEFS; hal/video.s, hal/bg.s, hal/tx.s):** the commit flips first, then places the tilemaps (hal_bg_place after hal_spr_flip); hal_bg_place keeps a three-slot history of the scroll (HAL_SCRH, hal_bg_hist) and, for a shown set late by one or two slots (HAL_FRAMES+2 - HAL_SPR_RDY[HAL_SPR_SHOWN]), places both layers with the scroll of the slot the set was due in (hal_bg_held), if within 3 pixels on both axes - a cut keeps the slot's own scroll, the columns having been assigned for it. The moved bits are then taken against what is placed (HAL_BG_SX/SY), not hal_bg_window's. `jv61`: late frames 0 relative motion (301 sprite-frames), the frame after both move together; the tilemap holds with the sprites and catches up with them.

**Verification (fz61, p1 781895b6):** fz61n == fz60, the DIRECT default == ov10b, the exact == exck8; intro entries vs ov10 253 equal / 10 different; the attract sheet as before; no reboot in the dumps, the entries, the attract.

## 38. The Universe BIOS: soft DIPs, the NGH number, the splash logo (2026-10-19, fz62)

**Soft DIPs (MAME, Universe BIOS 4.0, `work/play/fh/menu.lua` driving the Test switch and the joystick by frame; snapshots in `ub_menu*`):** the main menu's SETTING UP THE SOFT DIP lists "SLOT1 AERO FIGHTERS" (the table's name) and its page shows the eight options (COIN SLOT, COIN A/B, START COIN, DEMO SOUNDS, DIFFICULTY, LIVES, BONUS LIFE); A/B step a value forward/back, C leaves the page. A round trip (LIVES to 3, C, C, EXIT, the game booting) handed the game `02` in the LIVES byte and the game started with three planes in the HUD; the untouched page gave one. The stock MVS BIOS shows the same page from the same table (`mvs_menu`).
- Found on the way: the Universe BIOS makes a game's settings entry with every option at its FIRST choice, not at the table's default nibble, so a page once opened reset LIVES to 1 (the table's first choice), DIFFICULTY to EASY, COIN to 3 COINS/1 CR. Under `UB_LOGO=1` (the Universe-BIOS build) the tool rotates each option's choices so the default comes first (SOFTDIPS at module level): a page never opened and a page left untouched now mean the same game (verified: the game's bytes all 0 both ways, 3 lives). The arcade's own defaults (3 lives, NORMAL, 1 COIN/1 CR) are unchanged.

**NGH number:** 0x0538 (BCD "538") - the header's word at 0x108. Not in MAME's neogeo.cpp list (the official titles end at NGH-272, the homebrews go to 4-digit numbers that do not include 538), and the Universe BIOS 4.0 ROM holds no word-aligned 0x0538 (its game table, searched after the byte swap). Nothing to change; the comment on NGH in the tool says so.

**The splash logo (`UB_LOGO=1`, in the shipped DEFS; tools/gfx.py, tools/aerofgt2neo.py, tools/vslogo.png):** the Universe BIOS draws its boot logo from the cartridge's sprite tiles 0x000-0x039 (14 x 4, rows 0x00/0x0e/0x1d/0x2c, palette 7 over a copy in palette 3 two pixels off: an embossed look), with pens 1-4 the BIOS's four golds (the palette read off a stripe-test C ROM, `ub_stripe`). Those tiles are the original's player-plane tiles, so the splash showed plane fragments. Now: the plane tiles move to 0x1cf0-0x1d29 (never referenced by any stage's lookup table: 7,472 of the 16,384 first-half tile numbers are free), the ten stages' first-half lookup tables are patched (3,322 entries; the only writer of tiles < 0x40 into the lookup RAM is the loader at 0x2bbda, checked with `luttap.lua` over the attract and 20k frames of play), and tiles 0-0x39 hold the VideoSystem logo of the attract's first screen (tools/vslogo.png, 64 x 224, composed from the arcade's frame 300 - the emblem and the four words stacked - drawn upright on the rotated monitor, luminance to pens 1-4). The splash: the emblem and "© 1992 VIDEO SYSTEM Co.,LTD." in the BIOS's gold, embossed (`ub_logo/sheet.png`).

**Verification (fz62, p1 4749a483, c1 394f3495, c2 312a550b):** fz62n (no UB_LOGO) == fz61 in every ROM; the DIRECT default == ov10b; the exact == exck8; intro entries vs ov10 253 equal / 10 different; the attract sheet (planes from the moved tiles) as fz61; battery and crash seed below; the device (stock BIOS: the MGL's core boots with the MVS BIOS; uni-bios.rom is on the card, the core's OSD selects it) plays as fz61 (`work/mister_fz62_chk11`). The device's boot capture (`work/mister_fz62_boot`, from the load command) shows a green garbled frame ~6 s after the load, before the BIOS runs: the core's own ROM-loading picture, not the cartridge's.

**fz63 (2026-10-19):** the splash shows the "V SYSTEM" emblem alone, centred (tools/vslogo.png recomposed without the copyright line); the P ROM is fz62's, only tiles 0-0x39 of the C ROMs changed (c1 b6b8360b, c2 878ee712); deployed.

## 39. Full profile matrix of fz63 against the arcade: two players, autofire, boss bombs, every character (2026-10-19)

**The matrix.** Four nations x three seeds (7, 8, 9) x 200,000 frames, two players started together with autofire on both and bombs on every boss (botsel.lua), on fz63 and on the arcade (MAME aerofgt, the same movies): 1.2M frames each side. Every character: the game has one pilot-select cursor for both players (0x8e6c ORs the active players' inputs and writes the nation to both $10d000 and $10d002: P1 gets the nation's first pilot, P2 its second) and a player joining mid-game gets no select (tested: NATION2 in botsel.lua, bot200k_j.txt with P2's start at frame 3000 - the joiner takes the nation's second pilot), so four two-player games cover all eight characters and mixed nations do not exist. Tools: natsum.py (nation/stage), the new secsum.py (sections: a stage id and a 600-frame stretch of it from the stage's start, or its boss fight), botsum.py (boss fights, lost logic by active-object bin), seven 3,000-frame cycle profiles (runfp.sh with map63x.txt, the densest window of each stage from the seed-7 games: pr63_nf/ci/co/rw/de/ba/fi), the overrun-site probe (ovtap.lua, OVR_DIAG build fz63o, nation 3, 100k frames), and a deterministic attract-mode A/B (lag2 over attract.txt, 12,000 frames) of fz57/59/61/63. No reboot in the 12 runs.

**Totals (lost logic conversion / arcade; late = sets shown a slot late, drops = frames a column short, overruns = commits past the deadline, per 600k frames):**

| nation | total | boss fights | late% | drop% | overruns |
|---|---|---|---|---|---|
| 0 (F-18) | 3.54 / 3.31 | 4.05 / 4.22 | 9.8 | 0.18 | 17 |
| 1 (FSX) | 5.37 / 6.12 | 5.39 / 7.65 | 12.2 | 0.09 | 9 |
| 2 (Viggen) | 7.10 / 8.81 | 15.62 / 23.34 | 14.1 | 0.31 | 12 |
| 3 (AV-8) | 7.03 / 7.69 | 14.38 / 15.31 | 13.5 | 0.93 | 99 |

Per stage (conv / arcade): nation 0 cities 5.84/7.36, coast 2.07/3.34, bases 2.19/3.07, desert 6.42/6.77, ocean 3.84/5.86, runway 4.77/3.93, final 1.63/0.63; nation 1 night fleet 9.13/7.54, coast 2.86/5.84, bases 2.61/4.51, desert 6.77/7.95, ocean 5.12/6.97, runway 7.51/8.54; nation 2 night fleet 7.91/7.40, cities 9.49/14.11, bases 4.09/5.30, desert 8.33/12.49, ocean 11.45/11.01, runway 12.39/14.07; nation 3 night fleet 7.01/6.43, cities 8.20/10.10, coast 5.83/6.03, desert 9.83/9.28, ocean 7.26/8.42, runway 8.56/10.28, final 3.35/6.30. (fz59's matrix read 2.30/3.90/5.71/5.71: the games diverge between builds - deaths, respawns - and the per-seed lost figures scatter by +-2 points; the attract A/B below is the controlled measure.)

**Sections (pooled over nations; conv / arcade lost logic, objects conv / arcade):** the conversion is ahead in every section of the cities (t001 10.4/14.8, t002 16.3/18.8, boss 6.8/11.2), coast (t005 5.9/8.5, boss 7.9/11.2), bases (t005 5.3/8.5, t006 8.0/12.1), desert (t002 13.1/15.7, t003 14.0/14.7, boss 11.8/14.9), ocean (t004 13.0/16.4, boss 11.8/15.4), runway (t004 8.7/10.7, boss 11.4/16.0) and the final; behind in the night fleet's dense tail, t008-t017 (t009 24.4/20.6, t010 20.0/18.7, t011 18.8/16.0, t012 14.4/11.2, t014 10.2/7.4, t016 7.8/5.0) and its t004-t005 (5.0/4.3, 6.1/3.5). Per nation the worst (>= 3,000 frames each side): nation 1 night fleet t016 9.7/4.4, t009 25.0/20.2, t017 8.4/3.7, t010 24.3/19.9; nation 2 night fleet t016 8.8/4.1, t011 17.6/13.3; nation 3 desert boss 20.4/16.4, night fleet t005 6.0/2.1; nation 0 desert boss 9.3/5.7. Behind every such section the conversion's games carry more objects (night fleet t016: 37.9 vs 30.6; t009: 54.6 vs 49.4).

**At equal load (lost logic by active-object bin, conv / arcade):** cities and desert ahead in every bin of every nation (cities n2 40+: 9.6/16.4, 50+: 21.6/27.0, 60+: 32.2/37.9; desert n1 40+: 5.8/10.5, 50+: 19.8/19.0); the night fleet ahead to 40 objects and behind above (n1 40+: 8.7/10.6, 50+: 22.8/21.4, 60+: 32.5/30.5; n3 50+: 20.1/18.1, 60+: 29.9/27.2), and the conversion's night fleet games spend more frames at 50+ (36k vs 30k, n1). So: one real CPU deficit, the night fleet at 50-70 objects, 1-2 points; the rest of the "behind" sections is play divergence. In the 0-10 object frames (select, map, the cuts) the conversion loses 6-8% against the arcade's 2-5%.

**Bursts.** Runs of 5 or more consecutive lost logic frames: the conversion 26-42 per 200k-frame game, the arcade 0. Every one is 6 frames long and lands 2-3 frames after the stage index changes (nact 0): the scene cut - both layers cleared and reconverted (42 columns), the palette, the game's own map writes. The arcade's longest bursts are 4 frames, at its stage ends (its own tilemap rewrite). Runs of 3-4: comparable (46-73 vs 71-92 per game).

**Drops and overruns.** Drop frames per 600k: 1081 / 558 / 1828 / 5586 (nations 0-3); concentrated in the desert boss (1908 pooled), the coast boss (1083), the ocean boss (747), the cities' second stretch and boss (839, 506), the night fleet's t009-t011 (680) - the ring's 338-column floor under the bosses' bullet spreads. Nation 3 stands out (0.93% of frames; 4.4% in its boss fights) with its 99 overruns (cities 36, runway 20, final 16, coast 13; 83 of 99 in boss fights). Overrun sites (nation 3, 100k frames, 13): 8 with the flip as the last passing check (the commit's tail 2-6 lines past the deadline in a heavy frame), 2 at the slot scheduler, 2 in the tilemap conversion.

**Profiles (busy frames of the seven densest windows, cycles per frame; the budget 200,000, the arcade's own frame 163,000):**

| window | game logic | collision (gx) | records | pass control (fz_go/due/anch/fin) | pass ctl | shapes | bg | pal | flip+reclaim | sched/vid/other | total | over 200k |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| night fleet (n1, 27.6% lost) | 61.7k | 23.9k | 36.7k | 16.1k | 9.5k | 19.0k | 10.2k | 2.6k | 4.8k | 11.3k | 199.9k | 54% |
| cities (n2) | 59.4k | 33.9k | 35.7k | ~16k | 8.9k | 18.6k | 6.6k | 3.2k | 4.5k | 10.5k | 197.9k | 55% |
| coast (n3) | 60.4k | 31.2k | 37.5k | ~16k | 9.0k | 15.4k | 6.7k | 4.0k | 4.7k | 12.4k | 197.6k | 52% |
| runway (n0) | 64.0k | 25.6k | 37.2k | ~16k | 9.5k | 16.6k | 5.6k | 3.4k | 5.1k | 10.6k | 195.2k | 49% |
| desert (n0) | 61.9k | 19.2k | 36.7k | ~16k | 10.3k | 17.8k | 8.8k | 5.3k | 5.1k | 10.4k | 193.8k | 51% |
| bases (n0) | 60.9k | 25.0k | 35.0k | ~16k | 8.5k | 13.5k | 9.8k | 5.4k | 5.0k | 10.1k | 189.4k | 44% |
| final (n1) | 59.8k | 27.3k | 35.7k | ~16k | 9.7k | 15.8k | 3.9k | 4.0k | 4.8k | 10.8k | 190.7k | 45% |

(The fine map files the fused pass's control routines fz_go/fz_due/fz_anch/fz_fin under 'diag': 16k a frame, the record round trip's dispatch - ~290 cycles a record, §32's "left on the table".) Late-frame anatomy (cities): 55% of late sets work-limited (demand over the frame by 41k on average), 35% scheduling-limited; the primary excess game logic 165 frames, collision 144, the walk 124, tilemaps 77.

**The build trail, deterministic (attract mode, 12,000 frames, lost / late / drops / overruns):** fz57 630 / 1004 / 188 / 1; fz59 656 / 1077 / 252 / 4; fz61 673 / 1123 / 191 / 4; fz63 673 / 1123 / 191 / 4. fz59 (the HUD overlap charges) and fz61 (the set-scroll placement: hal_bg_hist and two hal_bg_held every commit) cost 7% more lost frames between them in the same scene; the matrix's larger swings are divergence.

**Options for the release, with the measure for each:**
1. The cut hitch (26-42 x 6 frames a game, the only 5+ bursts): with the layer hidden (BG_HIDECLR) the reconversion has no deadline - cap it at N columns a slot while HAL_BG_HID/FX1_CLR is set, so the game keeps its frames and the blackout grows by a few. Measure: bursts of 5+ -> 0; the attract A/B.
2. hal_bg_hist/held: a ring index instead of copying, hal_bg_held only when HAL_SPR_RDY says the shown set is late: ~200 cycles a commit back. Measure: attract A/B 673 -> ~660.
3. The pass control (16k a dense frame): a per-object template (table, flags, routine precomputed per object type) for the record round trip: ~150 cycles x 55 records = ~8k a frame in the night fleet - the one lever that reaches the night fleet's 50-70-object bins. Measure: pr63_nf's BUSY total, the night fleet 50+/60+ bins.
4. Collision (19-34k a frame, the largest HAL item in the cities and coast): a banded pre-test per shot (x-band buckets) that skips pairs the game's own test would reject, in the game's order - exactness by GX_VERIFY. Potential 10-15k a frame in the cities. Risk: the highest; the harness exists.
5. The flip's tail overruns (8 of 13): two more lines of reserve when the flip has more than N heads (its estimate 24 cycles a head + 400 runs short in heavy frames). Measure: ovtap over nation 3.
6. Nation 3's ring pressure (drops 0.93%, 83 of its 99 overruns in boss fights): the AV-8's spread shot draws more columns than the other planes'; the bullet pool takes pair bullets only - extend it to the spread's pieces, or shed by category when the ring is short (shadows and items before shots and bullets). Measure: nation 3's drop frames in the desert and coast bosses.
7. The HUD overlap charges (fz59: +26 lost in the attract A/B): charge the two entry tests at their cost (3 units) and FXU_HOV0 only with yields pending. Small, safe.
8. The 0-10-object screens (select, map: 6-8% vs 2-5%): the tilemap text on the fix layer and the scene loads (tilemap conversion > 15k on 14.5% of the cities' late frames); pre-convert during the black of the cut. Low value: the frames are static.
9. Not worth touching: shapes (13-19k, generated straight-line code), the palette (2.6-5.4k), the HUD (~1k), the bullet pool (2k), the game's own logic (60-64k at 12 MHz against the arcade's 10).

## 40. The release polish, options 1-7 of section 39 (2026-10-19, fz64; the shot pool fz65 measured and left off)

**The measure:** the deterministic attract run (12,000 frames of attract.txt, lag2: lost logic / late sets / drop frames / overruns), then the nation matrix of 39 on the shipped set.

| build | lost | late | drops | overruns | what |
|---|---|---|---|---|---|
| fz63 | 673 | 1123 | 191 | 4 | the release before this pass |
| fz64 | 661 | 1040 | 187 | 0 | options 1, 2, 5, 7 |
| fz65 | 686 | 1104 | 236 | 0 | fz64 + the shot pool (option 6) |

**Option 1, the cut hitch (`BG_CUTCAP=1`, hal/tm.s, hal/bg.s):** a cleared layer's columns are converted at most BG_CAP = 3 a slot (HAL_BG_CAPN counts them down from the clear, HAL_BG_CAPS/CAPF the slot's share) and its verification burst is off (hal_bg_layer_stale's HAL_BG_BURST cleared at a clear, hal_bg_scrub skipped while columns are under the cap: the burst - six columns a frame for twelve frames - was 20-50k cycles a frame for twelve frames after every cut). The 6-frame lost burst at a cut did NOT go: a 60-frame profile across the attract's demo-to-hangar cut (`work/play/fp/cut64`) shows the lost frames 2399-2404 are the game's own cut work - its tilemap clear and rewrite 132-162k cycles a frame, its lookup RAM load 136k - with the HAL's palette conversion (37-45k on a fade frame: hal_pal_convert over every entry) on top; the arcade loses 4 frames in the same place at 10 MHz. What the cap bought is the twelve frames after the cut (bg_conv 130-146k -> 35-45k a frame, the scrub gone) and a blackout 4-5 frames longer (hidden spans 15 and 32 against 11 and 27). The palette conversion on fade frames is the lever left for the cut: 44k a frame on every third frame of a fade.

**Option 2, the scroll history (`BG_SCRRING=1`):** HAL_SCRH is a ring of three with HAL_SCRI its index (hal_bg_hist writes one entry, no copying); the commit's placement (hal_bg_place .lay, hal_bg_l1place) reads this slot's scroll from the ring (hal_bg_scrcur) instead of calling hal_bg_scroll again; hal_bg_held indexes the ring. ~150 cycles a commit back.

**Option 5, the overruns (`SPR_FLIPRES=1`):** the probe (ovtap, OVR_DIAG builds, nation 3, 100k frames: 13 overruns on fz63 and on fz64's first form) places every one at the commit's step 7-8 - hal_spr_work, the sprite conversion's tail in the commit - not at the flip: the flip's check was the last passing one. The first form (two more lines in the flip's own check with 40+ heads) changed nothing (13 -> 13) and was dropped; the switch now adds 2 lines (96 units) to FZ_TAILX, the tail margin the commit's sprite work keeps back. Attract: overruns 4 -> 0; nation 3's 60k-frame run 4 -> 6 (noise at these counts); the matrix below is the measure.

**Option 7, the HUD overlap charges (`FX_HOVCHG=1`):** FZU_HUDT +3 instead of +7, FZU_HHIT +1 instead of +3, FXU_HOV0 charged only with yields pending. (The attract's 26-frame step from fz57 to fz59 is partly back: fz64 661 against fz57's 630 with options 1-2 as well.)

**Option 6, the player shots in the bullet pool (`BP_SHOTS=1`, built as fz65, OFF in the release):** first the diagnosis changed. Nation 3's drops (0.93% of frames, 4.4% in boss fights) follow its bomb presses (41 drop frames per 1,000 in the 150 frames after a press against 2.7 elsewhere; nation 2 17 against 1.4). The presses do fire bombs (bombtest.lua: bomb objects, types $0d/$20/$21, in 311 of the 1,000 frames after the first boss press; the byte the bot reads as the stock, +0x1e, is not the stock - it stays 5 - so the bot presses whenever a boss is up, which is what was wanted), and a nation-3 bomb's frames hold mostly shadows and explosions, not big bomb sprites. An arcade-side column census (colcen.lua: every active object's pieces' widths from the original's tables, nation 3 and nation 1, frames 5,000-30,000) puts nation 3's games at 147 / 222 / 292 sprite columns a frame (p90 / p99 / max) against nation 1's 128 / 159 / 197, with the player shots costing the same in both (types $0e, $0f, $11, $13: one-piece 16x16 or 32x16, 2-3 columns a frame each, ~10 shots a frame): nation 3's drops are the ring's 338-column floor under its heavier scenes (its stage order and bosses), not its plane. The pool was extended anyway, for the ring headroom every set would gain: the tool marks the one-piece, unzoomed, <= 2 x 2-tile descriptors of the shot types (bit 12 of the first word: 156 descriptors; the index's `lsl.w #4` drops the bit for free), fz_rec gives such a record the routine fz_pshot, which at pass time writes an 8-byte pool record (w2 low byte $40, the generic kind) when the pool is on with room and dispatches through fz_disp otherwise, and bp_apply's generic kind writes a 1-2 column x 1-2 tile piece from the lookup run with the flips (the second column blank for a one-column piece). It draws right (`work/play/fh/shotsnap65`) and loses: attract lost 686 against 658 (fz65n), drops 236 against 189; nation 3's 60k run drops 746 against 579 and overruns 270 against 6, 72 of 100 probed overruns first past the deadline at the commit's sprite tail. The pool's fixed 64 columns, taken whenever six poolable pieces are seen in a walk - always, with two autofire players - cost the ring more than the ten shots' columns it removes, and the sets wait for columns into the commit. The code stays under its switch, off; a pool sized to its content (and the ring sized to the rest) is the redesign it would need.

**Option 3, the record template:** withdrawn. The 'diag' category of the fine profiler map (16k a dense frame in 39) was the fz_* routines left unfiled: with them filed (fmap_fine.py: fz_pd_*/fz_pdh_* -> pass pieces, fz_fast*/fz_disp/fz_next -> dispatch) a 600-frame night fleet profile reads pass pieces 3.4k, dispatch 3.2k, the pass control proper (fz_go/fz_due/fz_fin/fz_anch) 2.3k a busy frame. There is no 16k round trip to template away; the record build's prologue reads the object's own bytes (flags, flips, colour, zoom, table), which a per-type template cannot stand in for exactly.

**Option 4, the banded collision pre-test:** not implemented in this pass. The scan (hal/gx.s gx_scan) already hoists the shot's bounds clipped to the playfield and rejects a candidate with two compares (93% fail on x); what is left is the visit of every slot of three pools per shot (~2,600 slot visits a frame at ten shots). An index of the targets by x band, built once a frame in slot order and merged over the two bands a shot can span, would cut that to ~100 tests - keeping the first-hit order, the end state (d7 = -1, a2 past the slots, X from the last slot's subq) and the hit code's side effects on later shots. ~10-20k a frame in the cities; the GX_VERIFY harness is the check. A session of its own.

**The matrix on fz64 (the shipped set; conversion / arcade lost logic, then the conversion's overruns and drop% per 600k frames; fz63's in brackets):** nation 0 3.53 / 3.31 (3.54), overruns 4 (17), drops 0.17% (0.18); nation 1 5.01 / 6.12 (5.37), 3 (9), 0.10% (0.09); nation 2 6.99 / 8.81 (7.10), 4 (12), 0.48% (0.31); nation 3 6.99 / 7.69 (7.03), 38 (99), 1.02% (0.93). Boss fights 3.53 / 4.22, 4.84 / 7.65, 19.86 / 23.34, 14.13 / 15.31 (fz63 4.05, 5.39, 15.62, 14.38). Night fleet 8.35 / 7.54, 6.93 / 7.40, 6.93 / 6.43 (fz63 9.13, 7.91, 7.01); at 50+ objects 23.2 / 21.4, 21.7 / 20.0, 21.1 / 18.1 - the one deficit stands, 1.7-3 points. Plain battery 4.10% lost (fz61 4.14), late 10.41% (10.49), drops 705 (435), overruns 3 (8). Bursts of 5+ lost frames 23-37 a game (unchanged: the game's own cut work). No reboot in the 12 + 9 games, the crash seed, the entries run (262 equal / 5 different against ov10, no reboot), the attract. fz64 p1 7c612d9e deployed (fz63's p1 backed up as 538-p1.p1.fz63_4749a483; the C ROMs are fz63's), the device trial clean.

## 41. The profile matrix as a tool (2026-10-19)

`work/play/fp/matrix.sh <romdir> <name> [nations] [seeds] [frames]` runs the matrix of 39/40 - one two-player game per nation and seed (botsel.lua: both players started together, autofire on both, a bomb press 2 frames in every 24 while a boss is up), F frames each, all in parallel - into work/play/fp/bl_n<N><name>_<seed>/ (lag.txt + bot.txt), then prints `matrix_report.py <name> orig <nations> <seeds> [prev]`: reboots and per-seed lost/late/drops/overruns/bursts, the nation-stage table against the arcade (natsum.py), boss fights and lost logic by load (botsum.py), the sections where the conversion is behind (secsum.py), the night fleet by load bin, and with [prev] the previous build's totals. `ORIG=1 sh matrix.sh - orig` makes the arcade's reference runs (bl_n<N>orig_<seed>; done once, 2026-10-19: the same movies on MAME aerofgt). Defaults: nations 0-3, seeds 7 8 9, 200,000 frames (~25 min on 16 cores). A quick check: `sh work/play/fp/matrix.sh work/out_X X "1 3" 7 60000`. The per-stage figures swing by +-2 points between builds (two-player games diverge); the deterministic attract A/B (`sh work/play/fp/runlag.sh work/out_X work/play/fp/att_X 12000 work/play/attract.txt`, then lost/late/drops/overruns from its lag.txt) is the controlled measure; the matrix is the measure against the arcade.

## 43. Design: the banded collision index (option 4 of section 39; for another session)

*(Built in section 45: the trace answered point (4), and the bands themselves did not pay - the index that shipped as `GX_BAND=1` keeps the targets with their x extents.)*

**What runs today (hal/gx.s, GX_SCAN=1):** shot_collide (the game's 0x2a142: a0 = the shot, d2 its damage, a3 the playfield bounds) tests the shot against every active target of three object pools - 0x1019c0 (0x18 slots), 0x1040c0 (0x10), 0x1052c0 (0x30) - in slot order, with the overlap test 0x2a1f6 (x block first, 0x2a22c the y block) and a second hitbox test 0x2a26a (76(a2): 92/88); a hit ends the whole scan through 0x2a1c0 with C set (its rts to the bsr); no hit ends at 0x2a1b8 with d0 = 0, C clear, a2 past the last pool, d7 = -1 and X as the last slot's `subq.w #1,d0` left it (0x2a602's random number uses roxl: X matters). A target is a slot whose first byte has (b0 & $31) == 1. gx_scan does this exactly, faster: the shot's x range clipped to the playfield once (d4/d5), two compares a candidate instead of four, eight slots a turn over the empties. 93% of candidates fail on x. The bomb pieces' entry 0x2a0e8 keeps the original loop at 0x2a18c (gx_col); the twin scan 0x2a088 (gx_col2) is the other caller.

**The cost left:** every active slot of the three pools is visited per shot: at ten shots a frame and ~45-55 active objects, ~500 candidate visits a frame plus the empties' scans (~2,600 slot visits), 19-34k cycles a frame in the matrix's windows (the cities and coast the most), the largest HAL item after the record build.

**The index.** Once per game frame, before the first shot_collide of the frame (detected by a frame counter kept at the collision entry: HAL_FRAMES or the game's vblank count 0x109a8e), build a list of targets by x band: 16 bands of 32 pixels over the playfield's x range (the bounds table at 0x50858 + 0x178, left/right ^ $8000), each band a list of slot addresses in SLOT ORDER (pool 0x1019c0 first, then 0x1040c0, then 0x1052c0, ascending). A target spans the bands from (left - bandx0) >> 5 to (right - bandx0) >> 5 (its two hitboxes: use 80(a2)/84(a2) and 88/92, the union); it is listed in each band it spans (duplicates across bands; a target is at most 2-3 bands wide). Storage: 16 x 64 words at FXS or the HAL scratch, plus a count per band. Build cost: ~100 targets x ~60 cycles = 6k a frame (the scan of 88 slots for the (b0 & $31) test is part of it, as today's first visit).

**The query.** For a shot: its x range clipped to the playfield (d4/d5 as today) -> the bands b0..b1 it spans (1-2 bands, a 32x16 shot never more than 2 at 32-pixel bands); walk the band lists in a merge by slot address (two cursors, the lower address first; equal addresses once), and for each slot: re-check (b0 & $31) == 1 (a hit on an earlier shot this frame may have changed it: 0x2a1c0's code writes the target), then the original's y block (0x2a22c) with the registers as the x block leaves them (d0, d1, d3, d6: gx_scan's .cand sets them), then the second hitbox. The first hit returns through 0x2a1c0 as today. No hit: the end state as today (d0 = 0, C clear, a2 = 0x1052c0 + 0x30 x 0x60, d7 = -1, X = the subq of the last slot's (b0 & $31) - 1: computed from the last slot's byte, 0x1052c0 + 0x2f x 0x60).

**Exactness, point by point:** (1) slot order: the merge yields targets in ascending address = the original's order within and across the three pools (the pools are ascending in memory and scanned in that order). (2) The x pre-test: a target not in the shot's bands cannot overlap in x (bands cover the hitboxes' union), so skipping it is what the original's x block would have done - no side effects on a failed test (verified by the GX_XPRE work: the failed block only sets d0/d1/d3). (3) Targets changed by a hit earlier in the same frame: the candidacy re-check at query time; a hit does not move a target (the handlers run in the main loop, before the collisions). (4) Targets spawned or moved between the index build and a later shot in the same frame: none - all collisions of a frame run in one stretch of the game's frame (0x2a142 from the shots' handlers? verify with a trace: if shot_collide is called from each shot's handler during the main object loop, targets CAN change between calls (an earlier handler moves or spawns a target) and the index must be rebuilt or invalidated per call - the design then needs a cheap "dirty" test, or the build per shot (6k x 10 = 60k: no gain). THIS IS THE FIRST THING TO ESTABLISH: trace the callers of 0x2a142 over a dense frame (a PC tap at 0x2a142 and 0x19976's handler dispatch) and whether any handler between two calls writes a target's position bytes 80-95 or b0.) (5) X: as today's end code. (6) The second hitbox 76(a2): both hitboxes in the band assignment.

**Verification:** GX_VERIFY as for GX_SCAN - the indexed query and the original 0x2a1f6/0x2a26a tests over every slot both run, the hit slot and the end registers compared, a difference counted in HAL_GX_MISS; the by-round entries (work/play/fh/entries.lua) and the nation matrix as the regression; the arcade's own hit outcomes are the reference (the game's score/kills by frame: botsel's bot.txt columns, identical movies).

**Expected gain:** 500 candidate visits -> ~100 band-list visits a frame, the 2,600 empty-slot visits gone, ~6k for the build: 19-34k -> ~10-14k a frame, i.e. ~10-20k a frame in the cities and coast, ~5% of the budget on the frames that matter.

**Risks:** point (4) above (if the collisions interleave with the handlers, the index is invalid: then only a per-call incremental scheme works, and the gain is doubtful); the band width against the largest target (a boss hitbox spanning many bands is listed in each: fine); the state size (16 x 64 x 2 bytes); the twin scan gx_col2 and the bomb pieces' entry are separate callers to leave alone at first.

**Files:** hal/gx.s (gx_scan, .pool, .cand; GX_VERIFY's gxsv84/gxsv92), tools/aerofgt2neo.py's GX_* DEFS flags (GX_SCAN hooks the jmp at 0x2a142), work/play/fh for the probes (a PC-tap census of 0x2a142's callers first), the matrix tool (AUDIT 41) and the attract A/B for the measure.

## 42. Option 6 again: the bullet pool sized to its content (2026-10-19, fz66; not shipped)

**The mechanism (`BP_SIZED=1`, hal/fx.s bp_poll, hal/fz.s):** the pool's slots BP_NV (8..BP_N by eights) and its lowest column BP_LOV replace the constants; the size is chosen at each turn-on from the demand (BP_WANT, else the walk's pool pieces + 2), the chains, keys and RING_TOP set for that size; while on, every BP_SIZEW = 64 walks the demand's maximum since the last sizing (BP_DMAX) is rounded to a size and, when it differs, the pool goes off and comes back at the new size (`BP_SIZEONCE=1`: sized at turn-on only). The records' room is FZ_PBL (the end FZ_PBE stays the area's: the count is derived from it - the first build moved FZ_PBE and every list reported 16-24 phantom records, drawn as garbage slots at every flip: the state trace `bpstate.lua` showed BP_SHOWN stuck at 16; found and fixed before the measurements below).

**Measured (attract A/B lost / late / drops / overruns; nation 3 seed 7 60k frames lost% / drops / overruns):**

| build | pool | attract | nation 3 |
|---|---|---|---|
| fz64 | fixed 32 slots, pair bullets | 661 / 1040 / 187 / 0 | 6.52 / 579 / 6 |
| fz66p | sized, resized every 64 walks, pair bullets | 680 / 1110 / 0 / 0 | 6.65 / 713 / 2 |
| fz66q | sized once at turn-on, pair bullets | 679 / 1092 / 329 / 0 | 8.42 / 304 / 6 |
| fz66 | sized, resized, pair bullets + the player shots | 711 / 1135 / 311 / 5 | 8.68 / 893 / 178 |

Sizing removes every drop of the attract's desert-boss scene (a small pool leaves the ring 48 more columns) and loses in play either way: resized, the off/on transitions (the pool unavailable while the ring drains below its new top, its pieces the general way) cost lost frames and the drops rise; sized once, the pool stays at the size of its first demand (8) and the boss's 35 bullets go the general way (lost 8.4%). With the shots in it the overruns return (178 in 60k; 82 of 100 probed first past the deadline at or after the flip): the pool's slots are assigned in record order, so a shot's slot changes every frame, its tile key never matches and every flip rewrites every slot's tiles in the vblank. The fixed pool stays; the switches stay off.

**What a working shot pool needs (for a later session):** slots assigned per object identity (the record carries the slot; keys then match across frames and the flip writes a slot's tiles once), the pool/ring split moved at the commit without an off/on cycle (the ring's top adjusted when the columns above it are free), and the size tracking the demand with hysteresis (grow at once, shrink after ~200 quiet walks). Until then the ring floor is best addressed by shedding at the set level (AUDIT 39's option 6b).

## 44. Option 6 a third time: the bullet pool with stable per-object slots (2026-10-19, fz67/fz68; not shipped)

**The mechanism (`BP_STABLE=1`, wants `BP_SIZED=1`; hal/fx.s bp_apply_st, bp_poll's .s2 grow/shrink, hal/fz.s fz_bul and fz_pshot):** a pool record names its object (the index (address - G_DX_OBJ1) >> 5, 0..254, from the bp_kidx ROM table at record time) and the flip keeps a slot per object: BP_SLOT[255] (object -> slot + 1), BP_OWNR[32] (slot -> object + 1), BP_OWNM (the owned slots, a mask), BP_KEY per slot (w2:w3 of the tiles it holds). The flip (bp_apply_st, in the real vblank) walks the set's pool records once: the object's slot or the lowest free one (none free: the record is not shown), the slot's SCB3/SCB4 written from the record, its tiles only when the key changed; then the owned slots not in the set are freed and hidden (SCB3 0). The record is laid out at pass time as the flip writes it: w0 = SCB3 ((496 - y) << 7 | rows), w1 = SCB4 (x << 7 | the index's low 7 bits), w2 = the SCB1 attribute (palette with NPAL_SPR, flips in bits 1/0) | $40 for the generic kind | bit 7 = the index's bit 7 | bit 2 = columns - 1, w3 = the lookup index. The generic kind (the one-piece shots, `BP_SHOTS=1`) is at most 2 x 2 tiles: no multiply, the second column blank (BLANK_TILE, transparent) for one-column pieces. The pool grows at once when the demand (BP_SEEN per walk) exceeds the size (BP_GROW; bp_top tells the ring to start no set above the new bottom, bp_clear waits until no set reaches it, then the new columns are chained and cleared) and shrinks after BP_SHRW=200 walks when the window's most rounds a step under the size and the slots above are free - no off/on cycle, so the ring is never drained first (section 42's loss). Cost at the flip's deadline check: 350 a record + 800 (bp_cost).

**Found on the way (each cost a build):** (1) the sweep loaded the owner byte into a register with a stale high byte, so it cleared the wrong map entry and the object -> slot map kept stale entries: every record then landed on a shared slot and rewrote its tiles each frame (13 lines a flip at 7 records; a write tap on BP_OWNR showed no writes at all). (2) The sweep's loop tested bclr's flag (the bit's old value) for "mask empty" and spun forever once the last unseen slot was freed (the fz68 "reboots" of the first fixed build). (3) The tile writes went to SCB1 of column (slot) instead of column (SPR_PT - 1 - 2 slot): the background strips' first rows (columns 1-17) got the shots and a black BLANK row - a 16-pixel black band with the shots at the top of the screen (work/play/fh/fliptap.lua, bpstate2.lua, owntap.lua; the picture check work/run_cmp3.sh + the scratchpad pixsheet.py found it; the VRAM dump tools/neovram.py confirmed the columns). (4) OVR_DIAG's RAM: a stamp at $d00f44 landed on the scheduler's HAL_SCH_BUSY/YLD/RES and wrecked the game - the flip stamps (OVB 0-2, OVB_ON) now live in OVD_S.

**Measured, the flip's cost (fliptap.lua on the OVR_DIAG build, nation 3, 10k frames; the flip = OVT 0..1 = the set flip + the HUD flip + the pool apply):** fz64 4,100-5,400 cycles; the stable pool before the record pre-layout ~550 a record + ~1,000 for the first (the identity decode, SCB3 from y and the height, the key compare as two words: ~520 cycles a record without a tile write); after it (fz68) ~280 a record + ~560 for the first. The tile keys change in only 8% of the object-frames (bpstate2.lua: 19 shot objects, 22,756 object-frames, 1,636 changes; the long-lived shots 50/51/66/67 change once in 2,000 frames) - the per-record bookkeeping, not the tiles, is the vblank cost. The first version's estimate (220 a record) overran at the yield after the flip (every overrun of ov67_n3: site 2, 2-4 lines past); 620 a record for the shots deferred the flip into lateness instead (fz67 attract: 7,809 late sets of 12,000 frames; nation 3: 94% late in the matrix).

**Results (attract A/B lost / late / drops / overruns; the matrix 4 nations x 3 seeds x 200k, conversion lost% per nation with the arcade's 3.31 / 6.12 / 8.81 / 7.69, then overruns and drop%):**

| build | pool | attract | matrix lost% n0..n3 | overruns | drop% n0..n3 |
|---|---|---|---|---|---|
| fz64 (the release) | fixed 32 slots, pair bullets, no identity | 669 / 1040 / 187 / 0 | 3.53 / 5.01 / 6.99 / 6.99 | 4 / 3 / 4 / 38 | 0.17 / 0.10 / 0.48 / 1.02 |
| fz67p | stable, pairs (the two-word SCB path, estimate 380 + 800) | 683 / 1063 / 175 / 2 | 3.31 / 4.77 / 6.94 / 7.36 | 1 / 3 / 3 / 178 | 0.18 / 0.07 / 0.37 / 0.92 |
| fz67 | stable, pairs + shots (estimate 620 + 1000) | 477 / 7809 / 93 / 7 | 3.70 / 5.57 / 8.84 / 4.51 (94% late) | 6433 / 1291 / 6406 / 482 | 0.30 / 0.13 / 0.51 / 0.01 |
| fz68p | stable, pairs, the records pre-laid (estimate 350 + 800) | 681 / 1059 / 176 / 2 | 3.31 / 4.77 / 6.94 / 7.40 | 1 / 3 / 3 / 147 | 0.18 / 0.07 / 0.37 / 0.95 |
| fz68 | stable, pairs + shots, the records pre-laid | 733 / 1118 / 186 / 10 | 4.45 / 5.62 / 8.86 / 8.22 | 5731 / 2423 / 5173 / 5071 | 0.32 / 0.18 / 0.69 / 0.66 |


**Verdict.** The pool with the shots is worse in every nation, by 0.6-1.9 points, with thousands of overruns: the commit's sprite tail (hal_spr_work after OVT 7) runs 25 lines over in the heavy frames once the pool is large, not the pool apply itself (ov68_n3: 121 of 224 overruns passed hal_bg_convert's check last, the flip at 1 line). The pairs-only stable pool equals fz67p/fz68p on nations 0-2 (identical runs: the pair pool holds nothing there) and its 0.2-point gain over fz64 there is the SIZED pool's smaller footprint (8 slots: 48 ring columns the fixed pool takes), while nation 3 - the only nation with pair bullets - loses 0.4 points and takes 147-178 overruns, 20-26 per 60k frames, nearly all at the flip's deadline check (the pool's estimate still under its cost by 2-8 lines; ov68p_n3_7/8). fz64 stays the release. The two knobs left untried: the estimate raised to ~450 a record + 1200 (overruns -> lates, the matrix would say which costs more), and the inverse size policy (start at 32 as fz64, shrink when idle, so a boss's burst never waits for the ring to drain below a new bottom - the sized pool's structural loss in nation 3). Neither can change the conclusion for the shots: a pooled sprite costs vblank time the ring path spends outside it, and only a sprite that is never redrawn would pay.

**Files:** hal/fx.s (bp_apply_st, bp_stclr, bp_clear, bp_kidx, bp_cost; BP_SLOT/BP_OWNR/BP_OWNM/BP_SEENM/BP_QMAX/BP_QCNT/BP_GROW at FXS+$2b0..$3df; the OVB stamps), hal/fz.s (fz_bul's and fz_pshot's pool records), hal/hal.s (BP_STABLE, OVD_BP/OVB_ON), hal/spr.s (OVB 0-2 round the flip); builds work/out_fz68 (pairs + shots), out_fz68p (pairs), out_fz68o/fz68po (OVR_DIAG), out_fz68n == fz64; matrices work/matrix_64L/67p/67/68p/68.txt; probes work/play/fh/fliptap.lua + fltsum.py, bpstate2.lua, owntap.lua, cyctap.lua (no events), ov67_n3/ov68_n3/ov68p_n3_*; pictures work/c3_fz64/fz67/fz67p/fz68/fz68p, the VRAM dump work/vr_fz68.

## 45. The collision index, built (2026-10-20, `GX_BAND=1`; AUDIT 43)

**Point (4) first: the shots' calls do not interleave with the targets' handlers (work/play/fh/gxtrace.lua, the arcade, botsel.lua 2P autofire, every nation, frames 3,000-60,000).** shot_collide (0x2a142) is called from the shots' own handlers in the main object loop; the shots live in the slots between the first target pool and the second (0x1022c0..0x1040c0: 91-100% of the calls - nation 0's and 2's other callers are objects in the pools, 0x101xxx and 0x104xxx, and the 36-72 bomb calls). Over 710,000 call pairs inside a pass, the target set (candidacy, the x words 80/84/88/92, 76) between two calls from the shot region: **no target gained, none moved, no target-pool handler ran between them**; the one change is a target the hit code took (bit 5: 2,524 losses), which the query tests again. So one index a pass is exact for the shot region, and the calls from elsewhere keep gx_scan's scan.

**The probe's two lessons:** (1) a MAME read tap on an instruction's FIRST word fires during the instruction before it (the 68000's prefetch: PC is the previous instruction's) - tap the second word of a longer instruction, where PC equals that word; (2) the arcade's work RAM is at 0xfef000 (game 0x100000 = 0xfef000, the harness map), not 0xff0000. Also: this MAME's Lua has no cycle counter (`totalcycles` nil, no `total_cycles`): a per-call cycle probe is impossible - the per-frame profiler (runfp.sh with a map) is the cycle measure.

**RAM.** The index needs per-pass storage, and the RAM is full: backup RAM 0xd00800-0xd00bff is the HAL's variables, 0xd00c00-0xd00dff its stack, 0xd00f00-0xd00fff the diagnostics and the timing model; the sprite RAM tail is used; a zero-at-sampling survey (work/play/fh/ramfree.lua, from frame 1,500: the boot RAM test fills everything) finds only game RAM that is zero by chance (empty object slots, tile RAM). The idle stack's deep end is free, as G_TRAMP's note says: a write tap (ramfree.lua WATCH, 3 x 40k frames, nations 0/2/3) found **no write to 0x10fc30..0x10fdaf after the boot**, while the tap on the stack's top (0x10ffc0..) counted 120,126 writes in 8,000 frames - the idle stack's live depth is under 64 bytes; the non-zero words below are boot leftovers. The index takes 0x10fc40..0x10fd9a.

**Three versions, measured by the per-frame profiler on matched windows** (same-route runs: botsel.lua SEEDSET=6f48; nation 3 cities 1,500-4,500 and coast 6,500-9,500, nation 2 night fleet 5,800-8,800; each profile with its own build's map, split so gx_scan is one category and the index code another - work/play/fp/map64g.txt, mapgb3g.txt; gxcmp.py joins bot.txt's shots): collision cycles a frame (gx_scan + the index; the object loop's scanner, ~7.7k, apart).

| build | cities | coast | night fleet | the index code |
|---|---|---|---|---|
| fz64 (gx_scan: every slot a call) | 13.6k | 18.2k | 17.8k | - |
| bands as AUDIT 43, bit masks (88 bits a band pair, 96 bytes) | 13.9k | 16.9k | 12.4k | ~12k |
| bands, byte lists (pair lists, unrolled build) | 11.5k | 10.4k | 9.7k | 8.7-10.6k |
| **extent list (shipped as GX_BAND=1)** | **8.7k** | **8.6k** | **8.8k** | 7.6-7.7k |

The masks lost on the walk (11 bytes and their bits a call: ~1.2k, near gx_scan's ~2.8k); the band lists on the build (a target's two bands and its ~2.8 pair-list entries: ~600 cycles a target, ~6k a build). The bands buy nothing a cheaper test does not: a target whose x extent (the least and largest of its x words) misses the shot's clipped range cannot pass either hitbox's x block, so the list of targets with their extents, walked in slot order, rejects an entry in ~50 cycles and needs neither bands nor the bounds table. A call tests 0.5 entries again on average (936k calls, 475k tests).

**The mechanism (hal/gx.s section 7; GX_SCAN's gx_scan branches to gx_band for a0 in the shot region; gx_upd counts the main loop's passes):** gx_bbuild, at a pass's first indexed call: 88 inline slot tests (GXBS: move.b, beq, andi, subq, bne - ~22 cycles an empty slot, ~42 a non-target), each target's (min x, max x, index x 4) appended, more than 56 targets -> the pass's calls scan (never seen: 0 in 240k frames). gx_band's query: the entries in slot order, those in range tested again for candidacy, then gx_scan's x compares and the original y blocks (0x2a22c, 0x2a2a0); a hit through 0x2a1c0 with d7 from the gx_bd7 table (the dbra's count, a word); no hit: the end state of gx_scan (d0 0, C clear, a2 past the last pool, d7.w -1, X from the last slot's subq) and d1/d3 as the slots' last target left them - the last one tested, or, when the last live target was skipped, its failed x block's values (the second hitbox's with 76 set) computed from its words.

**Exactness (GX_VERIFY = AEROFGT_GXCHECK=1):** gx_bref runs the original tests (0x2a1f6, 0x2a26a) over every slot first, without the hit code; the indexed call's hit slot, or its d1/d3, compared, a difference counted in HAL_GX_MISS. 4 nations x 60k frames: **0 misses in 936,007 indexed calls** (work/play/fh/gxbv.lua; gx45/gbv3_n*). The check catches what it should: a build whose extents ignore the second hitbox - 1,625 misses in 30k frames (gx45/gbm3); the band version with its lists one band short - 598 in 20k.

**Results.** The deterministic attract A/B (12,000 frames): lost logic 658 -> **491**, late 1,037 -> 864, drop frames 189 -> 197, overruns 1 -> 1 (desert 22.1 -> 17.1%). The matrix (4 nations x 3 seeds x 200k, 2P autofire + boss bombs; work/matrix_gb3.txt), lost logic conversion / arcade:

| nation | fz64 | GX_BAND | arcade | boss fights (GX_BAND / arcade) | overruns fz64 -> GX_BAND | drop% fz64 -> GX_BAND |
|---|---|---|---|---|---|---|
| 0 | 3.53 | **1.81** | 3.31 | 2.52 / 4.22 | 4 -> 2 | 0.17 -> 0.14 |
| 1 | 5.01 | **2.80** | 6.12 | 2.15 / 7.65 | 3 -> 2 | 0.10 -> 0.08 |
| 2 | 6.99 | **5.09** | 8.81 | 12.98 / 23.34 | 4 -> 2 | 0.48 -> 0.52 |
| 3 | 6.99 | **5.58** | 7.69 | 12.07 / 15.31 | 38 -> 22 | 1.02 -> 0.82 |

No reboot in the 12 games. The conversion is ahead of the arcade in every nation now (nation 0 was behind), and the sections behind the arcade fell from 63 to 16; the night fleet by load bin is level or ahead to 60+ objects (40+: 5.4-6.4% against 8.3-10.6%), nation 3's 70+ bin (948 frames) still behind (35.8 / 31.8). The first matrix of the bit-mask version (work/matrix_gb.txt) had nation 3 at 7.60 - the measured cost, not noise, was the reason to go on.

**Off: byte-identical to fz64** (p1 7c612d9e, every file's SHA1 the README's). On: p1 md5 ab82be55.

**Shipped as fz69 (2026-10-20): GX_BAND=1 joins the release DEFS** (work/out_fz69; only 538-p1.p1 changes: CRC c2531b64, SHA1 f5d797f8...; the README's table rebuilt from its own command, 9 of 9 files match). Picture check (work/run_cmp3.sh -> work/c3_fz69, beside c3_fz64): movie7 10,000 and attract 6,000 frames, HUD dropouts 0 on both, overruns 0, late sets 654 / 486 (fz64 758 / 569), the contact sheets clean (the black runs are the boss-kill fade to the mission map, as fz64's at its own frames). MiSTer: deployed over fz64 (backup 538-p1.p1.fz64_7c612d9e); chk11 trial clean (work/mister_fz69_chk11/sheet.png: title, attract with the HUD, two coined games, continue, the mission map), audio -35.3 dB (work/vid/fz69_chk11.mkv); the 22-minute open-loop Japan session (/tmp/play_jp.sh, work/vid/fz69_play.mkv, sheet work/vid/fz69_play_sheet.png) played through the ship, city, river, runway, desert, ocean-fleet, base and jet stages to the aliens mission with no reboot and no music gap (musicgap.py: only the end silence).

**Files:** hal/gx.s (section 7: gx_band, gx_bbuild, gx_bcand, gx_bslot, gx_bd7, gx_bref; gx_scan's branch and gx_scanp; gx_upd's GXB_PASS), hal/hal.s (GX_BAND); probes work/play/fh/gxtrace.lua (point 4, the arcade), ramfree.lua (the RAM survey and WATCH), gxbv.lua (the check's counters); work/play/fp/gxcmp.py, the maps map64g/mapgb3g.txt, profiles pg64_*, pg3_* (and pg2_*, pggb_*: the band versions); builds work/out_gb (GX_BAND), out_gbv (+ GXCHECK), out_g0 (off); the matrices work/matrix_gb3.txt, matrix_gb.txt; the attract runs work/play/fp/att_64r, att_gb3.

## 46. Dense scenes in nation 3: where fz69 stands, where a dense frame goes, the plan (2026-10-20; analysis, nothing built)

**Where nation 3 stands (fz69's matrix, work/matrix_gb3.txt).** Ahead of the arcade in total (5.58 / 7.69), in the night fleet (5.64 / 6.43) and in every stage; behind only at equal load in the densest frames: the night fleet's 60-69 objects 28.3 / 27.2 (7,061 frames: ~80 lost frames more than the arcade's rate) and 70+ 35.8 / 31.8 (948 frames: ~40 more). The sections that read "behind" (night fleet t004/t005 at ~36 objects, +0.6/+1.5) carry more objects than the arcade's games at the same point (37.3 vs 34.6): by load the conversion is ahead at 30-50 objects (40+: 5.4 / 8.3). Boss fights: 21 of the nation's 22 overruns and drop frames on 4.47% of boss frames (the desert boss 2.75%). For scale: the 0-10-object frames (maps, select, the cuts) lose 6.7% against the arcade's 4.5% - ~475 frames over the 600k, more than the dense bins together - but that is the game's own cut work (section 40: its tilemap rewrite 132-162k a frame; the palette path is already a 32k-entry table), not a HAL lever.

**What a dense frame is (fz69, the densest night-fleet windows of the matrix games: nation 3 seeds 7/8/9 from frames 46,868 / 184,375 / 56,640, ~540 frames at 60+ objects each; runfp.sh with the function-level map work/play/fp/mkmapfn.py -> map69fn.txt, then fz_rec and the collision index split by their local labels, map69fs.txt).** 60+ objects, cycles a frame (200,000 the frame; 55% of these frames go over it, 67% over the arcade's 163,000):

| item | cycles | per drawn object (~60) |
|---|---|---|
| record builder fz_rec | 32.0k | 530 |
| shape routines (VRAM columns) | 21.9k | 365 |
| the game outside its top 28 routines | 20.4k | |
| tilemaps (the night fleet's scroll) | 9.4k | |
| sched/vid/tcheck | 8.8k | |
| collision index (gx_band/bbuild/bcand) | 7.8k | |
| general records' pieces (fz_pd) | 6.9k | |
| main-loop slot scanner (gx_upd) | 6.6k | |
| obj_cull_outside_rect (game) | 6.5k | |
| builder's slot scan (fz_pass) | 6.4k | |
| spr_ctl, flip+reclaim, fz_* control, ntab | 20k | |
| obj_calc_hitbox, velocity, move (game) | 12.2k | |

Census of the drawn objects in those frames (work/play/fh/dncen.lua): 58-60 a frame, **85% fast records** (one piece, unzoomed, no B/A, a ROM template): the particles $0b (8-11), ring bullets $cb (7), $43 (4-7), bullets $2d (7-9), explosions $09 (4-5), items $0f (4-5); 8-10 general records (the fleet's ships $02/$3c/$40/$41, the $3d/$33 parts). The pair pool takes nothing here (no type $18 two-piece). fz_rec split: entry 2.3k, flags prologue 3.5k, the pair-bullet test every object pays 1.1k, **the fast path's tests and template fetch 12.7k (~250 a record)**, y/x 1.5k, w2/w3 composition 5.6k, the shape pick 2.1k, the general path 3.2k. The index: query loop 2.5k, build 2.1k + 1.2k per target, entry/end 1.3k. Two full scans of the 255 object slots every frame: the main loop's (6.6k) and the builder's (4.9k + 1.5k for the drawn ones). The shape routines are straight-line VRAM writes (spv_1100: ~45 instructions for a 32x32, the nops the MiSTer's write spacing needs): at their floor.

**The gap in cycles.** Section 23's sensitivity (~1-1.5 points of a dense bin's lost logic per 10k a frame) puts the 60-69 bin's 1.1 points at ~8-10k a dense frame and the 70+ bin's 4 points at ~25-30k - or a policy change, since 70+ frames are rare (0.16% of the nation's frames).

**The plan, exact cuts first (each a DEFS switch, off == fz69 byte for byte):**
1. **Slot scans as OR chains (`GX_ORSCAN`):** gx_upd's and fz_pass's eight-slot turns test each slot (tst.b + bne, ~20 cycles a slot); OR the eight state bytes into one register first (`move.b`, 7 x `or.b d16(An)`, one branch: ~13 a slot) and test them one by one only in a group with something in it. Pure reads, same order, same exit registers. ~2-3k a dense frame (more in sparse frames).
2. **The cull rect as constants (`GX_CULLK`):** 2.7M of the 3.6M calls of obj_cull_outside_rect come through 0x2b2d4 with the ROM rect at 0x2b326: a HAL copy with the rect's words ^ $8000 as immediates, each exit leaving d0/d1/d3/d4/a2 and the flags as the original's (the early exits leave d1 raw and d3/d4 the first pair). ~50 of ~200 cycles a call: ~1.5-2k.
3. **The fast record, tighter (`FZ_FASTR`):** the 85% case pays the general case's set-up: the flags prologue computes d6 bits the fast path then tests one by one (btst/andi.l pairs in w2w3), every object pays the pair-bullet compare, the template address needs `lsl #4` and a lea, FZ_FYM is an absolute-memory compare. A fast-first order (B/A, pieces, zoom, template word, in one short sequence), the w2/w3 masks from a 16-entry table indexed by the flag bits, the pair test only for type $18 behind the template miss, FZ_FYM as an immediate (it is set once per build), the template index pre-scaled by the tool: ~120-160 cycles a record, **~6-8k a dense frame** - the one item of this size. Verification as FZ_TPL's: a shadow mode building every fast record both ways and comparing (FZ_TPLCHK's pattern), the intro entries by round, the attract and the matrix.
4. **The index, tuned:** dbra over the entry count instead of the end compare, the rejection without a taken branch on the common side, gx_bcand's min/max with one exg path: ~1.5k.
5. **obj_calc_hitbox:** (y + d)^$8000 = (y^$8000) + d - two eori instead of four, words by movem: ~0.5-1k. Low priority.

Sum of 1-5: **~12-15k a dense frame** - enough for the 60-69 bin by the sensitivity above, about half of the 70+ bin's gap.

**Then the policy lever, measured not assumed:** 6. **Early conversion only when the game is idle (`FZ_EARLYB`):** FZ_EARLY lets the pass begin the next buffer a slot early; in a BUSY slot (the game still in its round) that work runs in the game's time. Section 30 measured the extremes (FZ_EARLY=0: lost logic 4.32 -> 2.27%, late 12.8 -> 18.6%, drop frames 1.50 -> 1.18%); the middle ground is early only in non-BUSY slots and only while the ring has room for a third set (fewer three-set moments in the boss fights: the drops and the commit-tail overruns). Measure: the 60+/70+ bins, late sets, nation 3's boss-fight drops and overruns, the attract A/B.

**Order and measures:** 1 and 2 (mechanical, exact by construction), 3 (the largest; its shadow check before anything runs long), 4-5, each by matched-window split profiles (work/play/fp/map69fs.txt pattern: each build its own map) and the attract A/B; then the matrix; then 6 as an A/B against the result. Not on the list, with reasons: the shape routines (at their floor), the general records (8-10 a frame), the palette (table-driven), the cuts (the game's own work), pools in vblank-written slots (sections 42/44), column sharing (ring-capacity findings), the game's velocity multiply (section 25: a table loses).

**Files:** work/play/fp/mkmapfn.py (function-level map), map69fn.txt, map69fs.txt (fz_rec and the index split), profiles pn69_7/8/9 (category), pf69_7 (function), ps69_7 (split); work/play/fh/dncen.lua (the record-path census).

## 47. Section 46's plan, built and measured (2026-10-20, fz70: `GX_CULLK`, `FZ_FASTR`, `FZ_EARLYB`)

**What did not survive the measuring, before any code:**
- **OR-chain slot scans (item 1):** simulated on the dense window's recorded slot states (work/play/fh/slotdump.lua, 3,000 frames, 68000 cycle counts for both scanners and both tests): the active objects are spread over the 255 slots, so most groups of eight hold one - the OR pass is wasted there: +3.6k a frame (groups of 8) / +1.4k (groups of 4) for the main loop, +2.8k / +1.0k for the builder, worse at 60+ objects. Not built.
- **obj_calc_hitbox (item 5):** no free register for the shared ^ $8000, and its exit registers (d2 the last word, a2 the table + 8, the flags of the tst) pin the order: break-even. Not built.
- **The index tuning (item 4):** ~0.5k on inspection, not worth the risk. Not built.

**Built (each a DEFS switch; with all three off the build is fz69 byte for byte):**
- **`GX_CULLK` (hal/gx.s 8):** jmp gx_cull at 0x2b2d4 (the cull entry with the ROM rect at 0x2b326): the rect's words ^ $8000 as immediates (GXC_R0..3, written by tools/aerofgt2neo.py from the ROM at build time), every exit's registers and flags as the original's (a2, d0, d3/d4 the pair reached, d1 raw on a y miss, the clr.b's flags outside). GX_VERIFY runs the original first and compares registers, SR and the slot's byte: **0 differences, 4 nations x 40k frames**; a bound off by one gives 129 in 10k (the check bites).
- **`FZ_FASTR` (hal/fz.s fz_rec):** the template fast record's way first; type $18 and $2e, d5 bits 5-7 (they fold into the original's flags), B/A, more than one piece, no template or a full buffer go to the original's way (fz_reco) unchanged. `FZ_FASTRCHK=1` builds every fast record a second time through fz_reco and compares the 16 bytes and a1: **0 of 3.29M records different** (four nations x 40k); y off by one: 73,075 of 73,075 caught. Measured gain smaller than section 46's estimate: the builder 4-8% less a drawn object (~20-50 cycles, not 120-160 - the template path was already lean; the general set-up it skips is ~60 cycles, part of it moved, not removed).
- **`FZ_EARLYB` (hal/fz.s fz_due):** a buffer is begun a slot early (FZ_EARLY) only when the slot began with the game idle (HAL_SCH_BUSY clear); in a busy slot its pass waits for its own slot instead of running in the game's time. With it, FZ_TAILX (the commit tail's margin) is 4 lines larger (+192 units: 344): the passes begun in their own slot meet the deadline more often - nation 3's overruns 59 with the old margin, 22 with +2 lines (248), **14 with +4 (344)**.

**The matrix (4 nations x 3 seeds x 200k, botsel 2P autofire + boss bombs; work/matrix_gb3/hcf/hcfe/hcfe344.txt), lost logic conversion / arcade, late sets, drop frames, overruns:**

| build | n0 | n1 | n2 | n3 | late% n0..n3 | drop% n0..n3 | overruns |
|---|---|---|---|---|---|---|---|
| fz69 | 1.81 | 2.80 | 5.09 | 5.58 | 5.96 / 8.33 / 11.24 / 11.77 | 0.14 / 0.08 / 0.52 / 0.82 | 2 / 2 / 2 / 22 |
| + GX_CULLK + FZ_FASTR | 1.56 | 2.40 | 4.27 | 4.97 | 5.69 / 7.42 / 10.69 / 10.38 | 0.17 / 0.07 / 0.25 / 0.87 | 2 / 1 / 2 / 22 |
| + FZ_EARLYB, margin 152 | 1.27 | 1.93 | 3.51 | 3.95 | 7.22 / 8.38 / 11.43 / 12.93 | 0.17 / 0.10 / 0.57 / 0.86 | 14 / 11 / 27 / 59 |
| **+ FZ_EARLYB, margin 344 (fz70)** | **1.15** | **1.76** | **2.78** | **3.21** | 7.00 / 8.57 / 8.72 / 11.41 | 0.16 / 0.10 / 0.55 / 0.78 | **1 / 1 / 1 / 14** |
| the arcade | 3.31 | 6.12 | 8.81 | 7.69 | - | - | - |

**The dense bins, night fleet, conversion / arcade (fz70; fz69 in brackets):** nation 3 60+: **19.9** / 27.2 (28.3), 70+: **28.6** / 31.8 (35.8); nation 1 60+ 21.2 / 30.5, 70+ 29.6 / 37.4; nation 2 60+ 21.5 / 29.0, 70+ 26.9 / 35.4. The deficit of sections 39-46 is gone: ahead of the arcade in every load bin of every nation. Sections behind the arcade (>= 3,000 frames each side): 16 -> 10. No reboot in any of the 39 games (hcf, hcfe and fz70 x 12, hcfe248 x 3). Boss fights: nation 3 9.30 / 15.31 (fz69 12.07), its drop frames 4.41% (4.47%), overruns 12 (21).

**The cost:** late sets +1.0 point in nation 0 (5.96 -> 7.00) and +0.2 in nation 1, -2.5 in nation 2 and -0.4 in nation 3; drop frames +0.02-0.03 points in nations 0-2, -0.04 in nation 3. The attract A/B (12,000 frames, deterministic): lost 491 -> **412**, late 864 -> 846, drop frames 197 -> 164, overruns 1 -> 1.

**Checks:** the picture check (run_cmp3.sh -> work/c3_fz70: movie7 10,000 and attract 6,000 frames, HUD dropouts 0, overruns 0, the contact sheet clean through two games, the ranking screen and the attract); the assist set (aerofgtna) changes with the main set because the build moves the video tables when the HAL outgrows 0xc8000, which both switches together do: its RAM and pixel dumps over movie1's 1,500 frames are byte-identical to fz69's. MiSTer: fz70 deployed (backup 538-p1.p1.fz69_ab82be55); chk11 clean (work/mister_fz70_chk11/sheet.png), audio -35.1 dB; the 22-minute open-loop Japan session (/tmp/play_jp.sh, work/vid/fz70_play.mkv, sheet work/vid/fz70_play_sheet.png) through the ship, city, river, runway, base, desert, ocean-fleet and jet stages to the night stage: no reboot, no music gap (musicgap.py: only the silence after the script's end). **fz70 is the release (2026-10-20):** the README's DEFS gain GX_CULLK=1,FZ_FASTR=1,FZ_EARLYB=1; 538-p1.p1 CRC 4a82388d, the assist's 538a-p1.p1 1ff47c07, the other files fz69's (the README's table rebuilt from its own command: 9 of 9).

**Files:** hal/gx.s (8: gx_cull), hal/fz.s (fz_rec's FZ_FASTR way and fz_reco; fz_due's FZ_EARLYB), hal/hal.s (the switches, FZ_TAILX + 192 x FZ_EARLYB), tools/aerofgt2neo.py (GXC_R0..3, the 0x2b2d4 hook); work/play/fh/slotdump.lua, ctrs.lua; builds work/out_hcf, out_hcfe, out_hcfe248, out_hcfe344 (= out_fz70, p1 md5 1e0211a8), out_hcv/out_hfc (the checks), out_hmut/out_hmut2 (the planted defects).

## 48. Sprite drops in boss fights: the cause measured, column merging and load shedding built and rejected (2026-10-20; fz70 stays the release)

**Where the drops are (fz70, work/play/fh/dropwhy2.lua on nation 2 and 3 seed 7, 200k frames; its pool-state address fixed to BP_ST 0xd00fea).** Nation 2: 1,377 drop frames, 7,130 sprites; nation 3: 1,837 frames, 12,177 sprites. By stage: the final, desert, ocean bosses (8-16% of their frames, nation 2), the desert, coast/river, final, ocean, runway bosses and the cities (nation 3). **Almost every drop has two sets in the ring** (1,375 of 1,377; 1,830 of 1,837): the shown set and the one in work, no complete set waiting - nothing frees columns until the set in work is itself shown, so the conversion's wait (spr_anyw) cannot help and the rest is dropped. The sets at the drop frames are **genuinely over half the ring**: the drawn objects' columns (work/play/fh/mergecen.lua on fz70's own games, frame-matched) p50 183 (nation 2) and 176 (nation 3); a double-buffered ring of 338 holds 169 a set. In nation 3, 96% of the drop frames have the pair-bullet pool on (RING_TOP 317: the ring 274 columns, 137 a set): ~25 pair bullets a frame in the bomb-heavy boss fights (type $18, 2 pieces of 2 columns - in the pool they cost 2 columns once, in the ring they would cost 4 twice). The frames themselves (work/play/fh/dshot screenshots inside long episodes): bomb strikes in boss fights - the escort jets, the white blast circles, rings of explosions (the bot bombs on every boss: the worst case). The records dropped are the pass's last: the objects of the highest slots (G_DX_OBJ4 up), the same ones every frame of an episode (episodes up to 137 frames).

**Column merging (`FZ_MERGE`, hal/fz.s fz_mg; built, measured, off).** Two pieces consecutive in the set's column order (SS_HNEXT unchanged since the last one's shape: nothing allocated between them), the same x and width and tilemap-1 class, the second a whole number of tiles below the first's bottom (a gap of at most FZ_MGGAP = 4 rows, the column at most 32 rows): the second's tiles go into the first's columns (the gap transparent), the first head taller - the same picture, fewer columns. Hooked in fz_fastv and fz_disp (every piece), a subroutine (no merge: rts; merge: on at fz_next, the charge and its refill before anything is written). The potential by the census (frames over 150 columns): nation 2 ~12-15 columns, nation 3 ~37-55 - but nation 3's is the pair bullets' two pieces (type $18: 49.8 of 53.7 columns), which the pool takes anyway; without them ~6. Realised (FZ_MGDIAG counters against the census, the same frames): nation 2 4.7-6.2 columns, nation 3 2.4-3.0. Correct in the pictures (boss-fight screenshots of the merge build; the flame pillars in them are nation 2's bomb, the same in fz70's). **Rejected:** the test on every piece (~350 cycles; ~20k in a dense frame) costs far more than the columns it saves - the matrix with merging and shedding: lost logic 3.26 / 3.89 / 5.94 / 6.48% against fz70's 1.15 / 1.76 / 2.78 / 3.21, overruns 39 / 45 / 27 / 80. Two bugs on the way: a .w column count with a stale high word added as .l to the diagnostic counter (the counter jumped by millions: not a reboot), and the first merge path's refill unwinding a stack that still held the saved registers (rewritten: the charge first, the registers saved after).

**Load shedding (`FZ_SHED`, hal/fz.s fz_shmark, fz_ntab, fz_begin; built, measured, off).** The effects (explosions 09, 33, 60, 6c, 99, 9b; sparks 0e, 16, a3; the bomb's flash 20; shadows 2f, 34, 88: fz_shtab from work/catalog/type_handlers.tsv) are marked in the builder (bit 7 of a record's first long: 24-bit addresses; cleared in fz_ntab before anything jumps through a kept record) while shedding is on; after a pass that dropped, the level goes up (1: every other effect, alternating with the pass's parity - each still shown every other frame; 2: all of them), down after FZ_SHCALM = 30 passes without a drop; shed records count in FZ_SHN (state at 0x10fc30, the idle stack's checked end). First 60k frames: sprites dropped 990 -> 159 (nation 2), 2,465 -> 306 (nation 3), ~7,000 records shed. The attract A/B: sprites dropped 1,274 -> 566, but the episodes barely shorten (frames with a true drop ~165 -> ~139: the sets are over the ring even without the effects), the frames shown inexact 164 -> 366 (the shed ones), late sets 846 -> 917, **lost logic 412 -> 452** (the marking's call on every object first; gated on the level afterwards, still 452). The matrix: true sprite drops did not fall in every nation (per game, e.g. nation 0 seed 7 392 -> 2,813 sprites with the first, ungated build), drop frames counted 0.16-0.78% -> 1.3-2.3% (shed frames included). **Rejected:** a smaller loss of sprites inside the same episodes, at the price of flicker in many more frames and the lost-logic gain of fz70.

**Why nothing exact closes it.** The ring double-buffers: the shown set stays while the next is converted, so a set over 169 columns (137 with the pool on) cannot be shown complete after another of its size. The levers left are structural, each tried before (AUDIT 12-14, 20, 42, 44 and the ring-capacity findings): column sharing between the two sets, in-place updates, vblank-written pools - and merging and shedding now. What would change the bound: fewer double-buffered columns (a third kind of storage, like the pool, for some class of sprites the vblank can afford), or a larger ring (the tilemaps' 42 sprites: tilemap 1 hides 5-7 of its 21 columns in these frames, ~2% of the ring). The boss fights' drops stay: 0.5% of the boss-fight frames in nations 0-1, ~4.4% in nations 2-3, almost all in bomb strikes.

**Files:** hal/fz.s (FZ_MERGE: fz_mg, the hooks in fz_fastv and fz_disp, fz_begin's gate; FZ_SHED: fz_shmark, fz_shtab, fz_ntab's skip, fz_begin's level), hal/hal.s (FZ_MERGE, FZ_MGT, FZ_MGGAP, FZ_MGDIAG, FZU_MGC, FZU_MG0, FZ_SHED, FZ_SHCALM; all off: the build is fz70 byte for byte); probes work/play/fh/dropwhy2.lua (BP_ST fixed), mergecen.lua, mergetype.lua; builds work/out_mg, out_mgd, out_sh, out_sh2, out_mgsh; matrices work/matrix_sh.txt, work/matrix_mgsh.txt; the attract runs work/play/fp/att_sh, att_sh2.

## 49. The bullet pool item: explosions pooled, a single-buffered effects store, pre-scaled effects (2026-10-20; analysis, nothing built)

**The effects in the drop frames (fz70, work/play/fh/effcen.lua: every frame of nation 2 and 3 seed 7, 200k frames, joined with dropwhy2.lua's drop frames; the effect types are section 48's shedding set).** Nation 2: 10.2 effect objects a drop frame, 56 columns (31% of the set's 181), 131 tiles; nation 3: 6.8 objects, 21 columns (12% of 175), 77 tiles. **The effects are nearly static:** a frame sees 1.5-2.1 of them start a new animation frame (22-35 tiles) and 1.6-3.1 move - a single-buffered store would write little per frame (positions and tiles only on a change, unlike the bullets of section 44, which move every frame).

**Pre-scaling / zoom: does not apply.** No effect is drawn zoomed: the builder zooms type $2e only (the enemy fighter formations, catalog: 109 tables), 0.2-0.4 columns of a drop frame. The explosions grow by their own animation frames; a Neo shrink keeps a sprite's columns anyway, so pre-scaled tiles would save columns only for zoomed sprites, and there are none to speak of here.

**Draw order: the obstacle to a store (work/play/fh/efford.lua, frames over 150 columns, the pass's order with boxes from the pieces).** An effect in a store at a fixed place in the sprite list (above the ring or below it) leaves its place among the other sprites. Explosions ($09) overlap a non-effect sprite drawn behind them in 86-88% of cases and one drawn in front of them in 83-89%; sparks ($16) 67% / 76%; smoke ($9b) 71-78% / 79-95%: wherever the store sits, most explosions would be drawn over or under something they should not be. Shadows ($2f, $34) and impact sparks ($0e) are almost never in front of a non-effect (0-8%): a store below the ring would keep them right - but they are ~1.2 + 0.5 objects a frame, a few columns.

**The gain if the slips were accepted (the census as a model: a set fits when its non-effect columns are at most half the ring left beside the store, and its effects fit the store).** Nation 2's drop frames that would fit: 22% with no store, 8% / 28% / 51% with a store of 32 / 48 / 64 columns; nation 3 (the pair-bullet pool's 64 columns on): 14% with no store, 10% / 9% / 7% with one - its effects are small and the store's columns come out of the ring. A store sized to its content brings back section 42's resize churn. Section 48's shedding agrees: taking the effects out halved the sprites dropped but hardly shortened the episodes.

**Verdict: no effects store.** Its best case halves nation 2's drop frames with systematic priority slips for most explosions and makes nation 3 worse; a shadows-only store is exact but saves a few columns. The bullet pool's two untried knobs (section 44: a larger estimate, the inverse size policy) concern the player shots' vblank cost, not the drops. The drops stay a capacity limit of the double-buffered ring (section 48).

**Files:** work/play/fh/effcen.lua, efford.lua; their runs in the session's scratch (ec_n2/3, eo_n2/3).

## 50. Single-buffered sprite storage instead of the double-buffered ring: evaluated (2026-10-20; nothing built)

**The question:** give one set all 338 ring columns (single buffering, the pool's way for every sprite) instead of two sets of half the ring - the boss fights' sets of 170-185 columns would fit.

**The constraint:** single-buffered columns are on the screen; a write to one is safe only while the beam is not drawing it - in the real vblank (40 lines, ~30.7k cycles), of which the commit's fixed work (palettes, tilemap blast and placement, HUD, flip, reclaim) reserves COMMIT_LINES = 16: **~24 lines, ~18k cycles** for sprites. Today the ring needs none of it for correctness: the pass converts into hidden columns at any time, the display included, and uses the vblank's rest only as more conversion time.

**What it would have to write (work/play/fh/sbuf.lua on fz70: a write tap on the VRAM registers, and the objects frame to frame; nation 3's night fleet 46,868-49,868 and nation 2's desert boss 55,000-58,000):**

| window | objects | columns | the conversion's ring writes a frame now | address sets | writes if each object kept its columns |
|---|---|---|---|---|---|
| night fleet, 45-60 objects | 48 | 123 | 585 data words | 226 | 288 |
| desert boss, 45-60 | 51 | 111 | 421 | 209 | 182 |
| desert boss, 60+ | 62 | 159 | 482 | 200 | 165 |

**A full rewrite each frame in the vblank:** 600-800 VRAM register writes, ~10-13k cycles at 12-16 cycles each (the MiSTer drops data writes closer than 12 cycles) - inside the 18k on average, over it in the densest frames (the census's 60+-object frames: ~460 tiles, ~1,300 writes, ~17-20k), which are the frames it would be for. The words would have to be computed before the vblank into a RAM list (~2-3 KB: there is no free RAM - sections 45-48 found 20 bytes at a time), every set would have to be complete before its vblank (no conversion overlapping the display: more sets late in exactly those frames), and a frame that does not fit tears at the top of the screen. **Does not work.**

**Writes only for changes (each object keeping its columns):** 160-290 writes a frame, ~2-4k cycles - affordable. But a sprite's place in the Neo's list is its column, fixed when allocated, while the game's draw order changes with every spawn and death (slot order) and every frame in the x-sorted group: keeping the order exact means moving columns, i.e. rewriting them, which is the full rewrite again; not keeping it is section 44's stable pool for every sprite, with its priority slips everywhere. And moved heads are written every frame regardless (22-32 a frame: most sprites move). **Does not work exactly.**

**The one form that could work: completing the overflow in the vblank after the flip.** Almost every drop has two sets in the ring, the shown one and the one in work (section 48): the one in work cannot wait, since only its own flip frees the shown set's columns. Instead of dropping its remaining records, it could be flipped incomplete at its vblank and the pass go on in the same vblank into the columns the flip just freed: the frame's display begins after the vblank, so a set completed by the deadline is shown whole. The remaining records are the pass's last (the back-most), so they belong in columns below the set's - right when the freed set lies below it (the usual case: the set in work runs into the shown set's tail from above); a split ring would need the drop as now. **Size:** the shortfall at the drop frames is p50 36-45 columns, p90 115-168; at ~400-600 cycles a column (records, pieces, shapes) the ~18k left convert ~30-45 columns: roughly half the drop frames would complete, the p90 ones still drop. **Risks:** the vblank's sprite share is also what the next pass's start uses today (contention: more late sets), a conversion past the deadline writes visible columns (tearing: it must stop at the deadline as the commit's tail does), and the ring's state machine (a shown set still converting, its reclaim, the split cases) is where every earlier ring change found its bugs (sections 10-14, 30, 44). Not built: a design for its own session.

**Files:** work/play/fh/sbuf.lua; the runs in the session's scratch (sb_nf, sb_db).


## 51. The overflow completion, built: in the vblank (does not fit) and on until complete (drops nearly halved) (2026-10-20, `FZ_OVF`; AUDIT 50)

**What it does (hal/spr.s, FZ_OVF).** At a drop (`.hdrop`) with only the shown set S and the set in work W in the ring, W not split, and S wholly below W's next column (or S split with W in its hole): W is marked complete (state 1) while still converting, waits as it does for columns, and the flip shows it - its heads so far written - and frees S. The conversion then goes on with W's remaining records (the back-most) into S's freed columns below W's (`FZ_OVFC`); `spr_ovfend` writes the heads converted since the flip and ends the set as `.fin` does. A second overflow inside a continuation, or a restart at the top (`.rst`), drops as before. State in the idle stack's deep end (FZ_OVFP 0x10fc3c, FZ_OVFC 0x10fc3d, FZ_OVFW 0x10fc3e, FZ_OVFH 0x10fd9a), cleared in fz_reset (the boot RAM test leaves patterns there: the first builds began with FZ_OVFP = $fc). FZ_OVFDIAG counts begun / completed / cut in 0xd00f30/34/38. Off, the build is fz70 byte for byte (all 9 files).

**A bug found on the way:** `hal_spr_set` multiplies d0 by 4; `spr_ovfend` indexed HAL_SPR_MIX and HAL_SPR_START with it. Set 2's drop flag (`bset #1` at MIX+8) landed on RDY[2]'s high byte (17749 -> 18261, a frame 500 in the future): the flip would not show the other sets (older than the shown one), the free sets behind the shown one in the ring order could not be reclaimed, no set could start - every frame late from then on (nation 3: 74% late over 60k frames). Found by a ring-state probe (`ordn 3` with two free sets).

**FZ_OVF=1, the continuation in the commit's vblank only (section 50's form): does not fit.** An event probe (the flip, the cut: the beam line from REG_LSPCMODE, the heads written) on nation 3: W waits from line ~350 for its flip at ~506, the commit's work after the flip reclaims S (~3 lines + the tail's), and the deadline (`HAL_OUT`, line ~259, 18 lines after the flip) comes after **1-3 heads**; 0-70 columns were left. Nation 3, 60k frames: 368 overflows, 3 completed, 365 cut; drops as fz70's (2401 vs 2465 records). No matrix: the counters settle it.

**FZ_OVF=2, the continuation on until complete (gives back main-loop time):** no cut at the commit's end or in the main loop. W's new columns lie below the ring's height-0 tail until their heads are written (`spr_ovfend` at `.fin`, in the main loop: the commit and the conversion are one thread, no interrupt between their VRAM writes). Every continuation completes (nation 3: 261 of 261, nation 2: 241 of 241); the beam at completion (nation 3): lines 255-290 for 95%, i.e. within ~20 lines after the vblank - the sprites of a continuation miss the screen's top rows for that one frame. The deterministic attract A/B (fz70 412 / 846 / 164 / 1): lost logic 392, late 889, **drop frames 76**, overruns 1.

**The matrix (work/matrix_ov2.txt; fz70: matrix_hcfe344b, matrix_hcfe344):**

| nation | lost logic fz70 -> ov2 (arcade) | late | drop frames | overruns |
|---|---|---|---|---|
| 0 | 1.15 -> 1.20% (3.31) | 7.00 -> 7.23% | 968 -> 587 | 1 -> 1 |
| 1 | 1.76 -> 1.42% (6.12) | 8.57 -> 7.24% | 615 -> 382 | 1 -> 3 |
| 2 | 2.78 -> 3.01% (8.81) | 8.72 -> 11.19% | 3297 -> 1394 | 1 -> 2 |
| 3 | 3.21 -> 3.46% (7.69) | 11.41 -> 11.96% | 4646 -> 2572 | 14 -> 23 |

Boss fights: nation 2 drop frames 1.77% (fz70 ~4.4%), nation 3 2.08% (4.41%), lost logic 9.35 / 8.75% against the arcade's 23.34 / 15.31%.

**The late-logic buffer given back.** The conversion's lost logic is a half to a third of the arcade's in every nation; FZ_OVF=2 spends a little of that margin: +0.2 points of lost logic in nations 2-3 (W's continuation holds the game: its set is due), and late frames +2.5 points in nation 2 (the next set cannot begin until the continuation ends), while every nation stays far under the arcade. That margin is the only reason the continuation can run past the vblank at all: in the vblank (FZ_OVF=1) it gets 1-3 heads. Giving back more would not remove the drops left: they are not short of time. Classified at each drop (work/play/fh/dropcls.lua: the ring's shape at each drop; nation 3, 60k frames, frames with a drop): W split around S (W's top run above S, its lower run below S down to column 43) 275, W below S 88, inside a continuation 45 (the set does not fit even with S's columns), 3 sets in the ring 2. In the first two, the columns the flip frees lie *above* W's last ones: the continuation's records (the back-most) would be drawn in front of W's earlier ones (a priority slip wherever they overlap), so FZ_OVF leaves them as drops. They belong to the alternation of two large sets at the ring's two ends (SPR_ANCH): one of every two sets is the lower one.

**The overruns (nation 3: 14 -> 23 in the matrix) are not the continuation's.** OVR_DIAG builds of fz70 and FZ_OVF=2 (work/out_70o, out_ov2o; the session's ovrwhy.lua: at each overrun the last passing check's caller and how many frames since a continuation began), nations 2-3, seeds 7-9, 200k frames each: fz70 115 overruns, FZ_OVF=2 129 (nation 2: 41 / 31, nation 3: 74 / 98), all at the yield (sched.s), the same checks in both - the flip's (hal_spr_flip+182) for 85%, then sch_slot and the commit; none within 3 frames of a continuation's start, 4 within 60. Seed noise around fz70's own flip overrun.

**The MiSTer trial (p1 d2611bd9, 2026-10-21; fz70 restored after it, the build kept on the card as 538-p1.p1.ov2_d2611bd9):** chk11 clean (work/mister_ov2_chk11/sheet.png: the same 24 screens as fz70's, its one black frame a scene change both share); the 22-minute play_jp session captured (work/vid/ov2_play.mkv, sheet ov2_play_sheet.png), audio -31.6 dB mean. One-frame spikes 2.24% of frames (fz70's session 2.08%), the game's own flashes. A continuation's late heads would show as a one-frame change in the raster's top rows only (the picture's top band, the game being rotated): 182 such frames against fz70's 130, the left/right/bottom bands alike; looked at, they are the Japanese bomb's shockwave across the top, drawn on one frame in two to four in both builds (a sequence of 24 frames: the game's blink), the difference following how much bomb each open-loop session had. No continuation artefact seen. MAME cannot show one: every continuation ends (lines 255-330) before MAME's frame end (the session's ovsnap.lua found none pending in 12,000 attract frames).

**Open:** a slipping continuation for the W-below-S drops (priority slips where they overlap, against a missing sprite) - a judgment call. Section 48's FZ_SHED results predated the fz_reset initialization of its state: rerun in section 52.

**Released as fz71 (2026-10-21):** the release switches + `FZ_OVF=2`; p1 md5 d2611bd9, CRC 7ad9189f, SHA1 39a7a92e...; the other cartridge files and the assist set are fz70's (work/out_fz71).

**Files:** hal/spr.s (`.hdrop`'s overflow, `.rst`'s guard, the flip's hand-over, `spr_ovfend`, hal_spr_work's entry and `.fin`), hal/video.s (the commit's cut, FZ_OVF=1), hal/fz.s (fz_reset: FZ_OVF's and FZ_SHED's state cleared), hal/hal.s (FZ_OVF, FZ_OVFDIAG); probes work/play/fh/dropcls.lua; builds work/out_ov, out_ovd (FZ_OVF=1), out_ov2, out_ov2d (FZ_OVF=2), out_m0 (off: fz70); matrix work/matrix_ov2.txt; attract work/play/fp/att_ov2.

## 52. Load shedding remeasured with its state initialized, on fz71 (2026-10-21; `FZ_SHED` stays off)

**Why:** section 48 measured `FZ_SHED` before fz_reset cleared its state (the boot RAM test leaves patterns in the idle stack: FZ_SH_LV could begin at $fc, shedding everything). Build work/out_sh71: fz71's switches + `FZ_SHED=1` (p1 md5 cd3852f1).

**The attract A/B (fz71 -> + shedding):** lost logic 392 -> 427, late 889 -> 985, sprites dropped 929 -> 528, frames shown incomplete (shed or dropped) 76 -> 343, overruns 1 -> 0. As section 48's (412 -> 452 lost logic): the initialization changed little here.

**The matrix (work/matrix_sh71.txt against fz71's work/matrix_ov2.txt).** The matrix's drop frames count a frame with a shed effect too, so the true drops are counted apart (work/play/fp/truedrop.sh: frames where the drop counter rises, seeds 7-9):

| nation | lost logic fz71 -> shed (arcade) | late | true drop frames | sprites dropped | frames incomplete (shed + dropped) |
|---|---|---|---|---|---|
| 0 | 1.20 -> 1.47% (3.31) | 7.23 -> 8.01% | 623 -> 311 | 4,358 -> 2,589 | 0.10 -> 1.44% |
| 1 | 1.42 -> 1.70% (6.12) | 7.24 -> 8.28% | 421 -> 304 | 3,456 -> 2,252 | 0.06 -> 1.16% |
| 2 | 3.01 -> 3.78% (8.81) | 11.19 -> 12.21% | 1,455 -> 322 | 12,084 -> 2,547 | 0.23 -> 1.59% |
| 3 | 3.46 -> 4.19% (7.69) | 11.96 -> 13.16% | 2,753 -> 1,395 | 27,225 -> 10,171 | 0.43 -> 2.88% |

Boss fights: lost logic 13.07% (nation 2) and 10.72% (nation 3) against the arcade's 23.34 / 15.31%; frames incomplete 8.6 / 11.7%. Overruns 1/2/1/21 (fz71 1/3/2/23).

**Correction to section 48:** shedding does cut the true drops in every nation - by 28-78% here, and by a similar share in section 48's own matrix (true drop frames 283/322/402/1,528 against fz70's 974/618/3,297/4,610, counted the same way); section 48's "did not fall in every nation" came from one game of the first, ungated build.

**Verdict: still off.** The price is effects missing on alternate frames in 1.2-2.9% of all frames and 4-12% of boss-fight frames - six to eleven times the frames of true drops it saves - plus 0.3-0.8 points of lost logic and ~1 point of late sets. Every nation stays well under the arcade's lost logic, so it remains a judgment call between an effect blinking for a few dozen frames and the back-most sprites of a set missing for one; with fz71's continuation already halving the true drops, the blink is the larger change on screen.

**Files:** work/out_sh71, work/matrix_sh71.txt, work/play/fp/truedrop.sh, the attract run work/play/fp/att_sh71.

## 53. The drops below the shown set: its columns kept for the records that belong there (2026-10-21, `FZ_HOLE`, `FZ_OVFPB`, `FZ_FLIPM`; release fz72)

**The case (section 51's remainder).** With only the shown set S and the set in work W in the ring, fz71's continuation (FZ_OVF=2) completes W only when S lies below W. In the rest, the columns S's flip frees lie *above* W's last ones: W began at the top, its top run reached S, and it went on below S's end down to SPR_PB (split around S: ~75% of the remaining drop frames), or W began just below S, S holding the ring's top (the bottom set of two large ones, ~25%). Continuing W's last records into S's columns would draw the back-most sprites in front of W's others.

**The placement change: S's columns get the records that belong there.** W's records are complete before its pass begins (the records pass, one buffer), so the split can be chosen in record order:
- **At the split** (hal_spr_go .spl, `fz_hole_split` in place of fz_split_anch): the lower run below S takes the *last* records that fit it - counted back from the buffer's end with the pieces' unclipped widths (an upper bound), its guard height 0 where they end - and the records between the top run's and the lower run's are kept: the pass's place saved as .late leaves it (FZ_REC, the piece, its routine, FZ_LEFT, y/x, w2, zoom), the pass jumped to the lower run's first record.
- **At the begin** (`fz_hole_begin`, fz_begin's end): W began at S's end with S at the ring's top: W is made a split set with an empty top run - its start S's, its lower run from SPR_PB up with the last records, the first ones kept.
- **The lower run done** (`.fin` -> `spr_holefin`): W is marked complete for its flip while still converting (FZ_OVF's state: FZ_OVFP/FZ_OVFC), the pass set back to the kept records, W's next column the top run's end. The flip shows W and frees S; after S's reclaim hal_spr_lim stops the kept records at the lower run's guard (W is the ring's split set); they convert into S's columns in order and `spr_ovfend` writes their heads, restoring W's end and the next start (`.hoff` moved them while it went on) and moving SPJ down. The kept records end where the lower run's began (fz_ntab: FZD_STOP).
- **Nothing shows early:** a column with no head written yet hangs off the next lower head, and the lower run's guard is height 0 - S's freed columns and the kept records' columns stay hidden until their heads are written, with no extra VRAM write.

**Costs and the bugs on the way.** The walk back (`fz_hwalk`, ~90 cycles a piece) is charged as the pass is, a record at a time, and resumable: at a split with no time the pass stops (.late, this piece again) and the walk goes on from where it stopped; at a begin it is only planned (FZD_ON 3) and done as the pass's first step (fz_go). The first build charged it in one sum without a stop: overruns 15/11/52/168 (OVR_DIAG: the slot check `sch_slot` with a walk under way, 2-14 lines over). A stop signalled through d2 met fz_split_anch's d2 (an SCB3 address, negative as a word): every split stopped forever (attract: 88% late) - FZD_ON 4 is the signal now. The begin variant first fired also with S low in the ring (S 127..79: a whole set kept for after the flip where fz71's .rst begins it again above S): it now needs S at the ring's top.

**A fz71 defect found and fixed (`FZ_OVFPB`):** fz_begin clears a set's pool-record count and only fz_fin sets it, so a set flipped before its pass ends (every FZ_OVF continuation) was shown with no pooled pair bullets until the next flip - nation 3 (pool on), 60k frames: 155 of 155 continuation flips showed none. FZ_OVFPB counts them at the hand-over (`fz_pbcnt`) and `spr_ovfend` applies the pool again when the set is complete (`bp_apply`): 38 of 194 flips with none left, sets whose pooled bullets come after the hand-over.

**`FZ_FLIPM`:** with fewer drops the flips carry more heads; the flip's own overrun (hal_spr_flip+182, fz70's long-standing one, 2-3 lines over) came up more often in nations 0-1 (matrix overruns 10/9 against fz71's 1/3). One line more in the flip's estimate brings them back (1/5/1/24 against fz71's 1/3/2/23).

**Correct (work/play/fh/holechk.lua):** at each kept-record continuation's end, every head written before the flip lies outside S's gap (the top run at or above SPJ, the lower run below SPG) and every head written after it inside - each part converted in order, the columns follow the records' order. Four bot games of nations 2-3 on the final code (out_hl charged, out_hlm1): 862 continuations, 0 out of place (and 1,082 on the first build); the visible-column check (vischk) on nations 2-3: 0 violations in game. Off (FZ_HOLE=0, FZ_OVFPB=0, FZ_FLIPM=0) the build is fz71 byte for byte (all 9 files).

**Measured (work/matrix_hlm1.txt: + FZ_OVFPB=1, FZ_HOLE=1, FZ_FLIPM=1; fz71: matrix_ov2.txt):**

| nation | lost logic fz71 -> (arcade) | late | true drop frames | sprites dropped | drop frames (matrix) | overruns |
|---|---|---|---|---|---|---|
| 0 | 1.20 -> 1.25% (3.31) | 7.23 -> 7.50% | 623 -> 283 | 4,358 -> 2,131 | 0.10 -> 0.04% | 1 -> 1 |
| 1 | 1.42 -> 1.61% (6.12) | 7.24 -> 7.82% | 421 -> 228 | 3,456 -> 1,653 | 0.06 -> 0.03% | 3 -> 5 |
| 2 | 3.01 -> 3.60% (8.81) | 11.19 -> 12.77% | 1,455 -> 498 | 12,084 -> 4,114 | 0.23 -> 0.04% | 2 -> 1 |
| 3 | 3.46 -> 3.64% (7.69) | 11.96 -> 12.61% | 2,753 -> 1,020 | 27,225 -> 10,575 | 0.43 -> 0.08% | 23 -> 24 |

Boss fights: drop frames 0.18/0.15/0.28/0.38% (fz71 0.36/0.22/1.77/2.08%); lost logic 11.11% (nation 2) and 9.56% (nation 3) against the arcade's 23.34 / 15.31%. The attract A/B (fz71 392 / 889 / 76 / 1): lost logic 404, late 956, drop frames 15, overruns 0. The price is the walk and the later sets: +0.05-0.6 points of lost logic (nation 2 most) and +0.3-1.6 points of late sets, every nation still under half the arcade's lost logic or near it.

**Left:** FZ_OVF continuations that begin mid-ring and run out at SPR_PB even with S's columns (most of the drop frames now), sets larger than the ring, and the pool's 64 columns in nation 3.

**The MiSTer trial and the release (2026-10-21).** The device was off the network for a minute before the deploy (its USB wireless; uptime unbroken). out_hlm1's p1 (md5 4d674998) trialled: chk11 clean (work/mister_hlm1_chk11/sheet.png: fz71's screens, the shared scene-change black frame; the second game's last shots a river stage, the open-loop pad's timing), the 22-minute play_jp session (work/vid/hlm1_play.mkv, sheet hlm1_play_sheet.png) through every stage to the ending, audio -31.6 dB mean; one-frame spikes 2.23% of frames (fz71's session 2.24%), top-band-only one-frame changes 175 (fz71 182: the Japanese bomb's blink). **Released as fz72:** the release switches + FZ_OVFPB=1, FZ_HOLE=1, FZ_FLIPM=1; p1 CRC 6f3ebbcf, SHA1 f8c6e66f..., md5 4d674998; the other cartridge files and the assist set are fz71's (work/out_fz72); deployed (backup 538-p1.p1.fz71_d2611bd9).

**Files:** hal/fz.s (fz_hole_split, fz_hwalk, fz_hcols, fz_hole_begin, fz_hole_bset, fz_pbcnt, fz_ntab's stop, fz_go's walk, the FZD_* state in FZ_V+184..+219 and +230..+239), hal/spr.s (.spl, .fin -> spr_holefin, spr_ovfend's hole end and pool, the FZ_OVF hand-over's count, the flip's FZ_FLIPM, hal_spr_work's begin budget), hal/hal.s (FZ_HOLE, FZ_OVFPB, FZ_FLIPM); probes work/play/fh/holechk.lua, dropcls.lua; builds work/out_hl, out_hld, out_hlo, out_hlm1 (the measured one), out_hlo1/2, out_hlm2, out_pb, out_m0 (off: fz71); matrices work/matrix_hl.txt (the first, uncharged walk), matrix_hl2.txt (charged, no margin), matrix_hlm1.txt; attract work/play/fp/att_hl, att_hlm1.
