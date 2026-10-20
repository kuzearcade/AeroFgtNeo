-- dropwhy.lua: at each sprite drop (HAL_SPR_DROP grows): the ring then: the set in work's
-- HNEXT/HMIN/start, the sets' states/starts/ends, the ring order, a complete set waiting
-- (anyc), split state, the pass's context (game/slot: FZ_GTCTX), the round's busy flag.
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000"); local FZV=0xd0e300
local SETS=0x10a280; local SSZ=510
local taps={}
local function ond(o,d,mk)
  if o~=0xd00ba2 then return end  -- the low word of the long (second write)
  local w=sp:read_i16(0xd00b98); local ss=SETS+SSZ*math.max(w,0)
  local t={} for s=0,2 do t[#t+1]=string.format("%d:%d..%d",sp:read_u8(0xd00b68+s),sp:read_u16(0xd00fba+2*s),sp:read_u16(0xd00fcc+2*s)) end
  local ord={} for i=0,sp:read_u8(0xd00fae)-1 do ord[#ord+1]=sp:read_u8(0xd00faf+i) end
  out:write(string.format("gf %d pc %06x W %d hnext %d hmin %d start %d sets %s ord %s sps %d ctx %d busy %d pass %d\n",HARNESS_GAME_FRAME(),cpu.state["PC"].value,w,sp:read_u16(ss+4),sp:read_u16(ss+8),sp:read_u16(0xd00fba+2*math.max(w,0)),table.concat(t," "),table.concat(ord,","),sp:read_i8(0xd00fde),sp:read_u8(FZV+201),sp:read_u8(0xd00f44),sp:read_u16(FZV+152)))
  out:flush()
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd00ba0,0xd00ba3,"drop",ond)} end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end; if f>=N then out:close(); m:exit() end end)
