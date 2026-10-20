-- Frame-equivalence harness, shared by the original driver (aerofgt) and the
-- conversion (aerofgtn).
--
-- A "game frame" ends when the original IRQ handler bumps its vblank flag
-- (addq.b #1 at 0x9e8).  At that instant this script
--   * appends every mapped RAM region (original layout order) to HARNESS_DUMP
--   * applies the movie inputs for the next game frame
-- so both machines see identical inputs per game frame regardless of how their
-- real frames line up.
--
-- Env: HARNESS_TARGET=orig|neo  HARNESS_MOVIE=<file>  HARNESS_DUMP=<file>
--      HARNESS_FRAMES=<n>  HARNESS_DUMP_FROM=<n>  HARNESS_SNAP=<dir> (optional PNGs)

local target = os.getenv("HARNESS_TARGET") or "orig"
local movie_path = os.getenv("HARNESS_MOVIE")
local dump_path = os.getenv("HARNESS_DUMP")
local max_frames = tonumber(os.getenv("HARNESS_FRAMES") or "3000")
local dump_from = tonumber(os.getenv("HARNESS_DUMP_FROM") or "0")
local snap_every = tonumber(os.getenv("HARNESS_SNAP_EVERY") or "0")

local machine = manager.machine
local cpu = machine.devices[":maincpu"]
local space = cpu.spaces["program"]
local ports = machine.ioport.ports

-- original region -> address in this machine
local REGIONS = {
	-- name,    orig,     size,    neo
	{ "wram",    0xfef000, 0x10000, 0x100000 },
	{ "palette", 0x1a0000, 0x00800, 0xd01000 },
	{ "raster",  0x1b0000, 0x00800, 0xd01800 },
	{ "vram",    0x1b2000, 0x04000, 0xd02000 },
	{ "sprlut",  0x1c0000, 0x08000, 0xd06000 },
	{ "sprram",  0x1d0000, 0x02000, 0xd0e000 },
}
local function addr(r) return target == "neo" and r[4] or r[2] end
local VBF = target == "neo" and 0x109054 or 0xff8054

-- ------------------------------------------------------------------ movie
local movie = {}
if movie_path then
	for line in io.lines(movie_path) do
		local f, p1, p2, sys = line:match("^(%d+)%s+(%x+)%s+(%x+)%s+(%x+)")
		if f then movie[tonumber(f)] = { tonumber(p1, 16), tonumber(p2, 16), tonumber(sys, 16) } end
	end
end
local last = { 0xff, 0xff, 0xff }

local function field(port, name)
	local p = ports[port]
	return p and p.fields[name]
end

local orig_map = {
	{ ":P1", { "P1 Up", "P1 Down", "P1 Left", "P1 Right", "P1 Button 1", "P1 Button 2" } },
	{ ":P2", { "P2 Up", "P2 Down", "P2 Left", "P2 Right", "P2 Button 1", "P2 Button 2" } },
}
local neo_map = {
	{ ":edge:joy:JOY1", { "P1 Up", "P1 Down", "P1 Left", "P1 Right", "P1 A", "P1 B" } },
	{ ":edge:joy:JOY2", { "P2 Up", "P2 Down", "P2 Left", "P2 Right", "P2 A", "P2 B" } },
}
-- SYSTEM bits of the original: b0 coin1 b1 coin2 b2 start1 b3 start2 b6 service
local sys_orig = { [0] = { ":SYSTEM", "Coin 1" }, [1] = { ":SYSTEM", "Coin 2" }, [2] = { ":SYSTEM", "1 Player Start" },
	[3] = { ":SYSTEM", "2 Players Start" }, [6] = { ":SYSTEM", "Service 1" } }
local sys_neo = { [0] = { ":AUDIO_COIN", "Coin 1" }, [1] = { ":AUDIO_COIN", "Coin 2" }, [2] = { ":edge:joy:START", "1 Player Start" },
	[3] = { ":edge:joy:START", "2 Players Start" }, [6] = { ":AUDIO_COIN", "Service 1" } }

local function apply_inputs(v)
	local map = target == "neo" and neo_map or orig_map
	for i = 1, 2 do
		local port, names = map[i][1], map[i][2]
		for bit = 0, 5 do
			local f = field(port, names[bit + 1])
			if f then f:set_value(((v[i] >> bit) & 1) == 0 and 1 or 0) end
		end
	end
	local sm = target == "neo" and sys_neo or sys_orig
	for bit, pf in pairs(sm) do
		local f = field(pf[1], pf[2])
		if f then f:set_value(((v[3] >> bit) & 1) == 0 and 1 or 0) end
	end
end

-- ------------------------------------------------------------------ dump
local out = dump_path and io.open(dump_path, "wb") or nil
local game_frame = tonumber(os.getenv("HARNESS_FRAME0") or "0")   -- (a run loaded from a state: its frame)
local by_round = os.getenv("HARNESS_BY_ROUND") == "1"
-- HARNESS_BOTFILE=<lua>: a file defining HARNESS_BOT(game_frame, v) -> v (the three input bytes of
-- the movie's row, to change: autofire, bombs by the game's state); HARNESS_TARGET and HARNESS_SPACE
-- (the program space) are globals for it
HARNESS_TARGET = target; HARNESS_SPACE = space
local botfile = os.getenv("HARNESS_BOTFILE")
if botfile then dofile(botfile) end
local game_round = 0
HARNESS_GAME_FRAME = function() return game_frame end
local done = false

-- the original IRQ also bumps a word frame counter (0xff9a8e); used to detect a dropped tap
local FCOUNT = target == "neo" and 0x109a8e or 0xff9a8e
local last_count = nil
local missed = 0

-- optional (neo only): Neo palette RAM + HAL video counters per game frame
local npal_path = os.getenv("HARNESS_NEOPAL")
local npal_out = npal_path and io.open(npal_path, "wb") or nil

-- optional (neo only): tilemap state as the HAL sees it at virtual vblank (pre-handler),
-- tagged with the game frame it belongs to: raster 0x800, io 0x20 (0xffff80..), vram 0x4000,
-- sprite RAM 0x2000, sprite lookup 0x8000
local pre_path = os.getenv("HARNESS_PRE")
local pre_out = pre_path and io.open(pre_path, "wb") or nil
local pre_tap = nil
local function install_pre()
	if not pre_out then return end
	if pre_tap then pre_tap:remove() end
	pre_tap = space:install_write_tap(0xd0085c, 0xd0085f, "harness_pre", function(offset, data, mask)
		if offset ~= 0xd0085e then return end
		pre_out:write(string.pack("<I4", game_frame + 1))
		pre_out:write(space:read_range(0xd01800, 0xd01fff, 8))
		pre_out:write(space:read_range(0xd00e80, 0xd00e9f, 8))
		pre_out:write(space:read_range(0xd02000, 0xd05fff, 8))
		pre_out:write(space:read_range(0xd0e000, 0xd0ffff, 8))   -- sprite list/attributes
		pre_out:write(space:read_range(0xd06000, 0xd0dfff, 8))   -- sprite lookup
	end)
end

-- optional (neo only): the HAL's variables (0xd00400..0xd00bff) at each game frame end
-- optional Neo sprite VRAM dumps: HARNESS_VRAM=<file> HARNESS_VRAM_RANGE=<from>-<to>
local vram_path = os.getenv("HARNESS_VRAM")
local vram_out = vram_path and io.open(vram_path, "wb") or nil
local vram_from, vram_to = (os.getenv("HARNESS_VRAM_RANGE") or "0-0"):match("(%d+)-(%d+)")
vram_from, vram_to = tonumber(vram_from), tonumber(vram_to)
local vram_item = nil
if vram_out then
	local dev = machine.devices[":spritegen"]
	for name, idx in pairs(dev.items) do
		if name:find("m_videoram") then vram_item = emu.item(idx) end
	end
end
-- optional (neo only): the HAL's slip log (hal/video.s, G_SLIPLOG), streamed: at each
-- game frame end <I4 game frame, I4 records written, H count> and the 32-byte header,
-- then count x <I4 record number> + 8 bytes for every record new or still open since
-- the last frame (big-endian, as in memory; the last copy of a number is final)
local SLOG = 0x10c900
local slog_path = os.getenv("HARNESS_SLIPLOG")
local slog_out = slog_path and io.open(slog_path, "wb") or nil
local slog_seen = 0
local hal_path = os.getenv("HARNESS_HALLOG")
local hal_out = hal_path and io.open(hal_path, "wb") or nil

local pix_path = os.getenv("HARNESS_PIXELS")
local pix_out = pix_path and io.open(pix_path, "wb") or nil
local pending_pix = nil
local shot_at = {}
for v in (os.getenv("HARNESS_SHOT_AT") or ""):gmatch("%d+") do shot_at[tonumber(v)] = true end
local pending_shot = nil

local function on_frame_end()
	game_frame = game_frame + 1
	if shot_at[game_frame] then pending_shot = game_frame end
	if pix_out then pending_pix = game_frame end
	local c = space:read_u16(FCOUNT)
	if last_count and ((c - last_count) & 0xffff) ~= 1 then
		missed = missed + 1
		print(string.format("harness: frame counter jumped %04x -> %04x at game frame %d", last_count, c, game_frame))
	end
	last_count = c
	if out and game_frame >= dump_from then
		out:write(string.pack("<I4", game_frame))
		for _, r in ipairs(REGIONS) do
			local a = addr(r)
			out:write(space:read_range(a, a + r[3] - 1, 8))
		end
	end
	if slog_out then
		local nrec = space:read_u32(SLOG)
		if nrec < slog_seen then slog_seen = 0 end         -- cleared (the boot RAM test)
		local from = math.max(slog_seen - 1, 0, nrec - 220)
		slog_out:write(string.pack("<I4I4I2", game_frame, nrec, nrec - from))
		slog_out:write(space:read_range(SLOG, SLOG + 31, 8))
		for i = from, nrec - 1 do
			local a = SLOG + 32 + 8 * (i % 220)
			slog_out:write(string.pack("<I4", i))
			slog_out:write(space:read_range(a, a + 7, 8))
		end
		slog_seen = nrec
	end
	if hal_out then
		hal_out:write(string.pack("<I4", game_frame))
		hal_out:write(space:read_range(0xd00400, 0xd00bff, 8))
	end
	if vram_out and game_frame >= vram_from and game_frame <= vram_to then
		-- Neo sprite VRAM (0x8800 words, the LSPC's own memory), big-endian words
		local t = {}
		for i = 0, 0x87ff do t[#t + 1] = string.pack(">I2", vram_item:read(i)) end
		vram_out:write(string.pack("<I4", game_frame))
		vram_out:write(table.concat(t))
	end
	if npal_out then
		-- HAL_PALMISS, HAL_PALDEFER, HAL_SLIP, HAL_DEADLINE, then palette RAM
		-- + HAL_PROBE_VPOS, HAL_DBG_COMMIT, HAL_DBG_END
		npal_out:write(string.pack("<I4I4I4I2I2I2I2I2I2", game_frame, space:read_u32(0xd00428), space:read_u32(0xd0042c),
			space:read_u16(0xd00430), space:read_u16(0xd00420), space:read_u16(0xd00432), space:read_u16(0xd00434),
			space:read_u16(0xd00436), space:read_u16(0xd00438)))
		npal_out:write(space:read_range(0x400000, 0x401fff, 8))
	end
	if os.getenv("HARNESS_MARK") and game_frame % 100 == 0 then
		print(string.format("harness: game frame %d at screen frame %d", game_frame, machine.screens[":screen"]:frame_number()))
	end
	if not by_round then
		local v = movie[game_frame + 1] or last
		last = v
		if HARNESS_BOT then v = HARNESS_BOT(game_frame, v) end   -- (HARNESS_BOTFILE: a bot over the movie)
		apply_inputs(v)
	end
	if game_frame >= max_frames and not done then
		done = true
		if out then out:close() end
		if pix_out then pix_out:close() end
		if npal_out then npal_out:close() end
		if hal_out then hal_out:close() end
		if slog_out then slog_out:close() end
		if pre_out then pre_out:close() end
		machine:exit()
	end
end

-- HARNESS_BY_ROUND=1: the movie's inputs are applied per logic round of the game (its
-- frame loop's builder point: the clr.w of the lock 0xff9236 at 0x2bfaa) instead of per
-- vblank handler, so that builds losing different numbers of logic frames still play the
-- same game round for round (work/catalog/AUDIT.md 24, stage 1's A/B).  The inputs are
-- latched by the handler, which samples the value set at the last round's end.
local LOCK = target == "neo" and 0x10a236 or 0xff9236
local round_tap = nil
if by_round then
	round_tap = space:install_write_tap(LOCK, LOCK + 1, "harness_round", function(offset, data, mask)
		local pc = cpu.state["PC"].value
		if pc < 0x2bfaa or pc > 0x2bfb6 then return end
		game_round = game_round + 1
		local v = movie[game_round + 1] or last
		last = v
		if HARNESS_BOT then v = HARNESS_BOT(game_round, v) end   -- (HARNESS_BOTFILE: a bot over the movie, per round here)
		apply_inputs(v)
	end)
end
HARNESS_GAME_ROUND = function() return game_round end

local tap = space:install_write_tap(VBF, VBF + 1, "harness_vbf", function(offset, data, mask)
	-- only the IRQ handler's addq.b #1 at 0x9e8 (PC already advanced past it) ends a
	-- game frame; the boot RAM test also writes patterns here
	local pc = cpu.state["PC"].value
	if (mask & 0xff) ~= 0 and pc >= 0x9e8 and pc <= 0x9f2 then on_frame_end() end
end)

-- optional write watch: HARNESS_WATCH=<orig hex lo>-<orig hex hi>, logged with PC/value
local watch = os.getenv("HARNESS_WATCH")
local watch_tap
if watch then
	local lo, hi = watch:match("(%x+)-(%x+)")
	lo, hi = tonumber(lo, 16), tonumber(hi, 16)
	local wlo = target == "neo" and (lo - 0xfef000 + 0x100000) or lo
	local whi = target == "neo" and (hi - 0xfef000 + 0x100000) or hi
	local wf = tonumber(os.getenv("HARNESS_WATCH_FROM") or "0")
	watch_tap = space:install_write_tap(wlo, whi, "harness_watch", function(offset, data, mask)
		if game_frame >= wf then
			print(string.format("watch gf %d pc %06x a2 %08x a0 %08x addr %06x data %04x mask %04x", game_frame, cpu.state["PC"].value, cpu.state["A2"].value, cpu.state["A0"].value,
				offset - wlo + lo, data, mask))
		end
	end)
end

install_pre()
local real_frame = 0
emu.register_frame_done(function()
	real_frame = real_frame + 1
	tap:reinstall()
	if round_tap then round_tap:reinstall() end
	if pre_tap then pre_tap:reinstall() end
	if pending_pix then
		local px, w, h = machine.screens[":screen"]:pixels()
		pix_out:write(string.pack("<I4I4I4", pending_pix, w, h))
		pix_out:write(px)
		pending_pix = nil
	end
	if pending_shot then
		machine.screens[":screen"]:snapshot(string.format("%s_gf%05d.png", target, pending_shot))
		pending_shot = nil
	end
	if watch_tap then watch_tap:reinstall() end
	if snap_every > 0 and real_frame % snap_every == 0 then
		machine.screens[":screen"]:snapshot(string.format("%s_%06d.png", target, real_frame))
	end
end)
