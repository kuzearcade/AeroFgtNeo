-- luttap.lua: writes to the game's lookup RAM mirror (G_SPRLUT $d06000-$d07fff) with a tile value < 0x40:
-- per writer PC: count, and the source table (A0/A1/A2 at the first write of a burst) guesses.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "12000"); local tap
local byp={}; local lastf=-1; local bursts={}
local function inst() if tap then tap:remove() end
  tap=sp:install_write_tap(0xd06000,0xd07fff,"lut",function(off,data,mask)
    local v=data&0xffff; if mask==0xff00 then v=data>>8 elseif mask==0x00ff then v=data&0xff end
    if (v&0x3fff)<0x40 then local pc=cpu.state["PC"].value; local k=string.format("%06x",pc)
      if not byp[k] then byp[k]={n=0,regs={}} end; byp[k].n=byp[k].n+1
      local f=HARNESS_GAME_FRAME()
      if f~=lastf then lastf=f; byp[k].regs[#byp[k].regs+1]=string.format("f%d a0=%06x a1=%06x a2=%06x a3=%06x off=%04x v=%04x",f,cpu.state["A0"].value,cpu.state["A1"].value,cpu.state["A2"].value,cpu.state["A3"].value,off-0xd06000,v) end
    end end) end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); inst()
  if f>=N-5 then for k,r in pairs(byp) do out:write(string.format("pc %s writes %d\n",k,r.n)); for i=1,math.min(#r.regs,12) do out:write("  "..r.regs[i].."\n") end end; out:close(); m:exit() end end)
