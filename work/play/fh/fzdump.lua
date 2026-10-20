-- fzdump.lua: hal/fz.s state per game frame in a window: the record buffers (headers,
-- the first records in hex), the pass state, the sets' heads/columns.  Env: OUT, FROM, TO
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w")
local FROM=tonumber(os.getenv("FROM") or "60"); local TO=tonumber(os.getenv("TO") or "80")
local FZV=0xd0e300; local BUFT={0xd0e510,0xd0e510+1312,0xd0f800}
local SETS=0x10a280; local SSZ=510
local function hex(a,n) local t={} for i=0,n-1 do t[#t+1]=string.format("%02x",sp:read_u8(a+i)) end return table.concat(t) end
local f=0
emu.register_frame_done(function()
  local gf=HARNESS_GAME_FRAME()
  if gf>=FROM and gf<=TO then
    out:write(string.format("gf %d HF %d W %d done %d st %d%d%d DROP %d LATE %d SHOWN %d\n",gf,sp:read_u32(0xd0085c),sp:read_i16(0xd00b98),sp:read_u8(0xd00b9a),
      sp:read_u8(0xd00b68),sp:read_u8(0xd00b69),sp:read_u8(0xd00b6a),sp:read_u32(0xd00ba0),sp:read_u32(0xd00ba4),sp:read_i16(0xd00b9c)))
    out:write(string.format("  FZ rec %08x rtn %08x recs %08x pbuf %08x due %08x left %d ph %d y %d x %d w2 %04x zoom %04x sy %d sx %d\n",
      sp:read_u32(FZV),sp:read_u32(FZV+4),sp:read_u32(FZV+8),sp:read_u32(FZV+12),sp:read_u32(FZV+16),sp:read_i16(FZV+28),sp:read_u8(FZV+30),
      sp:read_i16(FZV+32),sp:read_i16(FZV+34),sp:read_u16(FZV+36),sp:read_u16(FZV+38),sp:read_i16(FZV+40),sp:read_i16(FZV+42)))
    out:write(string.format("  D next %d tabstop %d hudnt %d hudunf %d shape %d done %d nsl %d\n",sp:read_u32(FZV+80),sp:read_u32(FZV+84),sp:read_u32(FZV+88),sp:read_u32(FZV+92),sp:read_u32(FZV+96),sp:read_u32(FZV+100),sp:read_u32(FZV+104)))
    for i=1,3 do
      local a=BUFT[i]; local n=sp:read_u16(a)
      out:write(string.format("  buf%d n %d stamp %d st %d ovf %d magic %08x\n",i-1,n,sp:read_u16(a+2),sp:read_u8(a+4),sp:read_u8(a+5),sp:read_u32(a+8)))
      for r=0,math.min(n,4)-1 do out:write("    rec "..hex(a+16+16*r,16).."\n") end
    end
    for s=0,2 do local ss=SETS+SSZ*s
      out:write(string.format("  set%d hnext %d hmin %d hoff %d zn %d\n",s,sp:read_u16(ss+4),sp:read_u16(ss+8),sp:read_u16(ss+10),sp:read_u16(ss+12)))
    end
    out:flush()
  end
  if gf>TO then out:close(); m:exit() end
end)
