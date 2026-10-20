-- yieldtap.lua: every write to FX_HYIELD (0x107fc0): frame, PC, value, D0-D7 (fx_hud_ov: d1 the
-- strip, d6 the slot met, d2-d4 the strip's column/row/row end, d0/d5/d7 the other's).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3600"); local tap
local function inst() if tap then tap:remove() end
  tap=sp:install_write_tap(0x107fc0,0x107fc1,"yield",function(off,data,mask)
    local r={} for i=0,7 do r[#r+1]=string.format("%04x",cpu.state["D"..i].value&0xffff) end
    out:write(string.format("f %d pc %06x val %04x seen %04x d %s\n",HARNESS_GAME_FRAME(),cpu.state["PC"].value,data&0xffff,sp:read_u16(0xd0f18c),table.concat(r," "))) end) end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME() inst()
  if f>=N-5 then out:close(); m:exit() end end)
