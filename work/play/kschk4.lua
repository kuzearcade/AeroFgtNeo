-- kschk.lua: at each update's commit (FX_DELTA := 1), every kept new entry's base entry
-- (by its slot) must have the same shape/attributes/tiles
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("V_OUT"),"w")
VR=emu.item(manager.machine.devices[":spritegen"].items["0/m_videoram"])
local LT={0xd0e000,0xd0e800,0xd0ec00,0xd0f800,0xd0fc00}
nh2=0; no2=0
local taps={}; local f=0; local n=0; local bad=0; local nb=0
local function key(a) return string.format("%04x%04x%04x%04x",sp:read_u16(a)&0xfe00,sp:read_u16(a+2)&0xfe00,sp:read_u16(a+4),sp:read_u16(a+6)) end
local function chk()
  n=n+1
  if sp:read_u8(0xd0f6e0)~=0 then nh2=nh2+1 end
  if sp:read_u8(0xd0f6e2)~=0 then no2=no2+1 end
  local base=sp:read_u16(0xd0f66a); local a2=sp:read_u32(0xd0f676); local cl=sp:read_u32(0xd0f01a)
  local src=sp:read_u16(0xd0e510+192+2*base)
  local bp=sp:read_u8(0xd0f666)
  local nbse=sp:read_u16(0xd0f6a6); local nn=sp:read_u16(0xd0f66c)
  local ta=sp:read_u32(0xd0f686)  -- DLR_A4: base table
  local ct=0x1084e0+132*sp:read_u16(0xd0f632)
  local tfin=sp:read_u8(ta+128); local nx=sp:read_u8(ta+129)
  local slotj={}
  for j=0,nbse-1 do local v=sp:read_u8(ta+j); if j>=tfin and v==0xff then v=nx; nx=nx+1 end; if v<0xfe then slotj[v]=j end end
  local msg=""
  if (src<5 and LT[src+1]~=a2) and bp==0 then msg=msg..string.format(" A2 %06x src %d", a2, src) end
  local mm=0
  for i=0,nn-1 do local k=sp:read_u8(ct+i)
    if k<0xfe then local s=sp:read_u8(0xd0e600+k); local j=slotj[s]
      if j==nil or key(a2+8*j)~=key(cl+8*i) then mm=mm+1; if mm<=3 then msg=msg..string.format(" i%d k%d s%d j%s",i,k,s,tostring(j)) end
      else
        -- the base sprite's columns: TA (dl_fin's permuted copy) is not the base's any more: use DL_TA? read SS_HADR before? use the hidden/kept copy DL_TA
        local col=sp:read_u16(0x10a280+510*base+62+2*k)-0x8200
        local w=((sp:read_u16(a2+8*j+2)>>9)&7)+1
        local ok=true
        for q=1,w-1 do if (VR:read(0x8200+col+q)&0x40)==0 then ok=false end end
        if col+w-1>380 then ok=false end
        if not ok then mm=mm+1; if mm<=3 then local tt={} for q=0,w do tt[#tt+1]=string.format("%04x",VR:read(0x8200+col+q)) end msg=msg..string.format(" W i%d k%d s%d j%d col%d w%d %s",i,k,s,j,col,w,table.concat(tt," ")) end end
      end end end
  if mm>0 or msg~="" then bad=bad+1; if bad<40 then out:write(string.format("f%d base %d bp %d ooo %d hole %d mm %d%s\n",f,base,bp,sp:read_u8(0xd0f6e2),sp:read_u8(0xd0f6e0),mm,msg)) out:flush() end end
end
local function onw(o,d,m) if (o&~1)==0xd0f620 and ((m&0xff00)~=0 and (d>>8)==1) then chk() end end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd0f620,0xd0f621,"ks",onw)} end
inst()
emu.register_frame_done(function() f=f+1; if f%300==0 then inst() end; if f%250==0 then out:write(string.format("F %d commits %d ooo %d hole %d bad %d\n",f,n,no2,nh2,bad)) out:flush() end end)
