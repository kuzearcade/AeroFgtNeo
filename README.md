# Aero Fighters for the Neo Geo MVS (aerofgtn)

A conversion of Video System's 1992 arcade game *Aero Fighters* (MAME set `aerofgt`) into a Neo Geo MVS cartridge set that runs on real Neo Geo hardware, on the MiSTer Neo Geo core and in MAME.

## Goal

The goal is the original game, not a remake. The arcade's own 68000 program runs on the Neo Geo's 68000. A hardware abstraction layer (HAL) translates its video, sound and input hardware into Neo Geo equivalents.

The project holds itself to these rules:

- **Real cartridge limits.** The main set fits a real PROGBK1 program board and CHA256 graphics board. No emulator-only hardware is needed.
- **Same game logic, frame for frame.** The game's RAM matches the arcade's frame by frame in the deterministic tests. Game speed and music tempo are the original's, in real time.
- **Measured against the arcade.** Every change is profiled against the original arcade game running the same input movies.
- **MVS only.** An AES (home console) version was dropped: the game's live data needs the MVS backup RAM.

## Features

- **The complete arcade game.** All nations (pilots), stages, bosses, attract mode and two-player play.
- **Original sound.** The arcade's Z80 sound program is patched to drive the Neo Geo's YM2610, with the arcade's own timing.
- **Video conversion on the Neo Geo.** The arcade's two scrolling tilemaps, its sprites and its palette are converted in real time into Neo Geo sprite columns, the fix layer and Neo Geo palettes.
- **Graphics converted at build time.** The arcade's tile and sprite graphics become the Neo Geo C, S and V ROMs. Common sprite shapes are precomputed into ROM templates.
- **Timing model detected at boot.** One ROM runs on both MAME and the MiSTer core. It measures the machine's interrupt timing when it starts.
- **Neo Geo integration.** The set has its own NGH number (0x0538, unused by any released title). Universe BIOS soft dips work, and the Universe BIOS splash shows the Video System emblem.
- **A MAME-only "assist" set (`aerofgtna`).** It adds an emulated board that performs the video conversion. That makes it pixel exact against the arcade at a constant two-frame offset. It is a reference for testing and cannot exist as a real cartridge.

## Requirements

- Linux with Python 3 (tested with 3.14), NumPy and Pillow.
- The vasm assembler, built for 68000 (Motorola syntax) and Z80 (oldstyle syntax), in `third_party/vasm`. It is not part of this repository: download the source from http://sun.hasenbraten.de/vasm/ and unpack it there.
- ROM sets you own, placed in `mame_roms/`:
  - `aerofgt.zip`: the Aero Fighters arcade set.
  - `sonicwi3.zip` or any other Neo Geo MVS set: the converter reuses its BIOS security block.
  - `neogeo.zip`: the Neo Geo BIOS, to run the result.
- For running it: MAME with the `aerofgtn` driver entry (see below), or a MiSTer with the Neo Geo core.

- MAME, for making the emblem image below. Any recent MAME with the `aerofgt` driver works.

Build vasm once:

```sh
cd third_party/vasm
make CPU=m68k SYNTAX=mot
make CPU=z80 SYNTAX=oldstyle
```

## Building

Make the Video System emblem image once. The release build's Universe BIOS splash (`UB_LOGO=1`) uses it. The image is copyrighted artwork, so it is not part of this repository. The tool takes it from your own `aerofgt.zip`: it runs the arcade set in MAME to the attract mode's logo screen, crops the emblem and writes `tools/vslogo.png`.

```sh
python3 -I tools/make_vslogo.py --mame mame --rompath mame_roms
```

It takes about half a minute. `--mame` names your MAME executable if it is not on the path as `mame`. Without the image, leave `UB_LOGO=1` out of the switches below. The build then works, but the Universe BIOS splash shows scrambled game tiles where its logo should be.

Then build the cartridge set.

Run the converter from the project root. The release build uses the direct video path with the switches below:

```sh
AEROFGT_DIRECT=1 \
AEROFGT_DEFS="FUSED=1,GX_XPRE=1,FZ_PD=1,GX_SCAN=1,FZ_TPL=1,FX_HOV=1,BG_HIDECLR=1,BG_SETSCR=1,UB_LOGO=1,BG_CUTCAP=1,BG_SCRRING=1,SPR_FLIPRES=1,FX_HOVCHG=1,GX_BAND=1" \
python3 -I tools/aerofgt2neo.py --aerofgt mame_roms/aerofgt.zip --secref mame_roms/sonicwi3.zip --out out
```

The build takes a few seconds. It writes:

| Output | Contents |
|---|---|
| `out/aerofgtn/` and `out/aerofgtn.zip` | The cartridge set: `538-p1.p1`, `538-s1.s1`, `538-m1.m1`, `538-v1.v1`, `538-c1.c1`, `538-c2.c2` |
| `out/aerofgtna/` and `out/aerofgtna.zip` | The MAME-only assist set |
| `out/aerofgtn_driver.txt` | The MAME `ROM_START` block with CRCs and SHA1s |
| `out/build/` | Build logs, the HAL listing `hal.lst`, intermediate binaries |

Without `AEROFGT_DIRECT` and `AEROFGT_DEFS` the tool makes the plain build. It is kept byte-identical between changes as a regression check.

New work is added behind `AEROFGT_DEFS` switches. A build with a new switch turned off must be byte-identical to the previous release.

### Expected checksums

The release command above, with the emblem image made by `tools/make_vslogo.py`, produces exactly these files. If yours differ, check that your `aerofgt.zip` is the MAME dump the converter expects; it stops with an error if a file's CRC is wrong. The Neo Geo set given with `--secref` does not change them: `sonicwi3.zip` and `sonicwi2.zip` give the same files.

