-- pdstat.lua: palette deferral reasons (OVR_DIAG=2 build) at the run's end
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("HARNESS_FRAMES"))-5; local done=false
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if not done and f>=N then done=true
    out:write(string.format("frame %d paldefer %d out %d scan %d stage %d nofit %d\n",f,sp:read_u32(0xd0042c),sp:read_u16(0xd00f38),sp:read_u16(0xd00f3a),sp:read_u16(0xd00f3c),sp:read_u16(0xd00f3e))); out:close() end
end)
