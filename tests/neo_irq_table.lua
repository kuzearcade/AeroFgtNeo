-- Dump the HAL diagnostics ring (dX, dRES, dTnext per frame) at a given frame.
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local stop = tonumber(os.getenv("STOP_FRAME") or "412")
local out = io.open(os.getenv("RING_OUT"), "w")
local n = 0
emu.register_frame_done(function()
	n = n + 1
	if n == stop then
		local frames = sp:read_u32(0xd0085c)
		out:write(string.format("frames %d\n", frames))
		for i = 0, 31 do
			local a = 0xd00880 + i * 12
			out:write(string.format("%d %d %d %d\n", i, sp:read_i32(a), sp:read_i32(a + 4), sp:read_i32(a + 8)))
		end
		out:close()
		manager.machine:exit()
	end
end)
