-- colcen.lua (HARNESS_TARGET=orig: the original's tables): frames F0..F1: per object type the mean
-- COLUMNS a frame (each piece: its graphic header's xsize, 16 px a column) and objects a frame; the
-- per-frame column total's p50/p90/max; bomb objects (types 0d, 20, 21) seen.  Env: OUT, F0, F1
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0") or "5000"); local F1=tonumber(os.getenv("F1") or "25000")
local B=0xff0000; local PEND=B+0x60c0; local h={}; local n=0; local tot={}
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 and f<=F1 then local fc=0
    for a=B,PEND-1,0x60 do
      if sp:read_u8(a)~=0 then local t=sp:read_u16(a+0x16); local k=string.format("%02x",t)
        local tab=sp:read_u32(a+0x1a)&0xfffffe; local pcs=sp:read_u8(a+4)+1; local cols=0
        if tab>0 and tab<0x80000 then
          for i=0,pcs-1 do local g=sp:read_u32(tab+14*i)
            if g>0 and g<0x80000 then cols=cols+((sp:read_u8(g+1)&0xe)>>1)+1 end end end
        if not h[k] then h[k]={0,0} end; h[k][1]=h[k][1]+1; h[k][2]=h[k][2]+cols; fc=fc+cols end end
    n=n+1; tot[#tot+1]=fc end
  if f>F1 then local ks={} for k in pairs(h) do ks[#ks+1]=k end table.sort(ks,function(a,b) return h[a][2]>h[b][2] end)
    table.sort(tot); out:write(string.format("frames %d columns/frame p50 %d p90 %d p99 %d max %d\n",n,tot[math.floor(#tot*0.5)],tot[math.floor(#tot*0.9)],tot[math.floor(#tot*0.99)],tot[#tot]))
    for _,k in ipairs(ks) do out:write(string.format("type %s : %.2f objects/frame, %.1f columns/frame\n",k,h[k][1]/n,h[k][2]/n)) end; out:close(); m:exit() end end)
