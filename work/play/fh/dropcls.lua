-- dropcls.lua (HARNESS_TARGET=neo, botsel.lua): at each sprite drop (HAL_SPR_DROP grows) its class -
-- in an FZ_OVF continuation (FZ_OVFC), one pending (FZ_OVFP), by the ring's sets (HAL_SPR_ORDN; with
-- two, one split or not), the pair-bullet pool on or off - and the ring's shape: the set in work, the
-- shown one, SPS/SPJ, ORD, per set START..END and state, W's HNEXT/HMIN, RING_TOP, GNEXT; the count
-- per class at the end (SUM lines).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N"))
local SETS=0x10a280; local SSZ=510; local K={}; local taps={}
local function ond(o,d,mk) if o~=0xd00ba2 or HARNESS_GAME_FRAME()<1000 then return end
  local c=sp:read_u8(0x10fc3d); local p=sp:read_u8(0x10fc3c); local on=sp:read_u8(0xd00fae); local sps=sp:read_i8(0xd00fde); local bp=sp:read_u8(0xd00fea)
  local w=sp:read_i16(0xd00b98); local sh=sp:read_i16(0xd00b9c)
  local sz={} for s=0,2 do sz[s]=sp:read_u16(0xd00fba+2*s)-sp:read_u16(0xd00fcc+2*s) end
  local k
  if c~=0 then k="in continuation" elseif p~=0 then k="ovf pending" elseif on==3 then k="3 sets in ring" elseif on==2 then k=(sps>=0 and "2 sets, one split" or "2 sets, not split") else k="ordn "..on end
  k=k..(bp~=0 and " (pool on)" or " (pool off)")
  K[k]=(K[k] or 0)+1
  local g={} for s=0,2 do g[#g+1]=string.format("%d..%d",sp:read_u16(0xd00fba+2*s),sp:read_u16(0xd00fcc+2*s)) end
  local ws=w>=0 and SETS+SSZ*w or SETS
  out:write(string.format("gf %d %s W %d shown %d sps %d spj %d ord %d,%d se %s st %d,%d,%d hn %d hm %d top %d gnext %d\n",HARNESS_GAME_FRAME(),k,w,sh,sps,sp:read_u16(0xd00fe0),sp:read_u8(0xd00faf),sp:read_u8(0xd00fb0),table.concat(g," "),sp:read_u8(0xd00b68),sp:read_u8(0xd00b69),sp:read_u8(0xd00b6a),sp:read_u16(ws+4),sp:read_u16(ws+8),sp:read_u16(0xd00fe4),sp:read_u16(0xd00fac)))
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd00ba0,0xd00ba3,"drop",function(o,d,mk) local ok,e=pcall(ond,o,d,mk); if not ok then out:write("ERR "..tostring(e).."\n") end end)} end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end
  if f>=N then for k,v in pairs(K) do out:write(string.format("SUM %s %d\n",k,v)) end; out:close(); m:exit() end end)
