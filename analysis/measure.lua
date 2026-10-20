-- Phase 1 measurement script for the original aerofgt driver.
-- Usage: mame aerofgt -autoboot_script analysis/measure.lua
-- Env:   MEASURE_OUT=<dir>  MEASURE_FRAMES=<n>  MEASURE_SEED=<n>  MEASURE_MOVIE=<file>
local out_dir = os.getenv("MEASURE_OUT") or "."
local max_frames = tonumber(os.getenv("MEASURE_FRAMES") or "20000")
local seed = tonumber(os.getenv("MEASURE_SEED") or "1")
local movie_file = os.getenv("MEASURE_MOVIE")
local skip = tonumber(os.getenv("MEASURE_SKIP") or "400")
local recording = false
local frame = 0
local lag_frames = {}

local machine = manager.machine
local cpu = machine.devices[":maincpu"]
local space = cpu.spaces["program"]
local ports = machine.ioport.ports

-- ------------------------------------------------------------------
-- memory touch bitmaps (one entry per word address)
local regions = {
	{ name = "palette", lo = 0x1a0000, hi = 0x1a07ff },
	{ name = "raster",  lo = 0x1b0000, hi = 0x1b0fff },
	{ name = "vram0",   lo = 0x1b2000, hi = 0x1b3fff },
	{ name = "vram1",   lo = 0x1b4000, hi = 0x1b5fff },
	{ name = "sprlut",  lo = 0x1c0000, hi = 0x1c7fff },
	{ name = "sprram",  lo = 0x1d0000, hi = 0x1d1fff },
	{ name = "wram",    lo = 0xfef000, hi = 0xffefff },
	{ name = "io",      lo = 0xffff80, hi = 0xffffff },
}
local touched_r, touched_w = {}, {}
local hook_r, hook_w = {}, {}   -- per-word-address extra handlers (one tap per range only)
local taps = {}
for _, r in ipairs(regions) do
	touched_r[r.name] = {}
	touched_w[r.name] = {}
	local tr, tw = touched_r[r.name], touched_w[r.name]
	taps[#taps + 1] = space:install_read_tap(r.lo, r.hi, "m_r_" .. r.name, function(offset, data, mask)
		if recording then tr[offset & ~1] = true end
		local h = hook_r[offset & ~1]; if h then h(offset, data, mask) end
	end)
	taps[#taps + 1] = space:install_write_tap(r.lo, r.hi, "m_w_" .. r.name, function(offset, data, mask)
		if recording then tw[offset & ~1] = true end
		local h = hook_w[offset & ~1]; if h then h(offset, data, mask) end
	end)
end
-- accesses anywhere else (unmapped / unexpected)
local odd = {}
taps[#taps + 1] = space:install_write_tap(0x080000, 0x19ffff, "m_w_odd", function(offset, data, mask)
	odd[string.format("W%06x", offset)] = (odd[string.format("W%06x", offset)] or 0) + 1
end)

-- gfxbank / scroll register shadows (write-only on hardware)
local gfxbank = { [0] = 0, 0, 0, 0 }
local scrolly = { [0] = 0, 0 }
local bank_writes = 0
local function vreg_w(offset, data, mask)
	if offset <= 0xffff87 then
		local i = (offset - 0xffff80) >> 1
		if gfxbank[i] ~= data then bank_writes = bank_writes + 1 end
		gfxbank[i] = data
	elseif offset == 0xffff88 then scrolly[0] = data
	elseif offset == 0xffff90 then scrolly[1] = data end
end
for a = 0xffff80, 0xffff90, 2 do hook_w[a] = vreg_w end

