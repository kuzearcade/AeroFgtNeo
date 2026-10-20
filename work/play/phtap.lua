-- phtap.lua: hole tries' progress: begun (DLR_OOO := $ff with DLR_HOLE), indexed (DLR_PH0), all
-- matched (DLR_DONE), committed (FX_DELTA := 1 with DLR_HOLE); saves (DLR_E written) per try
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("V_OUT"),"w")
local taps={}; local f=0; local c={b=0,i=0,d=0,c=0,s=0}
local function hole() return sp:read_u8(0xd0f6e0)~=0 end
local function on(o,d,m)
  local a=o&~1; local hi=(m&0xff00)~=0; local v=hi and (d>>8) or (d&0xff)
  if a==0xd0f6e2 and hi and v==0xff and hole() then c.b=c.b+1 end
  if a==0xd0f6e2 and not hi and v==0xff and hole() then c.i=c.i+1 end  -- DLR_PH0 at $6e3
  if a==0xd0f6b6 and not hi and v==0xff and hole() and sp:read_u8(0xd0f6e2)~=0 then c.d=c.d+1 end -- DLR_DONE $6b7
  if a==0xd0f620 and hi and v==1 and hole() then c.c=c.c+1 end
  if a==0xd0f66e and hole() and sp:read_u8(0xd0f6e2)~=0 then c.s=c.s+1 end -- DLR_E
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd0f6e2,0xd0f6e3,"a",on),sp:install_write_tap(0xd0f6b6,0xd0f6b7,"b",on),sp:install_write_tap(0xd0f620,0xd0f621,"c",on),sp:install_write_tap(0xd0f66e,0xd0f66f,"d",on)} end
inst()
emu.register_frame_done(function() f=f+1; if f%300==0 then inst() end
  if f%10000==0 then out:write(string.format("F %d begun %d indexed %d matched %d committed %d saves %d\n",f,c.b,c.i,c.d,c.c,c.s)) out:flush() end end)
