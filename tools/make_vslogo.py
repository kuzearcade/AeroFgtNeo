#!/usr/bin/env python3
"""Make tools/vslogo.png, the Video System emblem for the Universe BIOS splash (UB_LOGO=1).

  python3 -I tools/make_vslogo.py [--mame mame] [--rompath mame_roms] [--out tools/vslogo.png]

The emblem is copyrighted artwork, so it is not in the repository. This tool takes it from
your own Aero Fighters ROMs: it runs the arcade set `aerofgt` in MAME with no input, takes a
snapshot of the attract mode's first screen at frame 300 (the Video System logo), crops the
"V SYSTEM" emblem (52 x 44 pixels, without the copyright line under it) and centres it on a
black 64 x 224 RGB image. tools/gfx.py logo_tiles() turns that image into the splash tiles.

Needs MAME (any build with the aerofgt driver), Pillow, and aerofgt.zip in the rompath.
"""

import argparse
import os
import subprocess
import sys
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SHOT_FRAME = 300                    # the attract's Video System screen
EMBLEM = (86, 146, 138, 190)        # the emblem in that screen: left, top, right, bottom
SIZE = (64, 224)                    # the splash image (gfx.logo_tiles)

LUA = """
local n = 0
emu.register_frame_done(function()
	n = n + 1
	if n == %d then
		manager.machine.screens[":screen"]:snapshot("shot.png")
		manager.machine:exit()
	end
end)
""" % SHOT_FRAME


def snapshot(mame, rompath, work):
    """Run aerofgt to SHOT_FRAME in MAME and return the snapshot's path."""
    lua = os.path.join(work, "shot.lua")
    with open(lua, "w") as f:
        f.write(LUA)
    cmd = [mame, "aerofgt", "-rompath", rompath,
           "-snapshot_directory", work, "-nvram_directory", os.path.join(work, "nv"),
           "-cfg_directory", os.path.join(work, "cfg"),
           "-skip_gameinfo", "-nothrottle", "-sound", "none", "-video", "none",
           "-keyboardprovider", "none", "-mouseprovider", "none",
           "-joystickprovider", "none", "-lightgunprovider", "none",
           "-autoboot_script", lua]
    subprocess.run(cmd, cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   timeout=300, check=False)
    shot = os.path.join(work, "shot.png")
    if not os.path.exists(shot):
        sys.exit("make_vslogo: MAME made no snapshot (is aerofgt.zip in %s?)" % rompath)
    return shot


def emblem(shot):
    """The emblem from the snapshot, centred on a black SIZE image."""
    src = Image.open(shot).convert("RGB")
    emb = src.crop(EMBLEM)
    out = Image.new("RGB", SIZE, (0, 0, 0))
    out.paste(emb, ((SIZE[0] - emb.width) // 2, (SIZE[1] - emb.height) // 2))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mame", default="mame", help="the MAME executable")
    ap.add_argument("--rompath", default=os.path.join(ROOT, "mame_roms"),
                    help="the folder holding aerofgt.zip")
    ap.add_argument("--out", default=os.path.join(HERE, "vslogo.png"))
    args = ap.parse_args()
    with tempfile.TemporaryDirectory() as work:
        img = emblem(snapshot(args.mame, os.path.abspath(args.rompath), work))
    img.save(args.out)
    print("wrote %s (%dx%d)" % (args.out, img.width, img.height))


if __name__ == "__main__":
    main()
