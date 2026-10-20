-- hidtap.lua: frames with a layer hidden after a clear (HAL_BG_HID, FX1 heights all 0) over a play run:
-- spans "layer0 from-to" and "layer1 from-to" (FX1: FX1_HN == 0 and FX1_PAT == 0).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "20000")
local s0,s1=nil,nil
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  local h0=sp:read_u8(0xd00556)~=0; local h1=(sp:read_u16(0xd0f7e6)==0) and (sp:read_u32(0xd0f7d4)==0)
  if h0 and not s0 then s0=f elseif not h0 and s0 then out:write(string.format("layer0 %d-%d (%d)\n",s0,f-1,f-s0)); s0=nil end
  if h1 and not s1 then s1=f elseif not h1 and s1 then out:write(string.format("layer1 %d-%d (%d)\n",s1,f-1,f-s1)); s1=nil end
  if f>=N-5 then out:close(); m:exit() end end)
