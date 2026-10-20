-- vramw.lua: SCB3 writes without the chain bit inside the shown set's columns (not a head
-- of it): PC, column, value, ring state
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local cpu=manager.machine.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("V_OUT"),"w")
local addr=0; local mod=1; local n=0; local taps={}; local f=0
local function onw(o,d,m)
  local a=o&~1
  if a==0x3c0000 then addr=d elseif a==0x3c0004 then mod=d
  elseif a==0x3c0002 then
    local va=addr; addr=(addr+mod)&0xffff
    if va>=0x8200+43 and va<=0x8200+380 and (d&0x40)==0 and (d&0x3f)==0 then
      local col=va-0x8200
      local s=sp:read_i16(0xd00b9c)
      if s>=0 and s<3 then
        local hi=sp:read_u16(0xd00fba+2*s)-1; local lo=sp:read_u16(0xd00fcc+2*s)
        local inside=col>=lo and col<=hi
        if sp:read_i8(0xd00fde)==s and col>=sp:read_u16(0xd00fe2) and col<sp:read_u16(0xd00fe0) then inside=false end
        if inside then
          local ss=0x10a280+510*s; local nh=sp:read_u16(ss+10)//2; local head=false
          for k=0,nh-1 do if sp:read_u16(ss+62+2*k)==va then head=true end end
          if not head and n<200 then n=n+1
            out:write(string.format("f%d gf %d pc %06x col %d val %04x shown %d [%d..%d] W %d gnext %d ordn %d\n",f,sp:read_u16(0xd0085e),cpu.state["PC"].value,col,d,s,hi,lo,sp:read_i16(0xd00b98),sp:read_u16(0xd00fac),sp:read_u8(0xd00fae))); out:flush()
          end
        end
      end
    end
  end
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0x3c0000,0x3c0005,"vw",onw)} end
inst()
emu.register_frame_done(function() f=f+1; if f%300==0 then inst() end end)
