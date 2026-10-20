-- pick.lua: dump the screen at the frames listed in SCR_AT (comma separated), then exit
local out = io.open(os.getenv("SCR_OUT"), "wb")
local at, last = {}, 0
for v in string.gmatch(os.getenv("SCR_AT"), "%d+") do at[tonumber(v)] = true; last = math.max(last, tonumber(v)) end
local k = 0
emu.register_frame_done(function()
	k = k + 1
	if at[k] then
		local px, w, h = manager.machine.screens[":screen"]:pixels()
		out:write(string.pack("<I4I4I4", k, w, h)); out:write(px)
	end
	if k >= last then out:close(); manager.machine:exit() end
end)
