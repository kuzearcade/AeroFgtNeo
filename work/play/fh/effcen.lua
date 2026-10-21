-- effcen.lua (HARNESS_TARGET=neo, botsel.lua): per frame (F0..F1, every frame) the drawn objects'
-- sprite columns, and of the effects (the load-shedding types of AUDIT 48: explosions 09 33 60 6c 99
-- 9b, sparks 0e 16 a3, the bomb's flash 20, shadows 2f 34 88): objects, columns, tiles, how many
-- changed their piece table since the last frame (a new animation frame: their tiles to rewrite) or
-- moved, and the tiles of the changed ones; the zoomed objects' (type $2e) columns.  One line a frame:
-- f cols effobj effcols efftiles effanim effmoved effanimtiles zoomcols.  Env: OUT, F0, F1
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0")); local F1=tonumber(os.getenv("F1"))
local EFF={[0x09]=1,[0x33]=1,[0x60]=1,[0x6c]=1,[0x99]=1,[0x9b]=1,[0x0e]=1,[0x16]=1,[0xa3]=1,[0x20]=1,[0x2f]=1,[0x34]=1,[0x88]=1}
local last={}
local function shape(a)
  local tab=sp:read_u32(a+0x1a)&0xfffffe; local n=sp:read_u8(a+4)+1; local c,t=0,0
  if tab==0 or tab>=0x80000 then return 0,0,tab end
  for i=0,n-1 do local e=tab+14*i; local w0=sp:read_u16(e); local h,w
    if (w0&0x4000)~=0 then h=((sp:read_u8(e+9)&0xe)>>1)+1; w=((sp:read_u8(e+11)&0xe)>>1)+1
    else if w0>=8 then break end; local g=sp:read_u32(e)&0xffffff; if g==0 or g>=0x80000 then break end
      h=((sp:read_u8(g)&0xe)>>1)+1; w=((sp:read_u8(g+1)&0xe)>>1)+1 end
    c=c+w; t=t+w*h end
  return c,t,tab
end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 and f<F1 then
    local cols,eo,ec,et,ea,em,eat,zc=0,0,0,0,0,0,0,0; local now={}
    for a=0x1010c0,0x107000,0x60 do if sp:read_u8(a)>=0x80 then
      local ty=sp:read_u16(a+0x16); local c,t,tab=shape(a); cols=cols+c
      if ty==0x2e then zc=zc+c end
      if EFF[ty] then eo=eo+1; ec=ec+c; et=et+t
        local y,x=sp:read_u16(a+0xe),sp:read_u16(a+0x10); local l=last[a]
        if not l or l[1]~=tab then ea=ea+1; eat=eat+t end
        if not l or l[2]~=y or l[3]~=x then em=em+1 end
        now[a]={tab,y,x} end end end
    last=now
    out:write(string.format("%d %d %d %d %d %d %d %d %d\n",f,cols,eo,ec,et,ea,em,eat,zc))
  end
  if f>=F1 then out:close(); m:exit() end end)
