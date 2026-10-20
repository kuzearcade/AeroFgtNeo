-- Display a grid of C-ROM tiles with Neo sprites and dump the screen.
-- Env: GFX_TILES=<file of 280 hex tile numbers> GFX_OUT=<raw ARGB dump> GFX_AT=<frame>
local machine = manager.machine
local space = machine.devices[":maincpu"].spaces["program"]
local tiles = {}
for l in io.lines(os.getenv("GFX_TILES")) do tiles[#tiles + 1] = tonumber(l, 16) end
local at = tonumber(os.getenv("GFX_AT") or "900")
local n = 0
local function vw(addr, val)                 -- write one Neo VRAM word
	space:write_u16(0x3c0000, addr)
	space:write_u16(0x3c0002, val)
end
local function setup()
	space:write_u16(0x3c0004, 1)             -- VRAMMOD 1
	-- palette 1: pen p -> R=2p G=31-2p B=p (5-bit), mapped to Neo format
	for p = 0, 15 do
		local r, g, b = 2 * p, 31 - 2 * p, p
		local w = ((r & 1) << 14) | ((g & 1) << 13) | ((b & 1) << 12) | ((r >> 1) << 8) | ((g >> 1) << 4) | (b >> 1)
		space:write_u16(0x400000 + 0x20 + 2 * p, w)
	end
	space:write_u16(0x401ffe, 0x8000)        -- backdrop black
	for col = 0, 19 do
		local spr = 1 + col
		for row = 0, 13 do
			local t = tiles[col * 14 + row + 1]
			vw(spr * 64 + row * 2, t & 0xffff)
			vw(spr * 64 + row * 2 + 1, 0x0100 | (((t >> 16) & 15) << 4))
		end
		for row = 14, 31 do vw(spr * 64 + row * 2, 0); vw(spr * 64 + row * 2 + 1, 0) end
		vw(0x8000 + spr, 0x0fff)                        -- no shrink
		vw(0x8200 + spr, ((496 - 0) << 7) | 14)          -- y top, 14 tiles
		vw(0x8400 + spr, (col * 16) << 7)                -- x
	end
end
emu.register_frame_done(function()
	n = n + 1
	if n >= at - 3 and n <= at then setup() end
	if n == at + 2 then
		local px, w, h = machine.screens[":screen"]:pixels()
		local f = io.open(os.getenv("GFX_OUT"), "wb")
		f:write(string.pack("<I4I4", w, h)); f:write(px); f:close()
		machine:exit()
	end
end)
