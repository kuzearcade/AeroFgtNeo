local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local RF=tonumber(os.getenv("RF") or "90"); local n=0
emu.register_frame_done(function() n=n+1
  if n==RF then
    local function dump(tag) local t={} for i=0,31,2 do t[#t+1]=string.format("%04x",sp:read_u16(0x400000+i)) end print(tag,table.concat(t," ")) end
    dump("bank as is"); sp:write_u8(0x3a001f,0); dump("bank1"); sp:write_u8(0x3a000f,0); dump("bank0")
    local t={} for i=0,31,2 do t[#t+1]=string.format("%04x",sp:read_u16(0x400000+0x2000+i)) end print("+0x2000",table.concat(t," "))
    m:exit() end end)
