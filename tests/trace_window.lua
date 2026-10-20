-- Cycle-annotated instruction trace for frame windows.
-- Env: TRACE_OUT=<prefix> TRACE_WINDOWS="a-b,c-d" (frame_done counts)
local prefix = os.getenv("TRACE_OUT")
local windows = {}
for a, b in (os.getenv("TRACE_WINDOWS") or ""):gmatch("(%d+)-(%d+)") do windows[#windows + 1] = { tonumber(a), tonumber(b) } end
local n, last = 0, windows[#windows][2]
emu.register_frame_done(function()
	n = n + 1
	for i, w in ipairs(windows) do
		if n == w[1] then manager.machine.debugger:command(string.format('trace %s_%d.log,maincpu,noloop,{tracelog "%%d ",totalcycles}', prefix, i)) end
		if n == w[2] then manager.machine.debugger:command("trace off,maincpu") end
	end
	if n >= last then manager.machine:exit() end
end)
