local m=manager.machine; local n=0
emu.register_frame_done(function() n=n+1 if n==5 then for pn,p in pairs(m.ioport.ports) do local fs={} for fn,_ in pairs(p.fields) do fs[#fs+1]=fn end print(pn, table.concat(fs,", ")) end m:exit() end end)
