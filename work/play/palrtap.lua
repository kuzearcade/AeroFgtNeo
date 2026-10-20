-- paltap.lua: palette RAM writes (0x400000-0x401fff) outside the vblank: beam line, PC
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local sp=cpu.spaces["program"]
local scr=manager.machine.screens[":screen"]
local out=io.open(os.getenv("V_OUT"),"w"); local f=0; local taps={}; local H={}; local n=0; local tot=0
local function on0(o,d,m)
  tot=tot+1
  if f<400 then return end
  local v=(sp:read_u16(0x3c0006)>>7)
  local k=string.format("%06x", cpu.state["PC"].value)
  local key=k..((v>=0x110 and v<0x1f0) and " VIS" or " vbl")
  H[key]=(H[key] or 0)+1
  if v>=0x110 and v<0x1f0 and n<60 then n=n+1; out:write(string.format("f%d line %d pc %s a %06x d %04x\n",f,v-0x110,k,o,d)) end
end
local function on(o,d,m) local ok,e=pcall(on0,o,d,m) if not ok and n<3 then n=n+1 out:write("ERR "..tostring(e).."\n") out:flush() end end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_read_tap(0x400000,0x401fff,"palr",on)} end
inst()
emu.register_frame_done(function() f=f+1; if f%300==0 then inst() end
  if f%1000==0 then local ks={} for k,v in pairs(H) do ks[#ks+1]=k end table.sort(ks,function(a,b) return H[a]>H[b] end)
    out:write(string.format("F %d total %d\n",f,tot)); for i=1,math.min(#ks,40) do out:write(string.format("  %8d %s\n",H[ks[i]],ks[i])) end out:flush() end end)
