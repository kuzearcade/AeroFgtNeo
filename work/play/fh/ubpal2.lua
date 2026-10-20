local m=manager.machine; local RF=tonumber(os.getenv("RF") or "90"); local n=0; local it
for name,idx in pairs(m.devices[":"].items) do if name:find("m_paletteram") then it=emu.item(idx) end end
emu.register_frame_done(function() n=n+1 if n==RF then local t={} for p=3,7,4 do local t={} for i=0,15 do t[#t+1]=string.format("%04x",it:read(p*16+i)) end print("pal"..p, table.concat(t," ")) end; local t2={} for i=0x1000,0x100f do t2[#t2+1]=string.format("%04x",it:read(i)) end print("bank1 pal0",table.concat(t2," ")); m:exit() end end)
