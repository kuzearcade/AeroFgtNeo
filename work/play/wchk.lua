-- per walk done in its own slot (FX_WCHK builds): walk number, pieces, pool records, checksum, list words
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local B=0xd00f18; local last=nil
local FXS=0xd0f000; local LT={0xd0e000,0xd0e800,0xd0ec00,0xd0f800,0xd0fc00}
emu.register_frame_done(function()
  local i=sp:read_u16(0xd00f14)
  if last==nil or ((i-last)%65536)>3 then last=i end
  while last~=i do
    local a=B+8*(last%4); local seq=sp:read_u16(a); local n=sp:read_u8(a+2)
    local s=string.format("%d %d %d %08x",seq,n,sp:read_u8(a+3),sp:read_u32(a+4))
    for b=0,4 do
      if sp:read_u16(FXS+0x696+2*b)==seq and sp:read_u16(FXS+0x180+2*b)==n then
        local t={}
        for k=0,4*n-1 do t[#t+1]=string.format("%04x",sp:read_u16(LT[b+1]+2*k)) end
        s=s.." "..table.concat(t,"")
        break
      end
    end
    out:write(s.."\n")
    last=(last+1)%65536
  end
end)
