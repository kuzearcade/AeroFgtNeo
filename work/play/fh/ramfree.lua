-- ramfree.lua (HARNESS_TARGET=neo): which RAM a build never leaves non-zero - the game's work RAM
-- (0x100000-0x10ffff) and the backup RAM (0xd00000-0xd0ffff), read every 8th frame end, OR-ed into a
-- 128 KB map written at the end (OUT: the work RAM's 64 KB, then the backup RAM's).  A frame-end
-- sample misses a transient write: confirm a candidate block with WATCH=<lo>-<hi> (hex), a write
-- tap that counts every write to it from F0 on (written to OUT.watch).  Env: OUT, N, F0, WATCH
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local N=tonumber(os.getenv("N") or "60000"); local F0=tonumber(os.getenv("F0") or "1500");  -- (from F0: the boot RAM test fills it all)
 local OUT=os.getenv("OUT")
local acc={}; for i=1,32768 do acc[i]=0 end         -- 32768 longs: 64 KB + 64 KB
local W=os.getenv("WATCH"); if W=="" then W=nil end; local wlo,whi,wn,wfirst,wtap=nil,nil,0,nil,nil
if W then wlo,whi=W:match("(%x+)-(%x+)"); wlo=tonumber(wlo,16); whi=tonumber(whi,16) end
local function inst() if not W then return end; if wtap then wtap:remove() end
  wtap=sp:install_write_tap(wlo,whi,"ramfree",function(o,d,mk)
    if HARNESS_GAME_FRAME()<F0 then return end
    wn=wn+1; if not wfirst then wfirst=string.format("first write %06x data %x pc %06x frame %d",o,d,m.devices[":maincpu"].state["PC"].value,HARNESS_GAME_FRAME()) end end) end
inst()
local function orin(base,k0)
  local s=sp:read_range(base,base+0xffff,32)
  for i=0,16383 do local v=string.unpack(">I4",s,i*4+1); if v~=0 then acc[k0+i]=acc[k0+i]|v end end end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); inst()
  if f>=F0 and f%8==0 then orin(0x100000,1); orin(0xd00000,16385) end
  if f>=N then local o=io.open(OUT,"wb"); for i=1,32768 do o:write(string.pack(">I4",acc[i])) end; o:close()
    if W then local w=io.open(OUT..".watch","w"); w:write(string.format("watch %06x-%06x writes %d %s\n",wlo,whi,wn,wfirst or "")); w:close() end
    m:exit() end end)
