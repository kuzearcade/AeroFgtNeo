-- romhits.lua (orig target): the game's own reads of the bytes the descriptor rewrite changes
-- (PDLIST: lines "entry table c|n" from tools/aerofgt2neo.py AEROFGT_PDLIST; a descriptor
-- rewrites +0..+3 and +8..+13 of each entry).  After game frame 300 (the boot checksum reads
-- everything), each read of such a word is counted by (entry, offset, PC); the totals at the
-- end.  Env: OUT, N, PDLIST
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "60000")
local ent={}   -- word address -> {entry, offset}
local lo,hi=0x80000,0
for l in io.lines(os.getenv("PDLIST")) do
  local e=tonumber(l:match("^(%x+)"),16)
  for _,off in ipairs({0,2,8,10,12}) do ent[e+off]={e,off} end
  if e<lo then lo=e end; if e+14>hi then hi=e+14 end
end
local hits={}; local started=false
hi=hi|1
local tap=sp:install_read_tap(lo,hi,"rh",function(o,d,mk)
  if not started then return end
  local x=ent[o]; if not x then return end
  local k=string.format("%06x %d %06x",x[1],x[2],cpu.state["PC"].value); hits[k]=(hits[k] or 0)+1
end)
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f==300 then started=true end; if f%200==0 then tap:reinstall() end
  if f>=N-5 then local ks={} for k in pairs(hits) do ks[#ks+1]=k end; table.sort(ks)
    for _,k in ipairs(ks) do out:write(k.." "..hits[k].."\n") end; out:close(); m:exit() end end)
