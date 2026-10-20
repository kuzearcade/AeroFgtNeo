-- menu.lua: the Test switch on; a script of inputs by real frame: SCRIPT="frame:field:frames,..." (fields of :edge:joy:JOY1 or START);
-- snapshots at SHOTS="f,f,..."; exit at N.  Env: SCRIPT, SHOTS, N
local m=manager.machine; local n=0; local N=tonumber(os.getenv("N") or "600"); local TOFF=tonumber(os.getenv("TOFF") or "999999")
local test=m.ioport.ports[":TEST"].fields["Service Mode"]
local joy=m.ioport.ports[":edge:joy:JOY1"].fields; local st=m.ioport.ports[":edge:joy:START"].fields; local co=m.ioport.ports[":AUDIO_COIN"].fields
local acts={} for a,b,c in string.gmatch(os.getenv("SCRIPT") or "","(%d+):([^:,]+):(%d+)") do acts[#acts+1]={tonumber(a),b,tonumber(c)} end
local shots={} for s in string.gmatch(os.getenv("SHOTS") or "","%d+") do shots[tonumber(s)]=true end
local function fld(name) return joy[name] or st[name] or co[name] end
emu.register_frame_done(function() n=n+1; if test then test:set_value(n<TOFF and 1 or 0) end
  for _,a in ipairs(acts) do local f=fld(a[2]); if f then if n>=a[1] and n<a[1]+a[3] then f:set_value(1) elseif n==a[1]+a[3] then f:set_value(0) end end end
  if shots[n] then m.screens[":screen"]:snapshot(string.format("menu_%05d.png",n)) end
  if n>=N then local sp=m.devices[":maincpu"].spaces["program"]; local t={} for i=0,15 do t[#t+1]=string.format("%02x",sp:read_u8(0xd00810+i)) end print("HAL_SOFTDIP",table.concat(t," ")); m.screens[":screen"]:snapshot(string.format("menu_%05d.png",n)); m:exit() end end)
