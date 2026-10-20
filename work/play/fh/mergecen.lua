-- mergecen.lua (HARNESS_TARGET=orig or neo, botsel.lua): the sprite columns of the boss-fight frames and
-- what merging would save - per drawn object (b0 bit 7) its pieces from the ROM's own table (+0x1a,
-- pieces +4: entry = header pointer l, y offset w, x offset w; the header's +0/+1 bytes' bits 1-3 the
-- height/width in tiles - 1), its columns as drawn (width per piece), and merged: pieces of the same
-- object with the same x and width, no vertical overlap and a y a multiple of 16 below the
-- column's top (a Neo column's tiles are 16 pixels apart) share columns when the span from the top
-- one to the bottom one is at most 32 tiles; and across objects: consecutive pieces in slot order
-- (the pass's order) with the same x and width merged the same way (third count); FX1_PAT's
-- shown tilemap-1 columns (fourth, neo only); an FZ_MGDIAG build's merged columns so far (fifth).  On the conversion (neo) a rewritten entry (a descriptor:
-- the first word's bit 14) holds the header's bytes at +9/+11.  Per frame the totals; at the end the distribution over
-- the frames with a boss (bot.txt column 2) and the share of frames over 169 columns (half the ring:
-- a shown set and one in work cannot both fit).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "200000")
local NEO=HARNESS_TARGET=="neo"
local R=NEO and 0 or 0xeef000                     -- game 0x100000 -> arcade 0xfef000
local BOSSF=0xff0000                               -- (unused: boss frames from the bot's own flag)
local tot,mer={}, {}
local function objcols(a)
  local tab=sp:read_u32(a+0x1a)&0xfffffe; local n=sp:read_u8(a+4)+1
  if tab==0 or tab>=0x80000 then return 0,0,{} end
  local p={}
  for i=0,n-1 do local e=tab+14*i
    local w0=sp:read_u16(e); local h,w
    if NEO and (w0&0x4000)~=0 then
      h=((sp:read_u8(e+9)&0xe)>>1)+1; w=((sp:read_u8(e+11)&0xe)>>1)+1
    else
      if w0>=8 then break end
      local g=sp:read_u32(e)&0xffffff
      if g==0 or g>=0x80000 then break end
      h=((sp:read_u8(g)&0xe)>>1)+1; w=((sp:read_u8(g+1)&0xe)>>1)+1
    end
    p[#p+1]={y=sp:read_i16(e+4)+sp:read_i16(a+0xe),x=sp:read_i16(e+6)+sp:read_i16(a+0x10),w=w,h=h} end
  local c=0 for _,q in ipairs(p) do c=c+q.w end
  -- merge: group by (x, w), sort by y, greedy chains without overlap and span <= 32 tiles
  local g={} for _,q in ipairs(p) do local k=q.x*64+q.w; g[k]=g[k] or {}; table.insert(g[k],q) end
  local mc=0
  for _,lst in pairs(g) do table.sort(lst,function(a,b) return a.y<b.y end)
    local top,bot=nil,nil
    for _,q in ipairs(lst) do
      if top and q.y>=bot and (q.y-top)%16==0 and (q.y+16*q.h-top)<=512 then bot=q.y+16*q.h
      else mc=mc+q.w; top=q.y; bot=q.y+16*q.h end end end
  return c,mc,p
end
local bossf=0; local B={}
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>450 and f%2==0 then
    local c,mc,no,gc=0,0,0,0; local lx,lw,top,bot=nil,nil,nil,nil
    local g4,o4=0,0; local L4={}; local L1={}       -- (the same with gaps <= 4 rows; and one-piece objects only)
    local function step(L,q,cnt,gapmax)
      if L.x==q.x and L.w==q.w and q.y>=L.bot and (q.y-L.top)%16==0 and (q.y+16*q.h-L.top)<=512 and (q.y-L.bot)<=16*gapmax then L.bot=q.y+16*q.h; return cnt
      else L.x,L.w,L.top,L.bot=q.x,q.w,q.y,q.y+16*q.h; return cnt+q.w end end
    for a=0x1010c0+R,0x107000+R,0x60 do if sp:read_u8(a)>=0x80 then local x,y,p=objcols(a); c=c+x; mc=mc+y; no=no+1
      for _,q in ipairs(p or {}) do      -- across objects: consecutive pieces, same x and width, below
        if lx==q.x and lw==q.w and q.y>=bot and (q.y-top)%16==0 and (q.y+16*q.h-top)<=512 then bot=q.y+16*q.h
        else gc=gc+q.w; lx,lw,top,bot=q.x,q.w,q.y,q.y+16*q.h end
        g4=step(L4,q,g4,4)
        if #p==1 then o4=step(L1,q,o4,4) else o4=o4+q.w; L1={} end end end end
    local pat=NEO and sp:read_u32(0xd0f7d4) or 0; local np=0; for i=0,20 do if (pat>>i)&1==1 then np=np+1 end end
    local saved=NEO and sp:read_u32(0xd00f3c) or 0     -- (an FZ_MGDIAG build: FZ_MGC, the columns merged so far)
    B[#B+1]=string.format("%d %d %d %d %d %d %d %d %d",f,no,c,mc,gc,np,saved,g4,o4)
  end
  if f>=N then for _,l in ipairs(B) do out:write(l.."\n") end; out:close(); m:exit() end end)
