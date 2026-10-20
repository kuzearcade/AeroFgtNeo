-- gtlog.lua (FUSED=2): an event log of the ring: HAL_SPR_W writes (a build's start/end),
-- FZ_GTWAIT/FZ_GTCTX writes (wait, resume), HAL_SPR_ST writes (set states), HAL_SPR_SHOWN
-- (the flip), HAL_SPR_DROP (drops), with gf, HAL_FRAMES, busy, PC.  Env: OUT, FROM, TO
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local FROM=tonumber(os.getenv("FROM") or "1300"); local TO=tonumber(os.getenv("TO") or "1400")
local FZV=0xd0e300
local function ev(what,o,d,mk)
  local gf=HARNESS_GAME_FRAME(); if gf<FROM or gf>TO then return end
  out:write(string.format("gf %d HF %d busy %d %s off %06x data %04x mask %04x pc %06x | ST %d%d%d W %d wait %d ctx %d\n",gf,sp:read_u32(0xd0085c),sp:read_u8(0xd00f44),what,o,d&0xffff,mk&0xffff,cpu.state["PC"].value,
    sp:read_u8(0xd00b68),sp:read_u8(0xd00b69),sp:read_u8(0xd00b6a),sp:read_i16(0xd00b98),sp:read_u8(FZV+200),sp:read_u8(FZV+201)))
end
local taps={}
local function inst()
  for _,t in ipairs(taps) do t:remove() end
  taps={sp:install_write_tap(0xd00b98,0xd00b99,"w",function(o,d,mk) ev("W",o,d,mk) end),
        sp:install_write_tap(FZV+200,FZV+201,"wt",function(o,d,mk) ev("WAIT/CTX",o,d,mk) end),
        sp:install_write_tap(0xd00b68,0xd00b6b,"st",function(o,d,mk) ev("ST",o,d,mk) end),
        sp:install_write_tap(0xd00b9c,0xd00b9d,"sh",function(o,d,mk) ev("SHOWN",o,d,mk) end),
        sp:install_write_tap(0xd00ba0,0xd00ba3,"dr",function(o,d,mk) if o==0xd00ba2 then ev("DROP",o,d,mk) end end)}
end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end; if f>TO then out:close(); m:exit() end end)
