-- fzdiag.lua: hal/fz.s state every 100 game frames (FUSED builds): builds, passes, skips,
-- due drops, the four record buffers (count, stamp, state), HAL_FRAMES, the set states,
-- HAL_SPR_W/DONE, LATE, and the pass state (FZ_PH, FZ_LEFT, FZ_REC).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w")
local N=tonumber(os.getenv("N") or "1500")
local FZV=0xd0e300; local BUFT={0xd0e510,0xd0e510+1312,0xd0f800}
local f=0
emu.register_frame_done(function()
  f=f+1
  if f%100==0 then
    local b={}
    for i=1,3 do local a=BUFT[i]; b[#b+1]=string.format("[%d s%d st%d]",sp:read_u16(a),sp:read_u16(a+2),sp:read_u8(a+4)) end
    out:write(string.format("f%d gf%d HF%d bld %d pass %d skip %d ndue %d bufs %s W%d done%d st %d%d%d late %d ph%d left%d rec%08x due%08x blk%d\n",
      f,HARNESS_GAME_FRAME(),sp:read_u32(0xd0085c),sp:read_u32(FZV+68),sp:read_u32(FZV+72),sp:read_u16(FZV+64),sp:read_u16(FZV+66),
      table.concat(b," "),sp:read_i16(0xd00b98),sp:read_u8(0xd00b9a),sp:read_u8(0xd00b68),sp:read_u8(0xd00b69),sp:read_u8(0xd00b6a),
      sp:read_u32(0xd00ba4),sp:read_u8(FZV+30),sp:read_i16(FZV+28),sp:read_u32(FZV),sp:read_u32(FZV+16),sp:read_u8(0xd00fb2)))
    out:write(string.format("   stops: tab %d hudnt %d hudunf %d shape %d done %d nsl %d next %d\n",sp:read_u32(FZV+84),sp:read_u32(FZV+88),sp:read_u32(FZV+92),sp:read_u32(FZV+96),sp:read_u32(FZV+100),sp:read_u32(FZV+104),sp:read_u32(FZV+80)))
    out:write(string.format("   tail: tmax %d lines (ph %d) n %d mean %.1f  reclaim max %d  begin max %d\n",sp:read_u16(FZV+118),sp:read_u8(FZV+120),sp:read_u16(FZV+122),sp:read_u32(FZV+124)/math.max(1,sp:read_u16(FZV+122)),sp:read_u16(FZV+128),sp:read_u16(FZV+130)))
    out:write(string.format("   hud pass in tails: max %d lines, given %d units, left %d\n",sp:read_u16(FZV+134),sp:read_i16(FZV+136),sp:read_i16(FZV+138)))
    out:flush()
  end
  if f>=N then out:close(); m:exit() end
end)
