-- Log YM2610 register writes (port pair, register, value, game frame) for audio
-- equivalence.  Loads the harness for inputs/frame counting.
dofile(os.getenv("HARNESS_LUA"))
local target = os.getenv("HARNESS_TARGET")
local z = manager.machine.devices[":audiocpu"]
local iosp = z.spaces["io"]
local base = target == "neo" and 4 or 0
local out = io.open(os.getenv("YM_OUT"), "w")
local regs = { [0] = 0, [1] = 0 }
-- the Neo Z80 I/O map is 16 bits wide (OUT (n),A puts A on A8-A15), so tap the whole
-- space and filter on the low byte
local t = iosp:install_write_tap(0x0000, target == "neo" and 0xffff or 0x00ff, "ymlog", function(o, d, m)
	local lo = o & 0xff
	if lo < base or lo > base + 3 then return end
	local port = (lo - base) & 3
	local side = port >> 1
	if port & 1 == 0 then
		regs[side] = d & 0xff
	else
		out:write(string.format("%d %d %02x %02x\n", HARNESS_GAME_FRAME(), side, regs[side], d & 0xff))
	end
end)
local n = 0
emu.register_frame_done(function()
	n = n + 1
	if n % 300 == 0 then t:reinstall() end
end)
