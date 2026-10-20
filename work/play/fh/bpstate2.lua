-- bpstate2.lua (BP_STABLE build, fz68 record format: w1 = SCB4 | index low 7, w2 bit 7 = index bit 7): per frame BP_ST, BP_NV, BP_SHOWN, BP_SEENM, owned slots, the shown
-- set's record count and each record's identity (w0/w1 high nibbles) and key (w2, w3).  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "4000")
local SHOWN=tonumber(os.getenv("SHOWNADDR") or "0")
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME()
  if f>300 then
    local own=0 for i=0,31 do if sp:read_u8(0xd0f3b0+i)~=0 then own=own+1 end end
    local set=sp:read_u16(SHOWN)&7; local n=sp:read_u16(0xd0e33a+2*set); local r={}
    for i=0,math.min(n,16)-1 do local a=0xd0e000+set*256+i*8; local w0,w1,w2,w3=sp:read_u16(a),sp:read_u16(a+2),sp:read_u16(a+4),sp:read_u16(a+6)
      r[#r+1]=string.format("%d:%04x/%04x",(w1&0x7f)|(w2&0x80),w2,w3) end
    out:write(string.format("%d st %d nv %d shown %d seen %08x own %d set %d n %d %s\n",f,sp:read_u8(0xd00fea),sp:read_u16(0xd0f2a0),sp:read_u16(0xd0f20e),sp:read_u32(0xd0f3d0),own,set,n,table.concat(r," "))) end
  if f>=N-5 then out:close(); m:exit() end end)
