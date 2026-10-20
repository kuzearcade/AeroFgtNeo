-- entries.lua: the sprite entries each build makes per logic round, for the fused build's
-- A/B (AUDIT.md 24 stage 1): per round, the sequence of 4-word entries (and pool records)
-- in the order they are made.  TGT=ov10: the walk's list writes (FX_LISTS buffers in
-- sprite RAM, each entry's w3 last; the pool records after the pieces the same way), keyed
-- by the round count at the write (the walk runs after the round ended).  TGT=fz (an
-- FZ_DIAG build): the pass's dispatched words (FZ_DW, written in fz_disp) and its pool
-- records (FZ_POOL), keyed by the round the records were built in (the buffer's completion
-- tapped: FZB_ST := 1).  One line per round: round, entries, hash, then the entries in hex
-- when DETAIL=1.  Env: OUT, TGT, N (frames), DETAIL
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w")
local TGT=os.getenv("TGT") or "ov10"; local N=tonumber(os.getenv("N") or "3000"); local DETAIL=os.getenv("DETAIL")=="1"
local round=0
local cur={}   -- round -> list of entry strings
local function add(r,e) local t=cur[r]; if not t then t={}; cur[r]=t end; t[#t+1]=e end
local function entry(a) return string.format("%04x%04x%04x%04x",sp:read_u16(a),sp:read_u16(a+2),sp:read_u16(a+4),sp:read_u16(a+6)) end
-- (a write tap fires before the write: the word being written comes from the tap's data)
local function entryw(a,d) return string.format("%04x%04x%04x%04x",sp:read_u16(a),sp:read_u16(a+2),sp:read_u16(a+4),d&0xffff) end
local function flush(upto)
  local ks={} for r in pairs(cur) do if r<upto then ks[#ks+1]=r end end
  table.sort(ks)
  for _,r in ipairs(ks) do
    local t=cur[r]; local h=2166136261
    for _,e in ipairs(t) do for i=1,#e do h=((h ~ e:byte(i))*16777619) & 0xffffffff end end
    out:write(string.format("%d %d %08x%s\n",r,#t,h,DETAIL and (" "..table.concat(t," ")) or ""))
    cur[r]=nil
  end
  out:flush()
end
local taps={}
local function onr(o,d,mk)
  if (o&~1)~=0x10a236 then return end
  local pc=cpu.state["PC"].value
  if pc>=0x2bfaa and pc<=0x2bfb6 then round=round+1 end
end
local list={}
if TGT=="ov10" then
  -- the walk's end (FX_SDONE := $ff, hal/fx.s fx_snap_step): its buffer's pieces (FX_LN)
  -- and pool records (FX_PBN), the round at the end being the round it saw
  local FXS=0xd0f000; local LT={0xd0e000,0xd0e800,0xd0ec00,0xd0f800,0xd0fc00}
  local function ondone(o,d,mk)
    if (o&~1)~=FXS+22 then return end
    local v=(o==FXS+22) and ((d>>8)&0xff) or (d&0xff)
    if (o==FXS+22 and ((mk>>8)&0xff)==0) or v~=0xff then return end
    local b=sp:read_u16(FXS+62); if b>4 then return end
    local n=sp:read_u16(FXS+0x180+2*b); local np=sp:read_u16(FXS+0x200+2*b)
    local a=LT[b+1]
    for i=0,math.min(n,96)-1 do add(round,entry(a+8*i)) end
    for i=0,math.min(np,32)-1 do add(round,"P"..entry(a+8*96+8*i)) end
    if n==0 and np==0 then add(round,"") end
  end
  local function inst()
    for _,t in ipairs(taps) do t:remove() end
    taps={sp:install_write_tap(0x10a236,0x10a237,"rd",onr),sp:install_write_tap(FXS+22,FXS+23,"done",ondone)}
  end
  inst()
  emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end; if f%50==0 then flush(round-3) end; if f>=N then flush(round+1); out:close(); m:exit() end end)
else
  local FZV=0xd0e300; local BUFT={0xd0e510,0xd0e510+1312,0xd0f800}
  local bround={}   -- buffer address -> round built
  local function onst(o,d,mk)
    for _,b in ipairs(BUFT) do if o==(b+4)&~1 and ((mk>>8)&0xff)~=0 and ((d>>8)&0xff)==1 then bround[b]=round end end
  end
  local function prnd() if TGT=="gt" then return round end local pb=sp:read_u32(FZV+12); return bround[pb] or -1 end
  local function ondw(o,d,mk) if o==FZV+108+6 then add(prnd(),entryw(FZV+108,d)) end end
  local function onpool(o,d,mk) if (o&7)==6 then add(prnd(),"P"..entryw(o-6,d)) end end
  local function inst()
    for _,t in ipairs(taps) do t:remove() end
    taps={sp:install_write_tap(0x10a236,0x10a237,"rd",onr),sp:install_write_tap(FZV+108,FZV+115,"dw",ondw),sp:install_write_tap(0xd0e000,0xd0e2ff,"pool",onpool)}
    for i,b in ipairs(BUFT) do taps[#taps+1]=sp:install_write_tap(b+4,b+5,"st"..i,onst) end
  end
  inst()
  emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%300==0 then inst() end; if f%50==0 then flush(round-3) end; if f>=N then flush(round+1); out:close(); m:exit() end end)
end
