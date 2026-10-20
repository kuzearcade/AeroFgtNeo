dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local z=manager.machine.devices[":audiocpu"]
local f=0; local H={}
emu.register_frame_done(function() f=f+1
  local pc=z.state["PC"].value
  local k=string.format("%04x",pc&0xfff0)
  H[k]=(H[k] or 0)+1
  if f==60 or f==200 or f==400 or f==1000 then local ks={} for k,v in pairs(H) do ks[#ks+1]=k end table.sort(ks,function(a,b) return H[a]>H[b] end)
    local s={} for i=1,math.min(#ks,8) do s[#s+1]=ks[i]..":"..H[ks[i]] end print("F"..f.." "..table.concat(s," ")) H={} end end)
