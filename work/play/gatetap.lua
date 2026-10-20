-- gatetap.lua: at each gated hole try (DL_WHY := 3 with DLR_HOLE set): the list's column
-- sum (all entries), the hole, the list's length
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("V_OUT"),"w")
local taps={}; local f=0; local H={}; local n=0
local function onwhy(o,d,m)
  if (o&~1)~=0xd0e5e0 or d~=3 or sp:read_u8(0xd0f6e0)==0 then return end
  local cl=sp:read_u32(0xd0f01a); local bc8=sp:read_u16(0xd0f000+0x1e)  -- FX_BC8?
  local nn=sp:read_u16(0xd0f66c)
  local s=4; for i=0,nn-1 do s=s+((sp:read_u16(cl+8*i+2)>>9)&7)+1 end
  local hole=sp:read_u16(0xd00fe0)-sp:read_u16(0xd00fe2)-1
  n=n+1; if n<=40 or s>hole then out:write(string.format("f%d n %d sum %d hole %d spj %d spg %d cl %06x\n",f,nn,s,hole,sp:read_u16(0xd00fe0),sp:read_u16(0xd00fe2),cl)) out:flush() end
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd0e5e0,0xd0e5e1,"why",onwhy)} end
inst()
emu.register_frame_done(function() f=f+1; if f%300==0 then inst() end end)
