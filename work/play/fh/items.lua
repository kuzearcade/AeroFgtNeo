local m=manager.machine; local n=0
emu.register_frame_done(function() n=n+1 if n==3 then for tag,dev in pairs(m.devices) do for name,_ in pairs(dev.items) do if name:lower():find("palet") then print(tag, name) end end end m:exit() end end)
