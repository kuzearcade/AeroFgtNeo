-- typecen.lua: every 8 game frames, a histogram of the active objects' types (+0x16) over
-- the pools; at the end the totals per type.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "3000")
local B=0x101000; local PEND=B+0x60c0; local tot={}; local samples=0
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME()
  if f%8==0 then samples=samples+1
    for a=B,PEND-1,0x60 do if sp:read_u8(a)~=0 then local t=sp:read_u16(a+0x16); tot[t]=(tot[t] or 0)+1 end end
  end
  if f>=N-5 then
    local ks={} for k in pairs(tot) do ks[#ks+1]=k end; table.sort(ks)
    for _,k in ipairs(ks) do out:write(string.format("%02x %.2f\n",k,tot[k]/samples)) end
    out:close(); m:exit()
  end
end)
