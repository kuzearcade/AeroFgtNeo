-- sndpath.lua (arcade aerofgt): play each song FIRST..LAST for STEP frames (0x02, then the song); per song, the
-- sound chip writes made from the two code ranges the Neo port never patched (0x0ac0-0x0bd0, 0x15b0-0x1680):
-- count and the first time (seconds into the song).  Env: OUT, FIRST, LAST, STEP
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]; local z=m.devices[":audiocpu"]; local zio=z.spaces["io"]
local out=io.open(os.getenv("OUT"),"w")
local F0,STEP,FIRST,LAST=600,tonumber(os.getenv("STEP") or "6000"),tonumber(os.getenv("FIRST") or "32"),tonumber(os.getenv("LAST") or "63")
local n=0; local cur=nil; local c={}
local tap
local function inst() if tap then tap:remove() end
  tap=zio:install_write_tap(0x00,0x03,"ym",function(o,d) local pc=z.state["PC"].value
    local k=(pc>=0x0ad7 and pc<=0x0bcb) and "A" or ((pc>=0x15c8 and pc<=0x1674) and "B" or nil)
    if k and cur then c[k]=(c[k] or 0)+1; if not c[k.."t"] then c[k.."t"]=(n-F0)%STEP/60 end end end) end
inst()
emu.register_frame_done(function() n=n+1; if n%300==0 then inst() end
  if n>=F0 and (n-F0)%STEP==0 then
    if cur then out:write(string.format("song %02x  A(0x0aca ADPCM-B notes) %d first %.1fs  B(0x15bd) %d first %.1fs\n",cur,c.A or 0,c.At or -1,c.B or 0,c.Bt or -1)); out:flush() end
    local x=FIRST+(n-F0)//STEP; if x>LAST then out:close(); m:exit(); return end
    cur=x; c={}; sp:write_u8(0xffffc1,0x02)
  elseif cur and (n-F0)%STEP==20 then sp:write_u8(0xffffc1,cur) end end)
