-- gxtrace.lua (HARNESS_TARGET=orig): AUDIT 43 point (4) - do targets change between two calls of
-- shot_collide (0x2a142) in the same pass of the main object loop (0x1996a)?  At each call: the
-- target set of the three pools (slots with (b0 & $31) = 1, their x words 80/84 and, with 76 set,
-- 88/92) against the previous call's in the pass; the 32-pixel x bands of each target (playfield
-- left from the bounds table at 0x50858 + 0x178).  Also: handlers of target-pool slots run between
-- two calls of a pass (the dispatch at 0x19994, a0 = the slot), and the callers (the return address).
-- Env: OUT, F0, F1.  Arcade RAM: game 0x100000 = 0xfef000 here.
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local F0=tonumber(os.getenv("F0") or "3000"); local F1=tonumber(os.getenv("F1") or "60000")
local R=0xeef000                         -- game address 0x100000.. -> 0xfef000.. (the harness map)
local POOLS={{0x1019c0,0x18},{0x1040c0,0x10},{0x1052c0,0x30}}
local f=0; local on=false
local prev=nil; local prevsh=false; local tgtran=false; local passcalls=0
local st={calls=0,passes=0,multi=0,same=0,chg=0,bandchg=0,gain=0,lose=0,xmove=0,bandmove=0,tgtran=0,tgtran_chg=0}
local callers={}; local shotslots={}; local ex={}
local function bandsof(l,r,x0)
  local b0=(l-x0)>>5; local b1=(r-x0)>>5; return b0,b1 end
local function snap()
  local bt=sp:read_u32(0x50858+0x178)
  local x0=(sp:read_u16(bt)~0x8000)
  local s={}; local nt=0
  for _,p in ipairs(POOLS) do
    for i=0,p[2]-1 do local a=p[1]+i*0x60+R
      local b=sp:read_u8(a)
      if (b&0x31)==1 then
        local l1,r1=sp:read_u16(a+80),sp:read_u16(a+84)
        local h2=sp:read_u8(a+76); local l2,r2=0,0
        local l,r=l1,r1
        if h2~=0 then l2,r2=sp:read_u16(a+88),sp:read_u16(a+92); if l2<l then l=l2 end; if r2>r then r=r2 end end
        local ba,bb=bandsof(l,r,x0)
        s[a-R]={l1,r1,h2,l2,r2,ba,bb}; nt=nt+1; st.span=(st.span or 0)+(bb-ba+1)
      end end end
  st.tg=(st.tg or 0)+nt; return s
end
local function cmp(a,b)
  local d={gain=0,lose=0,xmove=0,bandmove=0}
  for k,v in pairs(b) do local u=a[k]
    if not u then d.gain=d.gain+1 else
      if u[1]~=v[1] or u[2]~=v[2] or u[3]~=v[3] or u[4]~=v[4] or u[5]~=v[5] then d.xmove=d.xmove+1 end
      if u[6]~=v[6] or u[7]~=v[7] then d.bandmove=d.bandmove+1 end end end
  for k,_ in pairs(a) do if not b[k] then d.lose=d.lose+1 end end
  return d
end
-- (the 68000's prefetch: a tap on an instruction's FIRST word fires during the one before it; its
-- second word's fetch has PC = that word: each tap is on the second word of a longer instruction)
local taps={}
local function inst()
  for _,t in ipairs(taps) do t:remove() end; taps={}
  taps[#taps+1]=sp:install_read_tap(0x1996c,0x1996d,"pass",function()
    if cpu.state["PC"].value==0x1996c and on then
      if passcalls>1 then st.multi=st.multi+1 end
      if passcalls>0 then st.passes=st.passes+1 end
      prev=nil; tgtran=false; passcalls=0 end end)
  taps[#taps+1]=sp:install_read_tap(0x19996,0x19997,"hdl",function()
    if cpu.state["PC"].value==0x19996 and on and prev then
      local a=cpu.state["A0"].value-R
      for _,p in ipairs(POOLS) do if a>=p[1] and a<p[1]+p[2]*0x60 then tgtran=true end end end end)
  taps[#taps+1]=sp:install_read_tap(0x2a144,0x2a145,"col",function()
    if cpu.state["PC"].value~=0x2a144 or not on then return end
    st.calls=st.calls+1; passcalls=passcalls+1
    local sh=cpu.state["A0"].value-R; local ra=sp:read_u32(cpu.state["SP"].value)
    callers[ra]=(callers[ra] or 0)+1; local sk=string.format("%x",sh&0xfff000); shotslots[sk]=(shotslots[sk] or 0)+1
    local insh=(sh>=0x1022c0 and sh<0x1040c0); if not insh then st.outside=(st.outside or 0)+1 end
    local s=snap()
    if prev and insh and prevsh then
      local d=cmp(prev,s)
      if tgtran then st.tgtran=st.tgtran+1 end
      if d.gain+d.lose+d.xmove==0 then st.same=st.same+1 else
        st.chg=st.chg+1; if tgtran then st.tgtran_chg=st.tgtran_chg+1 end
        st.gain=st.gain+d.gain; st.lose=st.lose+d.lose; st.xmove=st.xmove+d.xmove
        if d.gain+d.bandmove>0 then st.bandchg=st.bandchg+1 end
        st.bandmove=st.bandmove+d.bandmove
        if #ex<40 then ex[#ex+1]=string.format("f %d shot %x caller %x tgtran %s gain %d lose %d xmove %d bandmove %d",f,sh,ra,tostring(tgtran),d.gain,d.lose,d.xmove,d.bandmove) end
      end
    end
    prev=s; prevsh=insh; tgtran=false end)
end
inst()
emu.register_frame_done(function() f=HARNESS_GAME_FRAME(); on=(f>=F0); inst()
  if f>=F1 then
    out:write(string.format("frames %d..%d calls %d passes(with calls) %d passes with >1 call %d\n",F0,F1,st.calls,st.passes,st.multi))
    out:write(string.format("call pairs in a pass: unchanged %d changed %d (gain %d lose %d xmove %d; band-relevant %d, bandmove %d)\n",st.same,st.chg,st.gain,st.lose,st.xmove,st.bandchg,st.bandmove))
    out:write(string.format("calls from outside the shot region %d\n",st.outside or 0))
    out:write(string.format("targets per call %.2f, bands per target %.2f\n",(st.tg or 0)/math.max(st.calls,1),(st.span or 0)/math.max(st.tg or 1,1)))
    out:write(string.format("pairs with a target-pool handler between: %d (of them changed %d)\n",st.tgtran,st.tgtran_chg))
    for k,v in pairs(callers) do out:write(string.format("caller %x %d\n",k,v)) end
    for k,v in pairs(shotslots) do out:write(string.format("shot page %s %d\n",k,v)) end
    for _,e in ipairs(ex) do out:write(e.."\n") end
    out:close(); m:exit() end end)
