-- ovtap.lua: each new overrun (OVD_OPC changes): frame, OVD_OPC/OLN/OAT/SITE, OVD_OT (9 w), FX_HYIELD,
-- the frame's fx_hud_ov runs (write tap on FX_HOVRAN) and the HUD takes' .full runs are not seen;
-- also every frame with fx_hud_ov runs.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "45000"); local tap; local hov=0; local last=-1
local function inst() if tap then tap:remove() end
  tap=sp:install_write_tap(0x107fec,0x107fed,"hovran",function(off,data,mask) if (data&0xff00)==0xff00 or (data&0xff)==0xff then hov=hov+1 end end) end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); inst()
  local opc=sp:read_u32(0xd00be0)
  if f>300 and opc~=last then last=opc
    local t={} for i=0,8 do t[#t+1]=string.format("%d",sp:read_u16(0xd00f26+2*i)) end
    out:write(string.format("OVR f %d n %d opc %06x",f,opc,sp:read_u32(0xd00f08))..string.format(" qn %d",sp:read_u16(0xd0f692))..string.format(" oln %04x oat %d site %04x ot %s yield %04x hov %d\n",sp:read_u16(0xd00f0c),sp:read_u16(0xd00f0e),sp:read_u16(0xd00f10),table.concat(t,","),sp:read_u16(0x107fc0),hov)) end
  if hov>0 then out:write(string.format("hov f %d n %d yield %04x\n",f,hov,sp:read_u16(0x107fc0))) end
  hov=0; out:flush()
  if f>=N-5 then out:close(); m:exit() end end)
