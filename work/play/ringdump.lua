dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local vi=emu.item(manager.machine.devices[":spritegen"].items["0/m_videoram"])
local out=io.open(os.getenv("V_OUT"),"w"); local f=0
local F0=tonumber(os.getenv("F0")); local F1=tonumber(os.getenv("F1"))
local lastsh=-1
emu.register_frame_done(function() f=f+1
  local sc=sp:read_u32(0xd0f6fc)
  if f>=F0 and f<=F1 then
    local o={} for q=0,sp:read_u8(0xd00fae)-1 do local st=sp:read_u8(0xd00faf+q); local ss=0x10a280+510*st
      local hh={} for k=0,sp:read_u16(ss+10)//2-1 do hh[#hh+1]=sp:read_u16(ss+62+2*k)-0x8200 end
      o[#o+1]=string.format("%d[st%d %d..%d heads %s]",st,sp:read_u8(0xd00b68+st),sp:read_u16(0xd00fba+2*st),sp:read_u16(0xd00fcc+2*st),table.concat(hh,",")) end
    local c={} for n=43,70 do c[#c+1]=string.format("%d:%04x",n,vi:read(0x8200+n)) end
    out:write(string.format("f%d shown %d sps %d spg %d spj %d gnext %d shon %d shset %d shn %d shend %d shcnt %d W %d\n  %s\n  %s\n",f,sp:read_i16(0xd00b9c),sp:read_i8(0xd00fde),sp:read_u16(0xd00fe2),sp:read_u16(0xd00fe0),sp:read_u16(0xd00fac),sp:read_u8(0xd0f6f2),sp:read_u8(0xd0f6f3),sp:read_u16(0xd0f6f4),sp:read_u16(0xd0f6f6),sc,sp:read_i16(0xd00b98),table.concat(o," "),table.concat(c," "))) out:flush()
  end
end)