-- vblank flag (0xff8055): IRQ does addq.b #1, main loop waits for >=1 then clears.
-- written value >= 2 means the main loop missed a frame (lag frame).
local lag_count, t_irq, armed, busy_max, busy_hist = 0, nil, false, 0, {}
local lag_list = {}
local function vbf_w(offset, data, mask)
	if (mask & 0xff) == 0 then return end
	local v = data & 0xff
	if v ~= 0 then
		t_irq = manager.machine.time:as_double()
		if v >= 2 and recording then lag_count = lag_count + 1; lag_list[#lag_list + 1] = frame end
	else
		armed = true   -- main loop consumed the flag and starts the frame's work
	end
end
local function vbf_r(offset, data, mask)
	if (mask & 0xff) == 0 or not armed or not t_irq or (data & 0xff) ~= 0 then return end
	armed = false  -- first poll after the work is done
	local busy = (manager.machine.time:as_double() - t_irq) * 61.31
	if recording then
		if busy > busy_max then busy_max = busy end
		local b = math.floor(busy * 20)
		busy_hist[b] = (busy_hist[b] or 0) + 1
	end
end

hook_w[0xff8054] = vbf_w
hook_r[0xff8054] = vbf_r

-- sound command log
local sndcmds = {}
local function snd_w(offset, data, mask)
	local v = data & 0xff
	sndcmds[v] = (sndcmds[v] or 0) + 1
end
hook_w[0xffffc0] = snd_w

-- ------------------------------------------------------------------
-- input bot
local rng_state = seed
local function rnd(n)
	rng_state = (rng_state * 1103515245 + 12345) & 0x7fffffff
	return rng_state % n
end
local function setf(port, field, v)
	local p = ports[port]
	if p and p.fields[field] then p.fields[field]:set_value(v) end
end

local movie = nil
if movie_file then
	movie = {}
	for line in io.lines(movie_file) do
		local f, p1, p2, sys = line:match("^(%d+)%s+(%x+)%s+(%x+)%s+(%x+)")
		if f then movie[tonumber(f)] = { tonumber(p1, 16), tonumber(p2, 16), tonumber(sys, 16) } end
	end
end

local joy = 0
local function bot(frame)
	-- coins / start periodically so the game keeps being played
	local cyc = frame % 600  -- frequent coins + starts: continue forever so stages advance
	setf(":SYSTEM", "Coin 1", (cyc >= 100 and cyc < 106) and 1 or 0)
	setf(":SYSTEM", "Coin 2", (cyc >= 120 and cyc < 126) and 1 or 0)
	setf(":SYSTEM", "1 Player Start", (cyc >= 150 and cyc < 156) and 1 or 0)
	setf(":SYSTEM", "2 Players Start", (cyc >= 170 and cyc < 176) and 1 or 0)
	if frame % 12 == 0 then joy = rnd(9) end
	for pl = 1, 2 do
		local pre = "P" .. pl .. " "
		local port = ":P" .. pl
		local j = (pl == 1) and joy or ((joy + 4) % 9)
		setf(port, pre .. "Up", (j == 1 or j == 5 or j == 6) and 1 or 0)
		setf(port, pre .. "Down", (j == 2 or j == 7 or j == 8) and 1 or 0)
		setf(port, pre .. "Left", (j == 3 or j == 5 or j == 7) and 1 or 0)
		setf(port, pre .. "Right", (j == 4 or j == 6 or j == 8) and 1 or 0)
		setf(port, pre .. "Button 1", (frame % 4 < 2) and 1 or 0)
		setf(port, pre .. "Button 2", (rnd(400) == 0) and 1 or 0)
	end
end

-- ------------------------------------------------------------------
-- per-frame statistics
local pc_hist = {}
local max_line_cols, max_total_cols, max_sprites = 0, 0, 0
local line_hist = {}
local zoom_tuples = {}
local meta = {}
local meta_count = 0
local meta_pal_conflict = 0
local frame_line_worst = {}

local function r16(a) return space:read_u16(a) end

local function sprite_stats()
	local line_cols = {}
	local total = 0
	local nspr = 0
	for offs = 0, 0x1fff // 16 - 1 do
		local e = r16(0x1d0000 + offs * 2)
		if (e & 0x4000) ~= 0 then break end
		if (e & 0x8000) == 0 then
			local a = 0x1d0000 + 8 * (e & 0x03ff)
			local w0, w1, w2 = r16(a), r16(a + 2), r16(a + 4)
			local oy, ysize, zy = w0 & 0x1ff, (w0 >> 9) & 7, (w0 >> 12) & 0xf
			local ox, xsize, zx = w1 & 0x1ff, (w1 >> 9) & 7, (w1 >> 12) & 0xf
			nspr = nspr + 1
			local cols = xsize + 1
			total = total + cols
			if zx ~= 0 or zy ~= 0 then
				local key = string.format("%x,%x,%x,%x", zx, zy, xsize, ysize)
				zoom_tuples[key] = (zoom_tuples[key] or 0) + 1
			end
			local h = ysize * ((32 - zy) // 2) + 16
			for y = 0, h - 1 do
				local sy = (oy + y) & 0x1ff
				if sy < 224 then line_cols[sy] = (line_cols[sy] or 0) + cols end
			end
		end
	end
	local worst = 0
	for _, c in pairs(line_cols) do if c > worst then worst = c end end
	if worst > max_line_cols then max_line_cols = worst end
	if total > max_total_cols then max_total_cols = total end
	if nspr > max_sprites then max_sprites = nspr end
	line_hist[worst] = (line_hist[worst] or 0) + 1
	return worst
end

local function meta_stats()
	for layer = 0, 1 do
		local base = 0x1b2000 + layer * 0x2000
		for my = 0, 31 do
			for mx = 0, 31 do
				local parts = {}
				local cols = {}
				local ncol = 0
				for dy = 0, 1 do
					for dx = 0, 1 do
						local code = r16(base + ((my * 2 + dy) * 64 + mx * 2 + dx) * 2)
						local bank = (layer << 2) | ((code & 0x1800) >> 11)
						local bv = gfxbank[bank >> 1]
						bv = ((bank & 1) == 0) and ((bv >> 8) & 0xff) or (bv & 0xff)
						local tile = (code & 0x07ff) | (bv << 11)
						local col = (code & 0xe000) >> 13
						parts[#parts + 1] = string.format("%x:%x", tile, col)
						if not cols[col] then cols[col] = true; ncol = ncol + 1 end
					end
				end
				local key = layer .. "|" .. table.concat(parts, ",")
				if not meta[key] then
					meta[key] = true
					meta_count = meta_count + 1
					if ncol > 1 then meta_pal_conflict = meta_pal_conflict + 1 end
				end
			end
		end
	end
end

emu.register_frame_done(function()
	frame = frame + 1
	-- taps are dropped by MAME when handlers get re-installed; re-arm every frame
	for _, t in ipairs(taps) do t:reinstall() end
	local pc = cpu.state["PC"].value
	recording = frame > skip
	if recording then
		pc_hist[pc] = (pc_hist[pc] or 0) + 1
		if pc < 0xb86 or pc > 0xb8e then lag_frames[#lag_frames + 1] = string.format("%d:%06x", frame, pc) end
		sprite_stats()
		if frame % 8 == 0 then meta_stats() end
	end
	if movie then
		local m = movie[frame]
		if m then
			-- raw port values are written via field toggles in the harness; not used here
		end
	else
		bot(frame)
	end
	if frame >= max_frames then
		local f = io.open(out_dir .. "/measure_" .. seed .. ".txt", "w")
		f:write(string.format("frames %d\n", frame))
		for _, r in ipairs(regions) do
			local nr, nw, lo_w, hi_w = 0, 0, nil, nil
			for a in pairs(touched_r[r.name]) do nr = nr + 1 end
			for a in pairs(touched_w[r.name]) do
				nw = nw + 1
				if not lo_w or a < lo_w then lo_w = a end
				if not hi_w or a > hi_w then hi_w = a end
			end
			f:write(string.format("region %s readwords %d writewords %d wlo %s whi %s\n", r.name, nr, nw,
				lo_w and string.format("%06x", lo_w) or "-", hi_w and string.format("%06x", hi_w) or "-"))
		end
		for k, v in pairs(odd) do f:write(string.format("odd %s %d\n", k, v)) end
		f:write(string.format("sprites max_line_cols %d max_total_cols %d max_sprites %d\n", max_line_cols, max_total_cols, max_sprites))
		for k, v in pairs(line_hist) do f:write(string.format("linehist %d %d\n", k, v)) end
		for k, v in pairs(zoom_tuples) do f:write(string.format("zoom %s %d\n", k, v)) end
		f:write(string.format("meta unique %d palconflict %d bankchanges %d\n", meta_count, meta_pal_conflict, bank_writes))
		for k, v in pairs(pc_hist) do f:write(string.format("pc %06x %d\n", k, v)) end
		f:write(string.format("truelag %d busymax %.3f\n", lag_count, busy_max))
		f:write("truelagframes " .. table.concat(lag_list, " ") .. "\n")
		for k, v in pairs(busy_hist) do f:write(string.format("busy %.2f %d\n", k / 20, v)) end
		for k, v in pairs(sndcmds) do f:write(string.format("snd %02x %d\n", k, v)) end
		f:close()
		-- write bitmaps of touched words for later RAM layout planning
		for _, r in ipairs({ "wram", "sprlut", "sprram" }) do
			local g = io.open(out_dir .. "/touch_" .. r .. "_" .. seed .. ".txt", "w")
			local keys = {}
			for a in pairs(touched_w[r]) do keys[#keys + 1] = a end
			for a in pairs(touched_r[r]) do if not touched_w[r][a] then keys[#keys + 1] = a end end
			table.sort(keys)
			for _, a in ipairs(keys) do
				g:write(string.format("%06x %s%s\n", a, touched_r[r][a] and "r" or "-", touched_w[r][a] and "w" or "-"))
			end
			g:close()
		end
		machine:exit()
	end
end)
