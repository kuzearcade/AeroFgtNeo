-- fliphash3.lua (each head's own column only: no chain walk into the ring's neighbours); fliphash2.lua (content only: no column addresses, so a set begun elsewhere in the ring with the same sprites hashes the same); fliphash.lua: per sprite-set flip (HAL_SPR_SHOWN written in hal_spr_flip, after the
-- heads are shown): a hash of the shown set as the Neo VRAM holds it: per head (SS_HADR
-- order) its SCB3 value, its SCB4, and for the head's column and every column chained
-- above it the SCB2 word and the SCB1 tile/attribute words of the rows the head shows.
-- One line per flip: game frame, HAL_FRAMES, set, heads, columns, hash, HAL_SPR_LATE,
-- the set's HAL_SPR_MIX byte, HAL_SPR_DROPN.  Env: OUT.
-- A/B: two builds on the same bot movie must give the same hash per HAL_FRAMES wherever
-- neither run was late/dropped/held (AUDIT.md 24, stage 0).
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local sp=m.devices[":maincpu"].spaces["program"]
local vi=nil
for name, idx in pairs(m.devices[":spritegen"].items) do
  if name:find("m_videoram") then vi=emu.item(idx) end
end
local out=io.open(os.getenv("OUT"),"w")
local SETS=0x10a280; local SSZ=510; local HOFF=10; local HADR=62; local HVAL=286
local function hash(s)
  local ss=SETS+SSZ*s; local nh=sp:read_u16(ss+HOFF)//2
  local h=2166136261; local nc=0
  local function mix(v) h=((h ~ (v & 0xffff))*16777619) & 0xffffffff end
  for i=0,nh-1 do
    local a=sp:read_u16(ss+HADR+2*i); local v=sp:read_u16(ss+HVAL+2*i)
    local col=a-0x8200
    mix(v)
    local rows=v & 0x3f; if rows>32 then rows=32 end
    local c=col
    mix(vi:read(0x8400+c)); mix(vi:read(0x8000+c))
    local b=64*c
    for r=0,2*rows-1 do mix(vi:read(b+r)) end
    nc=nc+1
  end
  return nh,nc,h
end
local taps={}
local function onw(o,d,mk)
  if (o&~1)~=0xd00b9c then return end
  local s=d & 0xffff; if s>2 then return end
  local nh,nc,h=hash(s)
  out:write(string.format("%d %d %d %d %d %08x %d %d %d\n",HARNESS_GAME_FRAME(),sp:read_u32(0xd0085c),s,nh,nc,h,
    sp:read_u32(0xd00ba4),sp:read_u8(0xd00b6c+s),sp:read_u32(0xd00bf8)))
end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd00b9c,0xd00b9d,"fh",onw)} end
inst()
local f=0
emu.register_frame_done(function() f=f+1; if f%300==0 then inst(); out:flush() end end)
