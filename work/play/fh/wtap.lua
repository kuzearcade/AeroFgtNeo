-- wtap.lua: who writes into the regions hal/fz.s wants: the game's RAM gap 0x10aaa0..
-- 0x10c2ff (0xff9aa0..) and FXS+$700.. (0xd0f700..0xd0f74f).  Writes counted per PC.
-- Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w")
local N=tonumber(os.getenv("N") or "3000")
local cnt={}; local first={}
local function on(name) return function(o,d,mk)
  local pc=cpu.state["PC"].value
  local k=string.format("%s pc %06x",name,pc)
  cnt[k]=(cnt[k] or 0)+1
  if not first[k] then first[k]=string.format("gf %d at %06x data %04x",HARNESS_GAME_FRAME(),o,d) end
end end
local taps={}
local function inst()
  for _,t in ipairs(taps) do t:remove() end
  taps={sp:install_write_tap(0x10aaa0,0x10c2ff,"gap",on("gap")),
        sp:install_write_tap(0xd0f700,0xd0f74f,"fzv",on("fzv"))}
end
inst()
local f=0
emu.register_frame_done(function()
  f=f+1
  if f%300==0 then inst() end
  if f>=N then
    local ks={} for k in pairs(cnt) do ks[#ks+1]=k end
    table.sort(ks,function(a,b) return cnt[a]>cnt[b] end)
    for _,k in ipairs(ks) do out:write(string.format("%s n %d first %s\n",k,cnt[k],first[k])) end
    out:close(); m:exit()
  end
end)
