-- holechk.lua (HARNESS_TARGET=neo, botsel.lua; an FZ_HOLE build): the draw order of each set
-- whose middle records went on into the shown set's columns (FZ_HOLE, AUDIT 53).  When the
-- continuation begins (FZD_ON := 2, spr_holefin) the gap is noted: the top run's end SPJ and
-- the lower run's guard SPG; when it ends (FZD_ON := 0, spr_ovfend) the set's heads (SS_HADR:
-- SCB3/SCB4 addresses) are checked: those written before the flip (FZ_OVFH) outside the gap
-- (top run >= SPJ, lower run < SPG), those after it inside (SPG < col < SPJ) - each part
-- converted in order, so the columns follow the records' order.  Also the set's columns in
-- VRAM at the end: every head height > 0... (not checked: heights may be 0 off-screen).
-- One line per hole; BAD lines for a head out of place.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N"))
local FZD_ON=0xd0e3d6; local SETS=0x10a280; local SSZ=0x1fe
local HADR=0x3e
local spj,spg,n,bad=0,0,0,0
local taps={}
local function on(o,d,mk)
  local v
  if (o&1)==0 then v=(d>>8)&0xff; if (mk&0xff00)==0 then return end else v=d&0xff; if (mk&0xff)==0 then return end end
  if o~=FZD_ON and o~=FZD_ON-1 then return end
  if v==2 then spj=sp:read_u16(0xd00fe0); spg=sp:read_u16(0xd00fe2)
  elseif v==0 and spj>0 then
    local w=sp:read_u16(0x10fc3e); local ss=SETS+SSZ*w
    local hoff=sp:read_u16(ss+10); local h0=sp:read_u16(0x10fd9a)
    local nb,nt,nl,nh=0,0,0,0
    for i=0,hoff-2,2 do local a=sp:read_u16(ss+HADR+i)
      if a>=0x8200 and a<0x8600 then local c=a&0x1ff
        if i<h0 then if c>=spj then nt=nt+1 elseif c<spg then nl=nl+1 else nb=nb+1 end
        else if c>spg and c<spj then nh=nh+1 else nb=nb+1 end end end end
    n=n+1; if nb>0 then bad=bad+1 end
    out:write(string.format("%s gf %d set %d spj %d spg %d heads top %d lower %d hole %d out-of-place %d\n",nb>0 and "BAD" or "ok",HARNESS_GAME_FRAME(),w,spj,spg,nt,nl,nh,nb))
    spj=0 end
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(FZD_ON&~1,(FZD_ON&~1)+1,"hole",function(o,d,mk) local ok,e=pcall(on,o,d,mk); if not ok then out:write("ERR "..tostring(e).."\n") end end)} end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end
  if f>=N then out:write(string.format("holes %d bad %d\n",n,bad)); out:close(); m:exit() end end)
