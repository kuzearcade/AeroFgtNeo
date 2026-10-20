-- tabcen.lua: the piece tables the objects use (for the descriptor catalogue, tools/aerofgt2neo.py
-- fz_pd_prepare): every 4 game frames, each active object's C table (+0x1a, pieces 4(a0) + 1) and
-- its B/A table (+0x44 when b43 bit 7 or 6, pieces (b43 & $f) + 1), with its type; unique
-- (table, pieces, kind, type) rows at the end.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "60000")
local B=0x101000; local PEND=B+0x60c0; local seen={}
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f%4==0 and f>300 then
    for a=B,PEND-1,0x60 do if (sp:read_u8(a)&0x80)~=0 then   -- (drawn objects only: bit 7, as fz_pass; a logic-only object's +0x1a is no table)
      local t=sp:read_u16(a+0x16); local c=sp:read_u32(a+0x1a)&0xfffffe; local p=sp:read_u8(a+4)+1
      if c>0 and c<0x80000 then local k=string.format("%06x %d C %04x",c,p,t); if not seen[k] then seen[k]=f end end
      local b=sp:read_u8(a+0x43)
      if (b&0xc0)~=0 then local bt=sp:read_u32(a+0x44)&0xfffffe; local bp=(b&0xf)+1
        if bt>0 and bt<0x80000 then local k=string.format("%06x %d B %04x",bt,bp,t); if not seen[k] then seen[k]=f end end end
    end end
  end
  if f>=N-5 then local ks={} for k in pairs(seen) do ks[#ks+1]=k end; table.sort(ks)
    for _,k in ipairs(ks) do out:write(k.." "..seen[k].."\n") end; out:close(); m:exit() end
end)
