-- dropwhy2.lua: at each sprite drop (HAL_SPR_DROP grows): per set its state, START, END, HNEXT,
-- HMIN; GNEXT, RING_TOP, the pool state, SPS/SPJ, ORD, the records left in the pass (FZ_REC ..
-- FZ_RECE) and the columns they would take (fast records: +15; general: the descriptors' +11).
-- Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000"); local FZV=0xd0e300
local SETS=0x10a280; local SSZ=510
local taps={}
local function cols_left()
  local r=sp:read_u32(FZV); local e=sp:read_u32(FZV+76); local n=0; local c=0
  if r<0xd0e000 or e>0xd10000 or e<r then return -1,-1 end
  while r<e and n<120 do
    n=n+1
    if sp:read_u8(r+13)==0xff then c=c+((sp:read_u8(r+15)&0xe)>>1)+1
    else local t=sp:read_u32(r); local p=sp:read_u8(r+15)
      for i=0,p do local x=sp:read_u8(t+14*i+11); c=c+((x&0xe)>>1)+1 end end
    r=r+16
  end
  return n,c
end
local function ond(o,d,mk)
  if o~=0xd00ba2 then return end
  local w=sp:read_i16(0xd00b98)
  local t={} for s=0,2 do local ss=SETS+SSZ*s
    t[#t+1]=string.format("s%d:%d:%d..%d:hn%d:hm%d",s,sp:read_u8(0xd00b68+s),sp:read_u16(0xd00fba+2*s),sp:read_u16(0xd00fcc+2*s),sp:read_u16(ss+4),sp:read_u16(ss+8)) end
  local ord={} for i=0,sp:read_u8(0xd00fae)-1 do ord[#ord+1]=sp:read_u8(0xd00faf+i) end
  local n,c=cols_left()
  local hh={} for s=0,2 do hh[#hh+1]=tostring(sp:read_u16(SETS+SSZ*s+10)//2) end
  out:write(string.format("gf %d W %d %s gnext %d top %d bp %d sps %d spj %d ord %s left %d cols %d busy %d prev %d heads %s\n",HARNESS_GAME_FRAME(),w,table.concat(t," "),sp:read_u16(0xd00fac),sp:read_u16(0xd00fe4),sp:read_u8(0xd0f044),sp:read_i8(0xd00fde),sp:read_u16(0xd00fe0),table.concat(ord,","),n,c,sp:read_u8(0xd00f44),sp:read_u16(0xd00fd2),table.concat(hh,",")))
  out:flush()
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd00ba0,0xd00ba3,"drop",ond)} end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end
  if f%50==0 and f>400 then local t={} for s=0,2 do local ss=SETS+SSZ*s
    t[#t+1]=string.format("s%d:%d:%d..%d:hn%d:hd%d",s,sp:read_u8(0xd00b68+s),sp:read_u16(0xd00fba+2*s),sp:read_u16(0xd00fcc+2*s),sp:read_u16(ss+4),sp:read_u16(ss+10)//2) end
    out:write(string.format("P %d %s prev %d sps %d spj %d top %d\n",f,table.concat(t," "),sp:read_u16(0xd00fd2),sp:read_i8(0xd00fde),sp:read_u16(0xd00fe0),sp:read_u16(0xd00fe4))) end
  if f>=N-5 then out:close(); m:exit() end end)
