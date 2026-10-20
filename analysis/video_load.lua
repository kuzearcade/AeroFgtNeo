-- Per-game-frame video workload of the original: sprites/columns/tiles in the list,
-- palette, tilemap and lookup writes, scroll changes.  Uses the harness for inputs.
dofile(os.getenv("HARNESS_LUA"))
local cpu = manager.machine.devices[":maincpu"]
local space = cpu.spaces["program"]
local cnt = { pal = 0, vram = 0, lut = 0 }
local taps = {
	space:install_write_tap(0x1a0000, 0x1a07ff, "vl_pal", function() cnt.pal = cnt.pal + 1 end),
	space:install_write_tap(0x1b2000, 0x1b5fff, "vl_vram", function() cnt.vram = cnt.vram + 1 end),
	space:install_write_tap(0x1c0000, 0x1c7fff, "vl_lut", function() cnt.lut = cnt.lut + 1 end),
}
local out = io.open(os.getenv("VL_OUT"), "w")
local last_vbf = nil
local function sprite_stats()
	local nspr, cols, tiles, zoomed = 0, 0, 0, 0
	for offs = 0, 0x1ff do
		local e = space:read_u16(0x1d0000 + offs * 2)
		if (e & 0x4000) ~= 0 then break end
		if (e & 0x8000) == 0 then
			local a = 0x1d0000 + 8 * (e & 0x03ff)
			local w0, w1 = space:read_u16(a), space:read_u16(a + 2)
			local xs, ys = ((w1 >> 9) & 7) + 1, ((w0 >> 9) & 7) + 1
			nspr = nspr + 1; cols = cols + xs; tiles = tiles + xs * ys
			if (w0 >> 12) ~= 0 or (w1 >> 12) ~= 0 then zoomed = zoomed + 1 end
		end
	end
	return nspr, cols, tiles, zoomed
end
local frames = 0
local stop = tonumber(os.getenv("VL_FRAMES") or "20000")
local vtap = space:install_write_tap(0xff8054, 0xff8055, "vl_vbf", function(o, d, m)
	local pc = cpu.state["PC"].value
	if pc >= 0x9e8 and pc <= 0x9f2 then
		frames = frames + 1
		local s, c, t, z = sprite_stats()
		out:write(string.format("%d %d %d %d %d %d %d %d\n", frames, s, c, t, z, cnt.pal, cnt.vram, cnt.lut))
		cnt.pal, cnt.vram, cnt.lut = 0, 0, 0
		if frames >= stop then out:close() manager.machine:exit() end
	end
end)
local n = 0
emu.register_frame_done(function()
	n = n + 1
	if n % 300 == 0 then for _, t in ipairs(taps) do t:reinstall() end vtap:reinstall() end
end)
