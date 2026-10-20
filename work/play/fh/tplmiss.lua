-- tplmiss.lua: (FZ_TPLCHK builds) the descriptors of one-piece fast records built without a
-- template: a write tap on FZ_TPLMISS (FZ_V+242) reads a3 (the descriptor at fz_rec .fok);
-- the histogram to OUT at the end (and every 10,000 frames).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "30000")
local hist={}; local tap; local total=0
local function inst() if tap then tap:remove() end
  tap=sp:install_write_tap(0xd0e3f2,0xd0e3f3,"tplmiss",function(off,data,mask) local a3=cpu.state["A3"].value; hist[a3]=(hist[a3] or 0)+1; total=total+1 end) end
inst()
local function dump(f) out:seek("set",0); local ks={} for k in pairs(hist) do ks[#ks+1]=k end
  table.sort(ks,function(a,b) return hist[a]>hist[b] end)
  out:write(string.format("gf %d total %d distinct %d\n",f,total,#ks))
  for _,k in ipairs(ks) do out:write(string.format("%x %d\n",k,hist[k])) end; out:flush() end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f%500==0 then inst() end
  if f%10000==0 then dump(f) end
  if f>=N-5 then dump(f); out:close(); m:exit() end end)
