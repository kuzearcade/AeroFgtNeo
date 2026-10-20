-- fzev.lua: event log of the records pass (FUSED=1 builds; FZ_COST=1 for the refills),
-- each line tagged, with the time (f v c: MAME frame, REG_LSPCMODE's line counter, CPU
-- cycles at 12 MHz; 768 cycles a line, 264 lines a frame):
--   R f v h d7 routine y x charge w2 pieces-1 zoom   a record dispatched (fz_ntab)
--   H f v h d7                                      the HUD pass's start
--   F f v h short KER TAILU k                       hal_spr_refill entry (FZ_COST)
--   G f v h credit                                  its result
--   S f v h set TAILU rec ph HF KDL KER busy est    a pass run's start (fz_go)
--   E f v h pc d7 rec ph left TAILU                 HAL_SPR_RA5 written (stop/done/other)
--   T f v h value                                   HAL_SPR_TAILU written
--   B f v h buf state stamp n pc                    a record buffer's state byte written
--   Q f v h set seq buf                             fz_begin: the set's pass number
--   L f v h set HF                                  the flip (HAL_SPR_SHOWN)
--   N f v h HF                                      HAL_FRAMES low word written
--   Z f v h value                                   HAL_SCH_BUSY written
--   A f v h value                                   HAL_EARLY_ST written
--   O f v h                                         HAL_OVERRUN written
--   U f v h value                                   FZ_LUTGEN written (the HUD refresh, the loader)
-- Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]; local scr=m.screens[":screen"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "20000")
local FZV=0xd0e300
-- the pass's code addresses from the build's listing (env LST = .../build/hal.lst; the
-- fz14 layout's when absent)
local SYM={fz_go=0xc3162,fz_ntab=0xc31b4,fz_bul=0xc3292,fz_fast=0}
do local lst=os.getenv("LST"); if lst then local f=io.open(lst); if f then local on=false
  for l in f:lines() do
    if l:find("^Symbols by name") then on=true elseif l:find("^Symbols by value") then break
    elseif on then local n,a=l:match("^(%S+)%s+A:(%x+)"); if n and SYM[n] then SYM[n]=tonumber(a,16) end end
  end; f:close() end end end
local BUF={[0xd0e514]=0,[0xd0ea34]=1,[0xd0f804]=2}   -- (FZ_BSZ 1312: the terminator record)
-- (f = MAME frame, v = REG_LSPCMODE's line counter (256 + the line), c = CPU cycles, 12 MHz)
local function st() return string.format("%d %d %d",scr:frame_number(),sp:read_u16(0x3c0006)>>7,m.time:as_ticks(12000000)) end
local function d7() return cpu.state["D7"].value end
local function pc() return cpu.state["PC"].value end
local function s16(v) v=v&0xffff; if v>=0x8000 then v=v-65536 end; return v end
local taps={}
local function add(lo,hi,name,fn) taps[#taps+1]=sp:install_write_tap(lo,hi,name,fn) end
local function inst()
  for _,t in ipairs(taps) do t:remove() end; taps={}
  add(FZV+36,FZV+37,"w2",function(o,d,mk)
    local p=pc(); if p<SYM.fz_ntab or p>=SYM.fz_bul then return end
    local r=sp:read_u32(FZV)
    out:write(string.format("R %s %08x %08x %d %d %d %d %d %d %08x\n",st(),d7(),sp:read_u32(r+4),sp:read_i16(r+8),sp:read_i16(r+10),sp:read_u8(r+12),sp:read_u8(r+13),sp:read_u8(r+15),sp:read_u8(r+14)>>4,sp:read_u32(r)))
  end)
  add(FZV+236,FZV+239,"fast",function(o,d,mk)   -- (FZ_FAST, FZ_COST: FZ_COST2 = the fast record fz_fast begins)
    if o~=FZV+236 then return end
    local r=((d&0xffff)<<16)|sp:read_u16(FZV+238)
    r=d   -- (a long write: d is the whole value)
    out:write(string.format("R %s %08x %08x %d %d %d %d %d %d %08x\n",st(),d7(),SYM.fz_fast,sp:read_i16(r+4),sp:read_i16(r+6),sp:read_u8(r+12),sp:read_u16(r+8),0,0,sp:read_u32(r)))
  end)
  add(0xd0f006,0xd0f007,"hp",function(o,d,mk)
    local p=pc(); if p<SYM.fz_ntab or p>=SYM.fz_bul then return end
    out:write(string.format("H %s %08x\n",st(),d7()))
  end)
  add(FZV+232,FZV+233,"rf0",function(o,d,mk)
    out:write(string.format("F %s %d %d %d %d\n",st(),s16(d),sp:read_u16(0xd00bba),sp:read_u16(0xd00bb0),cpu.state["D0"].value&0xffff))
  end)
  add(FZV+234,FZV+235,"rf1",function(o,d,mk) out:write(string.format("G %s %d\n",st(),s16(d))) end)
  add(0xd00bf0,0xd00bf3,"go",function(o,d,mk)
    if o~=0xd00bf0 then return end
    local p=pc(); if p<SYM.fz_go or p>=SYM.fz_ntab then return end
    out:write(string.format("S %s %d %d %08x %d %d %d %d %d %d\n",st(),sp:read_i16(0xd00b98),sp:read_u16(0xd00bb0),sp:read_u32(FZV),sp:read_u8(FZV+30),sp:read_u16(0xd0085e),sp:read_u16(0xd00bae),sp:read_u16(0xd00bba),sp:read_u8(0xd00f44),sp:read_u16(0xd00568)))
  end)
  add(0xd00bf4,0xd00bf7,"ra5",function(o,d,mk)
    if o~=0xd00bf4 then return end
    out:write(string.format("E %s %06x %08x %08x %d %d %d\n",st(),pc(),d7(),sp:read_u32(FZV),sp:read_u8(FZV+30),sp:read_i16(FZV+28),sp:read_u16(0xd00bb0)))
  end)
  add(0xd00bb0,0xd00bb1,"tail",function(o,d,mk) out:write(string.format("T %s %d\n",st(),d&0xffff)) end)
  for a,b in pairs(BUF) do
    add(a,a+1,"bst"..b,function(o,d,mk)
      if (mk&0xff00)==0 then return end
      out:write(string.format("B %s %d %d %d %d %06x\n",st(),b,(d>>8)&0xff,sp:read_u16(a-2),sp:read_u16(a-4),pc()))
    end)
  end
  add(FZV+52,FZV+57,"seq",function(o,d,mk) out:write(string.format("Q %s %d %d %08x\n",st(),(o-(FZV+52))>>1,d&0xffff,sp:read_u32(FZV+12))) end)
  add(0xd00b9c,0xd00b9d,"flip",function(o,d,mk) out:write(string.format("L %s %d %d\n",st(),s16(d),sp:read_u16(0xd0085e))) end)
  add(0xd0085e,0xd0085f,"hf",function(o,d,mk) out:write(string.format("N %s %d\n",st(),d&0xffff)) end)
  add(0xd00f44,0xd00f45,"busy",function(o,d,mk) if (mk&0xff00)==0 then return end; out:write(string.format("Z %s %d\n",st(),(d>>8)&0xff)) end)
  add(0xd00568,0xd00569,"est",function(o,d,mk) out:write(string.format("A %s %d\n",st(),d&0xffff)) end)
  add(0xd0fdf2,0xd0fdf3,"lutgen",function(o,d,mk) out:write(string.format("U %s %d\n",st(),d&0xffff)) end)   -- FZ_LUTGEN (FZ_PD: the HUD refresh / loader)
  add(0xd00be0,0xd00be3,"ovr",function(o,d,mk) if o~=0xd00be2 then return end; out:write(string.format("O %s\n",st())) end)
end
inst()
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f>0 and f%100==0 then out:flush() end
  if f>0 and f%1000==0 then inst() end
  if f>=N then out:close(); m:exit() end
end)
