-- Record which instructions read each candidate ROM data pointer (original driver).
-- Env: CAND=<file of hex addresses> OUT=<file> FRAMES=<n> MEASURE_SEED (bot as measure.lua)
local cpu = manager.machine.devices[":maincpu"]
local space = cpu.spaces["program"]
local ports = manager.machine.ioport.ports
local out_path, frames = os.getenv("OUT"), tonumber(os.getenv("FRAMES") or "20000")
local seed = tonumber(os.getenv("MEASURE_SEED") or "1")
local cand = {}
for line in io.lines(os.getenv("CAND")) do cand[#cand + 1] = tonumber(line, 16) end
local hits = {}
local taps = {}
for _, a in ipairs(cand) do
	taps[#taps + 1] = space:install_read_tap(a, a + 3, "pp" .. a, function(offset, data, mask)
		local k = string.format("%06x %06x", a, cpu.state["PC"].value)
		hits[k] = (hits[k] or 0) + 1
	end)
end
local rng = seed
local function rnd(n) rng = (rng * 1103515245 + 12345) & 0x7fffffff return rng % n end
local function setf(p, f, v) local pp = ports[p] if pp and pp.fields[f] then pp.fields[f]:set_value(v) end end
local n, joy = 0, 0
emu.register_frame_done(function()
	n = n + 1
	if n % 300 == 0 then for _, t in ipairs(taps) do t:reinstall() end end
	local cyc = n % 600
	setf(":SYSTEM", "Coin 1", (cyc >= 100 and cyc < 106) and 1 or 0)
	setf(":SYSTEM", "Coin 2", (cyc >= 120 and cyc < 126) and 1 or 0)
	setf(":SYSTEM", "1 Player Start", (cyc >= 150 and cyc < 156) and 1 or 0)
	setf(":SYSTEM", "2 Players Start", (cyc >= 170 and cyc < 176) and 1 or 0)
	if n % 12 == 0 then joy = rnd(9) end
	for pl = 1, 2 do
		local pre, port = "P" .. pl .. " ", ":P" .. pl
		local j = (pl == 1) and joy or ((joy + 4) % 9)
		setf(port, pre .. "Up", (j == 1 or j == 5 or j == 6) and 1 or 0)
		setf(port, pre .. "Down", (j == 2 or j == 7 or j == 8) and 1 or 0)
		setf(port, pre .. "Left", (j == 3 or j == 5 or j == 7) and 1 or 0)
		setf(port, pre .. "Right", (j == 4 or j == 6 or j == 8) and 1 or 0)
		setf(port, pre .. "Button 1", (n % 4 < 2) and 1 or 0)
		setf(port, pre .. "Button 2", (rnd(400) == 0) and 1 or 0)
	end
	if n >= frames then
		local f = io.open(out_path, "w")
		for k, v in pairs(hits) do f:write(k .. " " .. v .. "\n") end
		f:close()
		manager.machine:exit()
	end
end)
