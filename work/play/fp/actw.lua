-- actw.lua: PCs that write an object slot's first byte (0x101000..0x1070bf step 0x60) with bit 7 set
-- (activation) or to zero (deactivation); counts per PC.  Env: OUT
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]; local cpu=m.devices[":maincpu"]
local on,off,copy={}, {}, {}
local tap=sp:install_write_tap(0x101000,0x1070bf,"actw",function(off_,data,mask)
  local o=(off_-0x101000)%0x60
  if o==0 or (o==1 and (mask&0xff00)==0) then
    local v=(o==0) and ((data>>8)&0xff) or (data&0xff)
    if o==0 and (mask&0xff00)==0 then return end
    local pc=cpu.state["PC"].value
    if v>=0x80 then on[pc]=(on[pc] or 0)+1 elseif v==0 then off[pc]=(off[pc] or 0)+1 end
  end
end)
local n=0
emu.register_frame_done(function()
  tap:reinstall(); n=n+1
  if n%2000==0 then
    local f=io.open(os.getenv("OUT"),"w")
    for pc,c in pairs(on) do f:write(string.format("on %06x %d\n",pc,c)) end
    for pc,c in pairs(off) do f:write(string.format("off %06x %d\n",pc,c)) end
    f:close()
  end
end)
