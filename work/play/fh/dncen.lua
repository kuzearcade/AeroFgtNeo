-- dncen.lua (HARNESS_TARGET=neo, a FUSED/FZ_PD/FZ_TPL build; botsel.lua): the drawn objects of the
-- dense frames by record path - per object type, in frames with at least NMIN active objects in
-- F0..F1: objects a frame, and how many take fz_rec's fast path (one piece, unzoomed, no B/A tables,
-- a descriptor with a ROM template), the pair-bullet pool (type $18 two-piece), or the general path
-- (pieces, B/A, zoom, no template); the general ones by piece count.  Objects: the main loop's slots
-- 0x1010c0..0x107060, drawn when b0 bit 7 is set (fz_pass).  Env: OUT, F0, F1, NMIN
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0")); local F1=tonumber(os.getenv("F1"))
local NMIN=tonumber(os.getenv("NMIN") or "60")
local T={}; local nf=0; local nall=0
local function add(k,f) T[k]=T[k] or {n=0,fast=0,pair=0,gen=0,pc={}}; local t=T[k]; t.n=t.n+1; t[f]=t[f]+1; return t end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 and f<F1 then
    local act=0
    for a=0x1010c0,0x107000,0x60 do if sp:read_u8(a)~=0 then act=act+1 end end
    if act>=NMIN then nf=nf+1
      for a=0x1010c0,0x107000,0x60 do local b=sp:read_u8(a)
        if b>=0x80 then nall=nall+1
          local ty=sp:read_u16(a+0x16); local pcs=sp:read_u8(a+4); local ba=sp:read_u8(a+0x43)&0xc0
          local tab=sp:read_u32(a+0x1a)&0xfffffe; local w=(tab>0 and tab<0x80000) and sp:read_u16(tab) or 0
          local tpl=(w&0x1fff)~=0 and (w&0x4000)~=0
          local k=string.format("%02x",ty&0xff)
          if ty==0x18 and pcs==1 then add(k,"pair")
          elseif pcs==0 and ba==0 and ty~=0x2e and tpl then add(k,"fast")
          else local t=add(k,"gen"); local p=pcs+1; t.pc[p]=(t.pc[p] or 0)+1 end
        end end end end
  if f>=F1 then
    out:write(string.format("frames with >= %d active: %d, drawn objects a frame %.1f\n",NMIN,nf,nall/math.max(nf,1)))
    local ks={} for k in pairs(T) do ks[#ks+1]=k end; table.sort(ks,function(a,b) return T[a].n>T[b].n end)
    local s={fast=0,pair=0,gen=0}
    for _,k in ipairs(ks) do local t=T[k]; s.fast=s.fast+t.fast; s.pair=s.pair+t.pair; s.gen=s.gen+t.gen
      local pc={} for p,c in pairs(t.pc) do pc[#pc+1]=string.format("%dpc:%.1f",p,c/nf) end; table.sort(pc)
      out:write(string.format("type %s  %.2f a frame  fast %.2f pair %.2f general %.2f  %s\n",k,t.n/nf,t.fast/nf,t.pair/nf,t.gen/nf,table.concat(pc," "))) end
    out:write(string.format("total fast %.1f pair %.1f general %.1f a frame\n",s.fast/nf,s.pair/nf,s.gen/nf))
    out:close(); m:exit() end end)
