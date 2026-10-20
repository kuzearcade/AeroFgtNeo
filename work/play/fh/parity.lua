-- parity.lua: at each flip, the shown set's number (the slot the arcade would first show
-- that round's list in: ov10 FX_LSEQ of the set's list buffer, FUSED FZ_SEQ of the set)
-- against HAL_FRAMES: 0 parity, < 0 earlier than the arcade, > 0 later.  Per 1000 game
-- frames a histogram; at the end the totals, and the flips that showed the same set again
-- (the arcade repeats a list when a round overruns: counted apart).  Env: OUT, TGT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local TGT=os.getenv("TGT") or "ov10"; local N=tonumber(os.getenv("N") or "20000")
local FZV=0xd0e300; local hist={}; local total=0; local lastseq=nil; local repeats=0
local function seqof(s)
  if TGT=="ov10" then local b=sp:read_u16(0xd0e510+192+2*s); if b>4 then return nil end; return sp:read_u16(0xd0f696+2*b) end
  return sp:read_u16(FZV+52+2*s)
end
local taps={}
local function onw(o,d,mk)
  if (o&~1)~=0xd00b9c then return end
  local s=d&0xffff; if s>2 then return end
  local seq=seqof(s); if not seq then return end
  if seq==lastseq then repeats=repeats+1; return end
  lastseq=seq
  local delta=(sp:read_u16(0xd0085e)-seq); if delta>32767 then delta=delta-65536 end
  hist[delta]=(hist[delta] or 0)+1; total=total+1
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd00b9c,0xd00b9d,"p",onw)} end
inst()
local function dump(tag)
  local ks={} for k in pairs(hist) do ks[#ks+1]=k end; table.sort(ks)
  local t={} for _,k in ipairs(ks) do t[#t+1]=string.format("%d:%d",k,hist[k]) end
  out:write(string.format("%s sets shown %d repeats %d  delta(frames vs arcade): %s\n",tag,total,repeats,table.concat(t," "))); out:flush()
end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f>0 and f%1000==0 then inst() end; if f%5000==0 and f>0 then dump("gf "..f) end; if f>=N then dump("end"); out:close(); m:exit() end end)
