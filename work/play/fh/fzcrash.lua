-- fzcrash.lua: at each record dispatch (fz_ntab's FZ_W2 write) with 16 pieces: the record,
-- its table's pieces (14 bytes each: graphic ptr, y, x, flips, zoom, colour) and the first
-- graphic header words.  Env: OUT, N, LST
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "600")
local FZV=0xd0e300
local SYM={fz_ntab=0,fz_bul=0}
do local f=io.open(os.getenv("LST")); local on=false
  for l in f:lines() do if l:find("^Symbols by name") then on=true elseif l:find("^Symbols by value") then break
    elseif on then local n,a=l:match("^(%S+)%s+A:(%x+)"); if n and SYM[n] then SYM[n]=tonumber(a,16) end end end; f:close() end
local n=0
sp:install_write_tap(FZV+36,FZV+37,"w2",function(o,d,mk) local ok,e=pcall(function()
  local p=cpu.state["PC"].value; if p<SYM.fz_ntab or p>=SYM.fz_bul then return end
  local r=sp:read_u32(FZV); local pcs=sp:read_u8(r+15)+1
  if pcs<12 then return end
  n=n+1; if n>3 then return end
  local t=sp:read_u32(r)
  out:write(string.format("gf %d HF %d rec %08x table %08x routine %08x y %d x %d w2 %02x pcs %d zoom %x\n",HARNESS_GAME_FRAME(),sp:read_u16(0xd0085e),r,t,sp:read_u32(r+4),sp:read_i16(r+8),sp:read_i16(r+10),sp:read_u8(r+13),pcs,sp:read_u8(r+14)))
  for i=0,pcs-1 do local a=t+14*i; local g=sp:read_u32(a)
    out:write(string.format("  piece %2d @%08x gfx %08x y %6d x %6d fl %02x%02x zm %02x%02x col %02x | gfx hdr %04x %04x\n",i,a,g,sp:read_i16(a+4),sp:read_i16(a+6),sp:read_u8(a+8),sp:read_u8(a+9),sp:read_u8(a+10),sp:read_u8(a+11),sp:read_u8(a+12),(g%2==0 and g<0x200000) and sp:read_u16(g) or 0xffff,(g%2==0 and g<0x200000) and sp:read_u16(g+2) or 0xffff))
  end
  out:flush()
  end); if not ok then print("fzcrash error", e) end
end)
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f>=N then out:close(); m:exit() end end)
