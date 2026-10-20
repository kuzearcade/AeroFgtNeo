-- svc.lua: the Test switch on from the start; snapshots every SE real frames; exit at N real frames.  Env: N, SE
local m=manager.machine; local n=0; local N=tonumber(os.getenv("N") or "1200"); local SE=tonumber(os.getenv("SE") or "60")
local f=m.ioport.ports[":TEST"].fields["Service Mode"]
emu.register_frame_done(function() n=n+1; if f then f:set_value(1) end
  if n%SE==0 then m.screens[":screen"]:snapshot(string.format("svc_%05d.png",n)) end
  if n>=N then m:exit() end end)
