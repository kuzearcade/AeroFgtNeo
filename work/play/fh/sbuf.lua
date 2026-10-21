-- sbuf.lua (HARNESS_TARGET=neo, botsel.lua): what single-buffered sprite storage would have to write.
-- (1) The VRAM writes the conversion makes now (a write tap on REG_VRAMADDR/RW/MOD, 0x3c0000-5:
-- the address, the data writes stepping it by the modulo), per frame: data words to the ring's
-- SCB1 (columns 43-380: 0xac0..0x5fff) and to its SCB2/3/4 (0x8000+43.. etc.), and address sets.
-- (2) The objects (as effcen.lua): heads (pieces), columns, tiles; frame to frame per slot: moved
-- (y or x), a new piece table (its tiles), new and gone objects - the writes a store keeping each
-- object in the same columns would need: a moved head 2 x (address + data) for SCB3, SCB4; a new
-- table's tiles 2 words each + an address per column; a new object all of it; a gone one 2 (height 0).
-- One line a frame: f objs heads cols tiles | ringSCB1 ringSCB234 addrsets | moved_heads newtab_tiles
-- newtab_cols new_objs new_tiles new_cols gone.  Env: OUT, F0, F1
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0")); local F1=tonumber(os.getenv("F1"))
local addr,mod=0,1; local s1,s234,na=0,0,0; local on=false; local tap
local function inst() if tap then tap:remove() end
  tap=sp:install_write_tap(0x3c0000,0x3c0005,"vram",function(o,d,mk)
    if not on then return end
    if o==0x3c0000 then addr=d; na=na+1
    elseif o==0x3c0004 then mod=d
    elseif o==0x3c0002 then
      if addr>=0xac0 and addr<0x6000 then s1=s1+1
      elseif addr>=0x8000 and addr<0x8600 and (addr&0x1ff)>=43 and (addr&0x1ff)<=380 then s234=s234+1 end
      addr=(addr+mod)&0xffff end end) end
inst()
local last={}
local function shape(a)
  local tab=sp:read_u32(a+0x1a)&0xfffffe; local n=sp:read_u8(a+4)+1; local c,t,h=0,0,0
  if tab==0 or tab>=0x80000 then return 0,0,0,tab end
  for i=0,n-1 do local e=tab+14*i; local w0=sp:read_u16(e); local hh,w
    if (w0&0x4000)~=0 then hh=((sp:read_u8(e+9)&0xe)>>1)+1; w=((sp:read_u8(e+11)&0xe)>>1)+1
    else if w0>=8 then break end; local g=sp:read_u32(e)&0xffffff; if g==0 or g>=0x80000 then break end
      hh=((sp:read_u8(g)&0xe)>>1)+1; w=((sp:read_u8(g+1)&0xe)>>1)+1 end
    c=c+w; t=t+w*hh; h=h+1 end
  return h,c,t,tab
end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); inst()
  if on then
    local no,nh,nc,nt,mv,ntt,ntc,nn,nnt,nnc,gone=0,0,0,0,0,0,0,0,0,0,0; local now={}
    for a=0x1010c0,0x1070c0-0x60,0x60 do if sp:read_u8(a)>=0x80 then
      local h,c,t,tab=shape(a); local y,x=sp:read_u16(a+0xe),sp:read_u16(a+0x10)
      no=no+1; nh=nh+h; nc=nc+c; nt=nt+t
      local l=last[a]
      if not l or l.ty~=sp:read_u16(a+0x16) then nn=nn+1; nnt=nnt+t; nnc=nnc+c
      else
        if l.y~=y or l.x~=x then mv=mv+h end
        if l.tab~=tab then ntt=ntt+t; ntc=ntc+c end end
      now[a]={y=y,x=x,tab=tab,ty=sp:read_u16(a+0x16)} end end
    for a,_ in pairs(last) do if not now[a] then gone=gone+1 end end
    last=now
    out:write(string.format("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",f,no,nh,nc,nt,s1,s234,na,mv,ntt,ntc,nn,nnt,nnc,gone))
  end
  s1,s234,na=0,0,0; on=(f>=F0 and f<F1)
  if f>=F1 then out:close(); m:exit() end end)
