-- Log sound commands read by the Z80 and sound-bank selections, per game frame.
dofile(os.getenv("HARNESS_LUA"))
local target = os.getenv("HARNESS_TARGET")
local z = manager.machine.devices[":audiocpu"]
local iosp = z.spaces["io"]
local out = io.open(os.getenv("ZC_OUT"), "w")
local taps = {}
if target == "neo" then
	taps[1] = iosp:install_read_tap(0x0000, 0xffff, "zc", function(o, d, m)
		local port = o & 0xff
		if port == 0x00 then
			out:write(string.format("%d cmd %02x pc %04x\n", HARNESS_GAME_FRAME(), d & 0xff, z.state["PC"].value))
		elseif port == 0x0b then
			out:write(string.format("%d bank %d\n", HARNESS_GAME_FRAME(), (o >> 8) // 2))
		end
	end)
else
	taps[1] = iosp:install_read_tap(0x0c, 0x0c, "zc", function(o, d, m)
		out:write(string.format("%d cmd %02x pc %04x\n", HARNESS_GAME_FRAME(), d & 0xff, z.state["PC"].value))
	end)
	taps[2] = iosp:install_write_tap(0x04, 0x04, "zb", function(o, d, m)
		out:write(string.format("%d bank %d\n", HARNESS_GAME_FRAME(), d & 3))
	end)
end
local n = 0
emu.register_frame_done(function()
	n = n + 1
	if n % 300 == 0 then for _, t in ipairs(taps) do t:reinstall() end end
end)
