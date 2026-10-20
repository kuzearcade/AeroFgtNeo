-- Histogram of instructions writing the original video RAMs (bot inputs as measure.lua).
dofile(os.getenv("HARNESS_LUA"))
local cpu = manager.machine.devices[":maincpu"]
local space = cpu.spaces["program"]
local hist = {}
local regions = { {"palette",0x1a0000,0x1a07ff}, {"raster",0x1b0000,0x1b07ff}, {"vram",0x1b2000,0x1b5fff},
	{"sprlut",0x1c0000,0x1c7fff}, {"sprram",0x1d0000,0x1d1fff}, {"vreg",0xffff80,0xffff91} }
local taps = {}
for _, r in ipairs(regions) do
	taps[#taps + 1] = space:install_write_tap(r[2], r[3], "vw" .. r[1], function(o, d, m)
		local k = r[1] .. " " .. string.format("%06x", cpu.state["PC"].value)
		hist[k] = (hist[k] or 0) + 1
	end)
end
local n, stop = 0, tonumber(os.getenv("VW_FRAMES") or "20000")
emu.register_frame_done(function()
	n = n + 1
	if n % 300 == 0 then for _, t in ipairs(taps) do t:reinstall() end end
	if n == stop then
		local f = io.open(os.getenv("VW_OUT"), "w")
		for k, v in pairs(hist) do f:write(k .. " " .. v .. "\n") end
		f:close()
		manager.machine:exit()
	end
end)
