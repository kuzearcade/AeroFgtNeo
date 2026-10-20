-- shotcen.lua: frames F0..F1: a histogram of the objects of types $0e-$18 by (type, table, pieces, flags $43, zoom);
-- plus per frame the count of such objects.  Env: OUT, F0, F1 (needs botsel via HARNESS_BOTFILE for the nation)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0") or "5000"); local F1=tonumber(os.getenv("F1") or "8000")
local B=0x101000; local PEND=B+0x60c0; local h={}; local n=0
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 and f<=F1 then
    for a=B,PEND-1,0x60 do
      if sp:read_u8(a)~=0 then local t=sp:read_u16(a+0x16)
        if t>=0x0e and t<=0x18 then local k=string.format("type %02x table %06x pieces %d flags %02x zoom %02x",t,sp:read_u32(a+0x1a)&0xfffffe,sp:read_u8(a+4)+1,sp:read_u8(a+0x43),sp:read_u8(a+0x2a)); h[k]=(h[k] or 0)+1 end end end
    n=n+1 end
  if f>F1 then local ks={} for k in pairs(h) do ks[#ks+1]=k end table.sort(ks,function(a,b) return h[a]>h[b] end)
    out:write(string.format("frames %d\n",n)); for _,k in ipairs(ks) do out:write(string.format("%s : %.2f/frame\n",k,h[k]/n)) end; out:close(); m:exit() end end)
