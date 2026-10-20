-- ubvram.lua: at real frame RF, the Neo sprite VRAM (0x8800 words) and palette RAM (0x400000, 8KB) to OUT.vram / OUT.pal; then exit
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local RF=tonumber(os.getenv("RF") or "150"); local out=os.getenv("OUT"); local n=0; local vi
local dev=m.devices[":spritegen"]; for name,idx in pairs(dev.items) do if name:find("m_videoram") then vi=emu.item(idx) end end
emu.register_frame_done(function() n=n+1
  if n==RF then
    local t={} for i=0,0x87ff do t[#t+1]=string.pack(">I2",vi:read(i)) end
    local f=io.open(out..".vram","wb"); f:write(table.concat(t)); f:close()
    local p={} for i=0,0x1fff,2 do p[#p+1]=string.pack(">I2",sp:read_u16(0x400000+i)) end
    f=io.open(out..".pal","wb"); f:write(table.concat(p)); f:close()
    m:exit() end end)
