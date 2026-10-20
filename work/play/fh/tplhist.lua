-- tplhist.lua: (FZ_TPLCHK builds) every one-piece fast record's descriptor, with or without a
-- template: write taps on FZ_TPLMISS (a3 = the descriptor at fz_rec .fok) and FZ_TPLHIT (the
-- descriptor at 20(sp): the template path's pushes); the histogram to OUT every 10,000 frames
-- and at the end: "<descriptor hex> <records> <misses>".  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "30000")
local hist={}; local miss={}; local tapm; local taph; local total=0; local tmiss=0
local function inst()
  if tapm then tapm:remove() end; if taph then taph:remove() end
  tapm=sp:install_write_tap(0xd0e3f2,0xd0e3f3,"tplmiss",function(off,data,mask) local d=cpu.state["A3"].value; hist[d]=(hist[d] or 0)+1; miss[d]=(miss[d] or 0)+1; total=total+1; tmiss=tmiss+1 end)
  taph=sp:install_write_tap(0xd0e3f6,0xd0e3f7,"tplhit",function(off,data,mask) local d=sp:read_u32(cpu.state["SP"].value+20); hist[d]=(hist[d] or 0)+1; total=total+1 end)
end
inst()
local function dump(f) out:seek("set",0); local ks={} for k in pairs(hist) do ks[#ks+1]=k end
  table.sort(ks,function(a,b) return hist[a]>hist[b] end)
  out:write(string.format("gf %d total %d misses %d distinct %d\n",f,total,tmiss,#ks))
  for _,k in ipairs(ks) do out:write(string.format("%x %d %d\n",k,hist[k],miss[k] or 0)) end; out:flush() end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f%500==0 then inst() end
  if f%10000==0 and f>0 then dump(f) end
  if f>=N-5 then dump(f); out:close(); m:exit() end end)
