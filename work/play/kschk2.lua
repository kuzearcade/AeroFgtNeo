-- kschk.lua: at each update's commit (FX_DELTA := 1), every kept new entry's base entry
-- (by its slot) must have the same shape/attributes/tiles
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("V_OUT"),"w")
local LT={0xd0e000,0xd0e800,0xd0ec00,0xd0f800,0xd0fc00}
local taps={}; local f=0; local n=0; local bad=0; local nb=0
local function key(a) return string.format("%04x%04x%04x%04x",sp:read_u16(a)&0xfe00,sp:read_u16(a+2)&0xfe00,sp:read_u16(a+4),sp:read_u16(a+6)) end
local function chk()
  n=n+1
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
      if j==nil or key(a2+8*j)~=key(cl+8*i) then mm=mm+1; if mm<=3 then msg=msg..string.format(" i%d k%d s%d j%s",i,k,s,tostring(j)) end end end end
  if f>=1836 and f<=1843 then
    local ks={} for k=0,7 do ks[#ks+1]=sp:read_u8(0xd0e600+k) end
    local c={} for k=0,7 do c[#c+1]=string.format("%02x",sp:read_u8(ct+k)) end
    local ss=0x10a280+510*base; local hh={} for k=0,7 do hh[#hh+1]=sp:read_u16(ss+62+2*k)-0x8200 end
    local kk={} for k=0,3 do kk[#kk+1]=key(cl+8*k):sub(13) end
    local bk={} for k=0,3 do bk[#bk+1]=key(a2+8*k):sub(13) end
    out:write(string.format("C f%d base %d src %d ci %d bp %d ooo %d id %d H %d KS %s CT %s heads %s new %s basel %s pc %06x\n",f,base,src,sp:read_u16(0xd0f018),bp,sp:read_u8(0xd0f6e2),sp:read_u8(0xd0f6b6),sp:read_u16(0xd0f672),table.concat(ks,","),table.concat(c,","),table.concat(hh,","),table.concat(kk,","),table.concat(bk,","),manager.machine.devices[":maincpu"].state["PC"].value)) out:flush()
  end
  if mm>0 or msg~="" then bad=bad+1; if bad<40 then out:write(string.format("f%d base %d bp %d ooo %d hole %d mm %d%s\n",f,base,bp,sp:read_u8(0xd0f6e2),sp:read_u8(0xd0f6e0),mm,msg)) out:flush() end end
end
local function onw(o,d,m) if (o&~1)==0xd0f620 and ((m&0xff00)~=0 and (d>>8)==1) then chk() end end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd0f620,0xd0f621,"ks",onw)} end
inst()
emu.register_frame_done(function() f=f+1; if f%300==0 then inst() end; if f%2000==0 then out:write(string.format("F %d commits %d bad %d\n",f,n,bad)) out:flush() end end)
