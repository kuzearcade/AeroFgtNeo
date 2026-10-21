-- menudrv.lua: drive the BIOS menus by script.  ACT="frame:field:frames;..." (fields: Service Mode,
-- P1 Up/Down/Left/Right/A/B/C/D, 1 Player Start, Coin 1), SNAP="f1,f2,..." snapshots, N the end.
-- Fields by name from every port.  RESET=f: a soft reset at frame f (RAM kept).  Also DUMP="f" dumps BRAM 0xd00000-0xd00400 and 0x10fd80.. then.
local m=manager.machine
local F={}
for pn,p in pairs(m.ioport.ports) do for fn,f in pairs(p.fields) do F[fn]=f end end
local acts={}
for a in string.gmatch(os.getenv("ACT") or "", "[^;]+") do local f,n,d=a:match("(%d+):([^:]+):(%d+)"); acts[#acts+1]={tonumber(f),n,tonumber(d)} end
local snaps={}
for s in string.gmatch(os.getenv("SNAP") or "", "%d+") do snaps[tonumber(s)]=true end
local N=tonumber(os.getenv("N") or "3000"); local DUMP=tonumber(os.getenv("DUMP") or "-1")
local RESET=tonumber(os.getenv("RESET") or "-1")   -- (a soft reset then: RAM kept, as the MiSTer's)
local sp=m.devices[":maincpu"].spaces["program"]
local f=0
emu.register_frame_done(function() f=f+1
  for _,a in ipairs(acts) do
    if f==a[1] then F[a[2]]:set_value(1) elseif f==a[1]+a[3] then F[a[2]]:set_value(0) end end
  if snaps[f] then m.video:snapshot() end
  if f==RESET then m:soft_reset() end
  if f==DUMP then local o=io.open(os.getenv("DOUT") or "dump.txt","w")
    for a=0xd00000,0xd003ff,16 do local t={} for i=0,15 do t[#t+1]=string.format("%02x",sp:read_u8(a+i)) end; o:write(string.format("%06x %s\n",a,table.concat(t," "))) end
    local t={} for i=0,31 do t[#t+1]=string.format("%02x",sp:read_u8(0x10fd80+i)) end; o:write("10fd80 "..table.concat(t," ").."\n")
    local IOM=tonumber(os.getenv("IOM") or "0")
    t={} for i=0,15 do t[#t+1]=string.format("%02x",sp:read_u8(0xd00810+i)) end; o:write("HAL_SOFTDIP "..table.concat(t," ").."\n")
    if IOM>0 then o:write(string.format("DSW1 %02x DSW2 %02x\n",sp:read_u8(IOM+0x27),sp:read_u8(IOM+0x29))) end
    o:close() end
  if f>=N then m:exit() end end)
