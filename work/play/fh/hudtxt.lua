-- hudtxt.lua: the fix layer shared by tilemap-1 text and the HUD strips: per game frame
-- F0..F1 HAL_FIXUSED, HAL_FIXCLR, FX_HOK, FZ_HCOK, FX_QN and the shadow's strips 0-7
-- (column,row,cells); every FM frames the fix map's non-zero cells.  Env: OUT, N, F0, F1, FM
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "6000")
local F0=tonumber(os.getenv("F0") or "0"); local F1=tonumber(os.getenv("F1") or "999999"); local FM=tonumber(os.getenv("FM") or "60")
local vi; local dev=m.devices[":spritegen"]; for name,idx in pairs(dev.items) do if name:find("m_videoram") then vi=emu.item(idx) end end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 and f<=F1 then
    local s={}
    for i=0,7 do local b=0x108000+96*i+8; s[#s+1]=string.format("%d:%d,%d,%d",i,sp:read_u16(b),sp:read_u16(b+2),sp:read_u16(b+4)) end
    out:write(string.format("f %d used %d clr %d hok %d hcok %04x qn %d yield %04x %s\n",f,sp:read_u16(0xd00552),sp:read_u16(0xd00554),sp:read_u8(0xd0f015),sp:read_u16(0xd0fdf0),sp:read_u16(0xd0f692),sp:read_u16(0x107fc0),table.concat(s," ")))
    if f%FM==0 then local t={} for c=0,39 do for r=0,31 do local v=vi:read(0x7000+c*32+r) if v~=0 then t[#t+1]=string.format("%d/%d=%04x",c,r,v) end end end
      out:write("fix "..f.." "..table.concat(t," ").."\n") end
    out:flush()
  end
  if f>=N-5 then out:close(); m:exit() end end)
