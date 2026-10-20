-- gxhist.lua: GX_VERIFY's |speed| histogram (GXV_HIST) at the end of a run.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "6000")
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f>=N-10 then
    out:write(string.format("calls %d out %d miss %d big %d\n",sp:read_u32(0xd00f0c),sp:read_u32(0xd00f00),sp:read_u32(0xd00f08),sp:read_u16(0xd00f04)))
    for s=0,255 do local c=sp:read_u16(0xd0fe00+2*s); if c>0 then out:write(string.format("%d %d\n",s,c)) end end
    out:close(); m:exit()
  end
end)
