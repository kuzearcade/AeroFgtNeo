-- per game frame: drop counter delta + active objects by type (frames with drops, and a 1/20 sample of the rest)
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local last=-1; local pd=0
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME(); if f==last then return end; last=f
  local d=sp:read_u32(0xd00ba0); local dd=d-pd; pd=d
  if dd>0 or f%20==0 then
    local t={}
    for a=0x101000,0x1070c0-1,0x60 do
      if sp:read_u8(a)>=0x80 then local ty=sp:read_u16(a+0x16); t[ty]=(t[ty] or 0)+1 end
    end
    local s={}; for k,v in pairs(t) do s[#s+1]=string.format("%x:%d",k,v) end
    out:write(f.." "..dd.." "..table.concat(s,",").."\n")
  end
end)
