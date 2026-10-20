-- bombcen.lua: in frames F0..F1, the objects by type (count/frame) and, per type, the max pieces and the
-- sum of (pieces) - to see what a nation's bomb draws.  Env: OUT, F0, F1
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0") or "5000"); local F1=tonumber(os.getenv("F1") or "8000")
local B=0x101000; local PEND=B+0x60c0; local h={}; local n=0; local presses=0; local prev=-1
local PL={B+0x6c0,B+0x720}
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 and f<=F1 then
    for a=B,PEND-1,0x60 do
      if sp:read_u8(a)~=0 then local t=sp:read_u16(a+0x16); local reg=(a<B+0x30c0) and "p1" or (a<B+0x42c0) and "p2" or (a<B+0x48c0) and "grp" or "p3"; local k=string.format("%02x %06x %s",t,sp:read_u32(a+0x1a)&0xfffffe,reg)
        local pcs=sp:read_u8(a+4)+1
        if not h[k] then h[k]={0,0,0} end; h[k][1]=h[k][1]+1; h[k][2]=h[k][2]+pcs; if pcs>h[k][3] then h[k][3]=pcs end end end
    n=n+1 end
  if f>F1 then local ks={} for k in pairs(h) do ks[#ks+1]=k end table.sort(ks,function(a,b) return h[a][2]>h[b][2] end)
    out:write(string.format("frames %d\n",n)); for _,k in ipairs(ks) do out:write(string.format("type %s : %.2f/frame, pieces %.2f/frame, max pieces %d\n",k,h[k][1]/n,h[k][2]/n,h[k][3])) end; out:close(); m:exit() end end)
