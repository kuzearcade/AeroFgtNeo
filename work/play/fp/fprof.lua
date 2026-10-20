-- fprof.lua: per game frame (DIRECT build) HAL state + counters + object census at the frame's
-- end (the game's handler, right after the slot), plus the MAME instruction trace of frames
-- FL_FROM..FL_TO to TR_FIFO (fprof.c aggregates it).  Env: FL_FROM FL_TO TR_FIFO OUT
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]; local cpu=m.devices[":maincpu"]
local dbg=m.debugger
local A,B=tonumber(os.getenv("FL_FROM")),tonumber(os.getenv("FL_TO"))
local out=io.open(os.getenv("OUT"),"w"); local st=0
-- object type -> category index (work/catalog/sprites/categories.tsv order)
local CATS={"HUD/text","bosses","city / buildings","enemy aircraft","enemy bullets","explosions","ground enemies","ground structures","items","naval","player","player bomb","player shots","screens","shadows","other"}
local tc={}
do local ci={} for i,c in ipairs(CATS) do ci[c]=i end
  local f=io.open(os.getenv("HOME").."/AeroFgtNeo/work/catalog/sprites/categories.tsv")
  f:read("l")
  for l in f:lines() do local c,t=l:match("^([^\t]+)\t(%x+)"); if c then tc[tonumber(t,16)]=ci[c] or 16 end end
  f:close()
end
local POS={0x0100,0x0800,0x1234,0x2000,0x2800,0x3000,0x3456,0x3800}
local r32,r16,r8=function(a) return sp:read_u32(a) end,function(a) return sp:read_u16(a) end,function(a) return sp:read_u8(a) end
local L32={0xd00ba4,0xd00ba0,0xd00bf8,0xd00be0,0xd00570,0xd00b78,0xd0042c,0xd0055c,0xd00878,0xd0086c,0xd00f4a,0xd0087c,0xd00fc4,0xd00fc0,0xd00558,0xd00428,0xd00bb4,0xd00b7c,0xd007fc,0xd006cc,0xd00fa4}
-- LATE DROP DROPN OVERRUN CARRY MIXN PALDEFER BGDEFER SLOWB TIMN YN DELTAN BLKN RCLN BGMISS PALMISS ZOOM VZN PRIN IDLES APXF
local function cnt(a,n) local c=0; for i=0,n-1 do if r8(a+i)~=0 then c=c+1 end end; return c end
local function stats(f)
  local t={f, r16(0x3c0006)>>7}
  for _,a in ipairs(L32) do t[#t+1]=r32(a) end
  t[#t+1]=r16(0xd0f036)                                      -- FX_UNFIN
  -- state: K0 DEADLINE KDL BUSY EARLY_ST SPR_W SPR_DONE FX_SDONE ORDN SPS SPJ SPG GNEXT PREV SHOWN
  t[#t+1]=r16(0xd0056a); t[#t+1]=r16(0xd00420); t[#t+1]=r16(0xd00bae); t[#t+1]=r8(0xd00f44); t[#t+1]=r16(0xd00568)
  t[#t+1]=sp:read_i16(0xd00b98); t[#t+1]=r8(0xd00b9a); t[#t+1]=r8(0xd0f016); t[#t+1]=r8(0xd00fae); t[#t+1]=sp:read_i8(0xd00fde)
  t[#t+1]=r16(0xd00fe0); t[#t+1]=r16(0xd00fe2); t[#t+1]=r16(0xd00fac); t[#t+1]=r16(0xd00fd2); t[#t+1]=sp:read_i16(0xd00b9c)
  for i=0,2 do t[#t+1]=r8(0xd00b68+i) end                    -- ST[3]
  for i=0,2 do t[#t+1]=r16(0xd00fba+2*i) end                 -- START[3]
  for i=0,2 do t[#t+1]=r16(0xd00fcc+2*i) end                 -- END[3]
  t[#t+1]=r8(0xd00fb2); t[#t+1]=r16(0xd00552); t[#t+1]=r16(0xd0f692); t[#t+1]=r16(0xd0f03e)   -- BLK FIXUSED QN WP
  for i=0,4 do t[#t+1]=r16(0xd0f180+2*i) end                 -- FX_LN[5]
  t[#t+1]=r16(0xd0f006); t[#t+1]=r8(0xd0f6d8); t[#t+1]=r8(0xd0f6d9); t[#t+1]=r8(0xd0f6da); t[#t+1]=r8(0xd0f667)   -- PASS FAILS SKIPN BOFF DLR_ON
  t[#t+1]=r8(0xd0f620); t[#t+1]=r8(0xd0f640)                 -- FX_DELTA FX_PON
  for i=1,14 do t[#t+1]=r16(0xd0e5e2+2*i) end                -- DL_WHYN[1..14]
  t[#t+1]=cnt(0xd00440,64); t[#t+1]=cnt(0xd00500,64); t[#t+1]=cnt(0xd00670,64)   -- PALDIRTY BG_PEND BG_LOW
  -- object census: active slots 0x101000..0x1070c0 stride 0x60, type word +0x16
  local n,n1,c=0,0,{}; for i=1,16 do c[i]=0 end
  local a=0x101000
  while a<0x1070c0 do
    if r8(a)>=0x80 then n=n+1; if a<0x1040c0 then n1=n1+1 end; local k=tc[r16(a+0x16)] or 16; c[k]=c[k]+1 end
    a=a+0x60
  end
  t[#t+1]=n; t[#t+1]=n1; for i=1,16 do t[#t+1]=c[i] end
  local h=0; for _,p in ipairs(POS) do h=(h*31+r16(0xd06000+2*p))%4294967296 end
  t[#t+1]=string.format("%08x",h)
  out:write(table.concat(t," "),"\n")
end
-- the handler's addq.w at 0x9e2 (frame counter), just before the vblank flag's addq at 0x9e8
local tap=sp:install_write_tap(0x109a8e,0x109a8f,"fprof_fc",function(off,data,mask)
  local pc=cpu.state["PC"].value
  if pc>=0x9e2 and pc<=0x9ec then
    local f=HARNESS_GAME_FRAME()+1
    if f>=A and f<=B then stats(f) end
  end
end)
emu.register_frame_done(function()
  tap:reinstall()
  local g=HARNESS_GAME_FRAME()
  if st==0 and g>=A then st=1; dbg:command('trace '..os.getenv("TR_FIFO")..',maincpu,noloop,{tracelog "%d ",totalcycles}') end
  if st==1 and g>B then st=2; dbg:command('trace off,maincpu'); out:close(); m:exit() end
end)
