-- gxprobe.lua: (1) obj_move_dir_speed: the speed d0 at its velocity add (the write of 6(a0)
-- from 0x2b946); (2) obj_calc_hitbox: calls whose inputs (y d0, x d1, table a2-2 at the write of
-- 80(a0)) equal the slot's previous call with no other writer of the slot's hitbox words since
-- (a cache's hit rate).  No reads of the tapped range (MAME re-enters the tap).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "6000")
local speeds={}; local nvel=0
local hb={}; local dirty={}; local hcalls,hhit,hmiss_in,hmiss_dirty=0,0,0,0
local function objtap(o,d,mk)
  local pc=cpu.state["PC"].value
  if pc>=0x2b946 and pc<=0x2b94a then
    local a0=cpu.state["A0"].value
    if o==a0+6 then nvel=nvel+1; local s=cpu.state["D0"].value&0xffff; speeds[s]=(speeds[s] or 0)+1 end
    return
  end
  local slot=o-((o-0x101000)%0x60); local off=o-slot
  if off>=80 and off<96 then
    if pc>=0x29ee6 and pc<0x29f60 then
      if off==80 then
        local a0=cpu.state["A0"].value; local y,x,t=cpu.state["D0"].value&0xffff,cpu.state["D1"].value&0xffff,cpu.state["A2"].value-2
        hcalls=hcalls+1
        local k=hb[a0]
        if k and k[1]==y and k[2]==x and k[3]==t then
          if dirty[a0] then hmiss_dirty=hmiss_dirty+1 else hhit=hhit+1 end
        else hmiss_in=hmiss_in+1 end
        hb[a0]={y,x,t}; dirty[a0]=false
      end
    else
      dirty[slot]=true
    end
  end
end
-- (one tap over the whole object area crashes MAME when the callback reads CPU state: three)
sp:install_write_tap(0x101000,0x103fff,"obj1",objtap); sp:install_write_tap(0x104000,0x105fff,"obj2",objtap); sp:install_write_tap(0x106000,0x1070bf,"obj3",objtap)
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f>=N-10 then
    local ks={} for k in pairs(speeds) do ks[#ks+1]=k end; table.sort(ks)
    out:write(string.format("velocity adds %d; distinct speeds %d\n",nvel,#ks))
    for _,k in ipairs(ks) do local s=k; if s>=0x8000 then s=s-65536 end; out:write(string.format("  speed %6d x %d\n",s,speeds[k])) end
    out:write(string.format("hitbox calls %d: cache hits %d (%.1f%%) misses: inputs %d dirty %d\n",hcalls,hhit,100*hhit/math.max(1,hcalls),hmiss_in,hmiss_dirty))
    out:close(); m:exit()
  end
end)
