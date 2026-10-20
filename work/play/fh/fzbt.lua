-- fzbt.lua: the record builder's time: FZB_ST := 3 (fz_build .got) to := 1 (complete) per build, in
-- 12 MHz cycles, with the records (FZB_N) - sums and a histogram by records, from game frame F0.
-- Env: OUT, N, F0
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "26800"); local F0=tonumber(os.getenv("F0") or "20964")
local BUF={[0xd0e514]=0xd0e510,[0xd0ea34]=0xd0ea30,[0xd0f804]=0xd0f800}
local t0={}; local sum=0; local n=0; local recs=0; local hist={}
local taps={}
local function onst(o,d,mk)
  local b=BUF[o]; if not b then return end
  if (mk&0xff00)==0 then return end
  local st=(d>>8)&0xff; local f=HARNESS_GAME_FRAME(); if f<F0 then return end
  local t=m.time:as_ticks(12000000)
  if st==3 then t0[b]=t elseif st==1 and t0[b] then local c=t-t0[b]; local r=sp:read_u16(b); sum=sum+c; n=n+1; recs=recs+r; local k=math.min(r//10,9); hist[k]=(hist[k] or 0)+1; hist[k.."c"]=(hist[k.."c"] or 0)+c; hist[k.."r"]=(hist[k.."r"] or 0)+r; t0[b]=nil end
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={} for a,_ in pairs(BUF) do taps[#taps+1]=sp:install_write_tap(a,a+1,"st"..a,onst) end end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%500==0 then inst() end
  if f>=N-5 then out:write(string.format("builds %d cycles %d (%.0f a build) records %d (%.0f a record)\n",n,sum,sum/math.max(1,n),recs,sum/math.max(1,recs)))
    for k=0,9 do if hist[k] then out:write(string.format("  %d-%d records: %d builds, %.0f cycles a build, %.0f a record\n",k*10,k*10+9,hist[k],hist[k.."c"]/hist[k],hist[k.."c"]/math.max(1,hist[k.."r"]))) end end
    out:close(); m:exit() end end)
