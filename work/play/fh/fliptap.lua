-- fliptap.lua (OVR_DIAG build): each frame the commit's step lines past the deadline (OVD_T 0..8,
-- signed), BP_NV, BP_SHOWN, the three sets' pool record counts (FZ_PBN).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "10000")
local function s16(v) if v>32767 then return v-65536 end return v end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>300 then local t={} for i=0,8 do t[#t+1]=string.format("%d",s16(sp:read_u16(0xd00f14+2*i))) end
    out:write(string.format("%d %s nv %d shown %d pbn %d %d %d bp %d %d %d\n",f,table.concat(t," "),sp:read_u16(0xd0f2a0),sp:read_u16(0xd0f20e),sp:read_u16(0xd0e33a),sp:read_u16(0xd0e33c),sp:read_u16(0xd0e33e),s16(sp:read_u16(0xd00f38)),s16(sp:read_u16(0xd00f3a)),s16(sp:read_u16(0xd00f3c)))) end
  if f>=N-5 then out:close(); m:exit() end end)
