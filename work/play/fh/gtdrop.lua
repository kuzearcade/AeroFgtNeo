-- gtdrop.lua: per 250 game frames the ring's drop anatomy (FUSED=2): DROP, DROPN, BLKN,
-- restarts (DBGI), split set (SPS), GNEXT, PREV, the sets' states/starts/ends, pool state
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000")
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f>0 and f%250==0 then
    local t={} for s=0,2 do t[#t+1]=string.format("%d:%d..%d",sp:read_u8(0xd00b68+s),sp:read_u16(0xd00fba+2*s),sp:read_u16(0xd00fcc+2*s)) end
    out:write(string.format("gf %d DROP %d DROPN %d BLKN %d rst %d sps %d gnext %d prev %d ordn %d sets %s bp_st %d ring_top %d\n",f,sp:read_u32(0xd00ba0),sp:read_u32(0xd00bf8),sp:read_u32(0xd00fc4),sp:read_u16(0xd00baa),sp:read_i8(0xd00fde),sp:read_u16(0xd00fac),sp:read_u16(0xd00fd2),sp:read_u8(0xd00fae),table.concat(t," "),sp:read_u8(0xd00fea),sp:read_u16(0xd00fe4))); out:flush()
  end
  if f>=N then out:close(); m:exit() end
end)
