-- fhdump.lua: at game frame AT, after the frame's flip: the shown set's heads as the
-- Neo VRAM holds them: column, SCB3 value, SCB4, SCB2, and the SCB1 words of the head's
-- column and the chained columns above it (up to 8).  Env: OUT, AT
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local vi=nil
for name, idx in pairs(m.devices[":spritegen"].items) do
  if name:find("m_videoram") then vi=emu.item(idx) end
end
local out=io.open(os.getenv("OUT"),"w")
local AT=tonumber(os.getenv("AT") or "76")
local SETS=0x10a280; local SSZ=510; local HOFF=10; local HADR=62; local HVAL=286
emu.register_frame_done(function()
  local gf=HARNESS_GAME_FRAME()
  if gf==AT then
    local s=sp:read_i16(0xd00b9c)
    out:write(string.format("gf %d HF %d shown set %d\n",gf,sp:read_u32(0xd0085c),s))
    if s>=0 then
      local ss=SETS+SSZ*s; local nh=sp:read_u16(ss+HOFF)//2
      for i=0,nh-1 do
        local a=sp:read_u16(ss+HADR+2*i); local v=sp:read_u16(ss+HVAL+2*i); local col=a-0x8200
        out:write(string.format(" head %d col %d scb3 %04x (vram %04x) scb4 %04x scb2 %04x\n",i,col,v,vi:read(0x8200+col),vi:read(0x8400+col),vi:read(0x8000+col)))
        local k=0
        while k<8 do
          local c=col+k; local t={}
          for r=0,7 do t[#t+1]=string.format("%04x/%04x",vi:read(64*c+2*r),vi:read(64*c+2*r+1)) end
          out:write(string.format("   col %d scb3 %04x: %s\n",c,vi:read(0x8200+c),table.concat(t," ")))
          k=k+1
          if (vi:read(0x8200+c+1) & 0x40)==0 then break end
        end
      end
    end
    out:close(); m:exit()
  end
end)