The cartridge set, `out/aerofgtn/` (release fz69):

| File | Size | CRC32 | SHA1 |
|---|---|---|---|
| `538-p1.p1` | 1,048,576 | `c2531b64` | `f5d797f8a8a4f98589d5c0ff12bda9a25ad58e96` |
| `538-s1.s1` | 131,072 | `0d03fe97` | `66c4bd3fd4f96b6e091a3dd940f2b3dbd9532a57` |
| `538-m1.m1` | 131,072 | `099dcce7` | `72afbb063e1be6a013c5d0921b76763f1383879e` |
| `538-v1.v1` | 2,097,152 | `b72e6abe` | `a7276d1cb693286fe87f945c9254e2f62bf28acb` |
| `538-c1.c1` | 8,388,608 | `c789a87b` | `f1a5eeea423ff4c17dc6b1c9156ee10e25aa82b4` |
| `538-c2.c2` | 8,388,608 | `b66fd318` | `fa1ce9981d380cb4ea0c6fc9524f198c8ec8a9aa` |

The MAME-only assist set, `out/aerofgtna/`, made by the same command:

| File | Size | CRC32 | SHA1 |
|---|---|---|---|
| `538a-p1.p1` | 1,048,576 | `3a860c30` | `80976e29adc157294b6be7cfd125145a5d867e95` |
| `538a-t1.bin` | 1,048,576 | `5bcd6831` | `1479c87dc3454203e1df16dc59f5180434e98fcb` |
| `538a-t2.bin` | 4,194,304 | `2f66876b` | `db7c4ecc7b562f4d27df08400c46aa9c1cc38b95` |

To check a build:

```sh
sha1sum out/aerofgtn/* out/aerofgtna/*
```

## Running

**MAME.** Add the `aerofgtn` set to `src/mame/snk/neogeo.cpp` using `out/aerofgtn_driver.txt`, list it in `mame.lst`, and rebuild MAME. The assist set needs the `aerofgtn_assist_state` driver class. Then run:

```sh
mame aerofgtn -rompath "out;mame_roms"
```

**MiSTer.** Copy the six `538-*` files into a folder under `games/NeoGeo/` and add an `aerofgtn` entry to that folder's `romsets.xml`, as for other Neo Geo conversions. The MVS system type is required. Both the stock MVS BIOS and Universe BIOS work.

## Testing

The test tools live in `tests/` and `work/play/`. The main ones:

- **RAM equivalence.** `tests/harness.lua` plays an input movie and dumps RAM each frame, on the arcade and on the conversion. `tests/compare_state.py` compares the two.
- **Lag and lost frames.** `work/play/fp/runlag.sh` measures lost logic frames, late sprite sets, sprite drops and overruns on a movie.
- **The profile matrix.** `work/play/fp/matrix.sh` runs two-player games with autofire and boss bombs for every nation and three seeds, on the conversion and the arcade, and reports by stage and boss fight.

## Current status

The current release is **fz69** (2026-10-20). It runs on the MiSTer and in MAME, has been played through on both, and has no known reboots or display faults.

Lost logic frames are frames where the game's logic misses a vblank. The original arcade loses some too. In the profile matrix, the conversion loses fewer than the arcade in every nation:

| Nation | Conversion | Arcade |
|---|---|---|
| 0 | 1.81% | 3.31% |
| 1 | 2.80% | 6.12% |
| 2 | 5.09% | 8.81% |
| 3 | 5.58% | 7.69% |

Sprite sets shown one frame late average 6 to 12% of frames. Dropped sprite frames are 0.1 to 0.8% of frames, mostly in the densest boss fights. Overruns past the vblank deadline number 2 per 600,000 frames in nations 0 to 2 and 22 in nation 3.

The detailed engineering record, with every experiment and its measurements, is `work/catalog/AUDIT.md`.

## To do

- **Dense scenes in nation 3.** The night fleet's densest stretches (70 or more active objects) still trail the arcade by a few points of lost logic, and nation 3 has most of the overruns.
- **Sprite drops in boss fights.** The remaining drops come from a capacity limit of the Neo Geo sprite column ring. Every column-sharing and matching scheme tried so far has been rejected. Load shedding is the one approach left.
- **The bullet pool.** Three versions of a separate pool for bullets and player shots were built and measured (sections 40, 42 and 44 of the audit). None beat the release. Two tuning knobs remain untried, but neither is expected to help the player shots.

## Legal

*Aero Fighters* (*Sonic Wings*) is copyright 1992 Video System Co., Ltd. Neo Geo, MVS and the Neo Geo BIOS are trademarks and copyright of SNK. This project is not affiliated with or endorsed by either company.

This repository contains no game or BIOS ROM data. The converter reads ROM sets you supply and builds the cartridge files locally. You must own the original *Aero Fighters* arcade board and a Neo Geo MVS cartridge to use their ROMs legally. The converted set is derived from those ROMs and must not be distributed.

The converter copies the BIOS security block from a Neo Geo set you own. No SNK code is included in the project's own source.

The repository also leaves out the Video System emblem image used for the Universe BIOS splash (`tools/make_vslogo.py` makes it from your own ROMs), all screenshots and captures of the game, and all dumps and disassemblies of the original program. `.gitignore` enforces this.

Third-party components keep their own licences and are not included. vasm is by Volker Barthelmann and Frank Wille, and is free for non-commercial use under its own terms. MAME is distributed under the GPL-2.0 licence, which applies to the driver changes made to `neogeo.cpp`.

The project's own source code is licensed under the GNU General Public License, version 3. See `LICENSE`.
