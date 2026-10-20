-- mergetype.lua (HARNESS_TARGET=neo, botsel.lua): in frames whose drawn objects need at least CMIN sprite
-- columns, per object type: objects a frame, pieces, columns, the columns merging within the object
-- would save (same x and width, the next piece a whole number of tiles below the last one's bottom,
-- a gap of at most 4 rows: FZ_MERGE's rule in table order), the same allowing the next piece above
-- (bottom-first tables), and the share with the object's flips byte ($2a) non-zero.  Env: OUT, F0, F1, CMIN
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0")); local F1=tonumber(os.getenv("F1"))
local CMIN=tonumber(os.getenv("CMIN") or "180")
local T={}; local nf=0
local function pieces(a)
  local tab=sp:read_u32(a+0x1a)&0xfffffe; local n=sp:read_u8(a+4)+1; local p={}
  if tab==0 or tab>=0x80000 then return p end
  for i=0,n-1 do local e=tab+14*i; local w0=sp:read_u16(e); local h,w
    if (w0&0x4000)~=0 then h=((sp:read_u8(e+9)&0xe)>>1)+1; w=((sp:read_u8(e+11)&0xe)>>1)+1
    else if w0>=8 then break end; local g=sp:read_u32(e)&0xffffff; if g==0 or g>=0x80000 then break end
      h=((sp:read_u8(g)&0xe)>>1)+1; w=((sp:read_u8(g+1)&0xe)>>1)+1 end
    p[#p+1]={y=sp:read_i16(e+4),x=sp:read_i16(e+6),w=w,h=h} end
  return p
end
local function saving(p,both)
  local s=0; local L=nil
  for _,q in ipairs(p) do
    if L and L.x==q.x and L.w==q.w and q.y>=L.bot and (q.y-L.top)%16==0 and q.y-L.bot<=64 and q.y+16*q.h-L.top<=512 then
      L.bot=q.y+16*q.h; s=s+q.w
    elseif both and L and L.x==q.x and L.w==q.w and q.y+16*q.h<=L.top and (L.top-q.y)%16==0 and L.top-(q.y+16*q.h)<=64 and L.bot-q.y<=512 then
      L.top=q.y; s=s+q.w
    else L={x=q.x,w=q.w,top=q.y,bot=q.y+16*q.h} end end
  return s
end
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>=F0 and f<F1 then
    local objs={}; local c=0
    for a=0x1010c0,0x107000,0x60 do if sp:read_u8(a)>=0x80 then local p=pieces(a); local k=0 for _,q in ipairs(p) do k=k+q.w end; c=c+k; objs[#objs+1]={a=a,p=p,c=k} end end
    if c>=CMIN then nf=nf+1
      for _,o in ipairs(objs) do local ty=string.format("%02x",sp:read_u8(o.a+0x17)); T[ty]=T[ty] or {n=0,pc=0,c=0,s=0,s2=0,fl=0}
        local t=T[ty]; t.n=t.n+1; t.pc=t.pc+#o.p; t.c=t.c+o.c; t.s=t.s+saving(o.p,false); t.s2=t.s2+saving(o.p,true)
        if sp:read_u8(o.a+0x2a)~=0 then t.fl=t.fl+1 end end end end
  if f>=F1 then out:write(string.format("frames with >= %d columns: %d\n",CMIN,nf))
    local ks={} for k in pairs(T) do ks[#ks+1]=k end; table.sort(ks,function(a,b) return T[a].s2>T[b].s2 end)
    for _,k in ipairs(ks) do local t=T[k]; out:write(string.format("type %s  %.1f a frame, pieces %.1f, columns %.1f, within saving %.1f (either direction %.1f), flipped %.0f%%\n",
      k,t.n/nf,t.pc/math.max(t.n,1),t.c/nf,t.s/nf,t.s2/nf,100*t.fl/math.max(t.n,1))) end
    out:close(); m:exit() end end)
