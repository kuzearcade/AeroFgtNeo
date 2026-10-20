-- bpstate.lua: every E frames (and at every change of BP_ST or BP_NV): frame, BP_ST, BP_NV, BP_LOV, BP_DMAX, BP_DCNT, BP_WANT, BP_SEEN, BP_SHOWN, RING_TOP.  Env: OUT, N, E
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "12000"); local E=tonumber(os.getenv("E") or "60"); local last=""
local FXS=0xd0f000
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  local st=sp:read_u8(0xd00fea); local nv=sp:read_u16(FXS+0x2a0); local k=st..":"..nv
  if f%E==0 or k~=last then
    out:write(string.format("f %d st %d nv %d lov %d dmax %d dcnt %d want %d seen %d shown %d ringtop %d\n",f,st,nv,sp:read_u16(FXS+0x2a2),sp:read_u16(FXS+0x2a4),sp:read_u16(FXS+0x2a6),sp:read_u16(FXS+0x2a8),sp:read_u16(FXS+0x210),sp:read_u16(FXS+0x20e),sp:read_u16(0xd00fe4))); last=k end
  if f>=N-5 then out:close(); m:exit() end end)
