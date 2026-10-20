-- excv.lua: exceptions taken by the 68000 - a read tap on the vector table (0x08..0x3f: bus
-- error, address error, illegal, divide, chk, trapv, privilege, trace, line A/F) fires when
-- the CPU fetches a vector; the exception frame is on the stack then: for a bus/address
-- error SP+0 the special status word, +2 the access address, +6 the instruction register,
-- +8 SR, +10 PC; for the others SR at +0 and PC at +2.  Also the game's reset vector fetch
-- (0x04) after the boot.  Logs: game frame, vector, SP, the frame's words.  Env: OUT, N
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "90000")
local n=0
local function onv(o,d,mk)
  local f=HARNESS_GAME_FRAME(); if f<10 then return end
  n=n+1; if n>40 then return end
  local s=cpu.state["SP"].value
  out:write(string.format("gf %d vector %02x SP %06x frame %04x %04x %04x %04x %04x %04x %04x\n",f,o,s,sp:read_u16(s),sp:read_u16(s+2),sp:read_u16(s+4),sp:read_u16(s+6),sp:read_u16(s+8),sp:read_u16(s+10),sp:read_u16(s+12)))
  if o>=0x08 then
    local r={} for _,n in ipairs({"D0","D1","D2","D3","D4","D5","D6","D7","A0","A1","A2","A3","A4","A5","A6","PC"}) do r[#r+1]=string.format("%s=%08x",n,cpu.state[n].value) end
    local FZV=0xd0e300; local rec=sp:read_u32(FZV)
    out:write("  regs "..table.concat(r," ").."\n")
    out:write(string.format("  FZ_REC %08x FZ_RECS %08x FZ_RECE %08x FZ_LEFT %d FZ_PH %d RA5 %08x RTN %08x W %d SPS %d\n",rec,sp:read_u32(FZV+8),sp:read_u32(FZV+76),sp:read_i16(FZV+28),sp:read_i8(FZV+30),sp:read_u32(0xd00bf4),sp:read_u32(FZV+4),sp:read_i16(0xd00b98),sp:read_i8(0xd00fde)))
    for k=-3,0 do local a=rec+16*k; if a>=0xd0e000 and a<0xd10000 then out:write(string.format("  rec%+d @%08x: %s\n",k,a,sp:read_range(a,a+15,8):gsub(".",function(c) return string.format("%02x",c:byte()) end))) end end
    local a5=cpu.state["A5"].value; if a5>=0xd0e000 and a5<0xd10000 then out:write(string.format("  at a5 %08x: %s\n",a5,sp:read_range(a5-16,a5+15,8):gsub(".",function(c) return string.format("%02x",c:byte()) end))) end
  end
  out:flush()
end
local taps={}
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_read_tap(0x04,0x3f,"excv",onv)} end
inst()
emu.register_frame_done(function() local f=HARNESS_GAME_FRAME(); if f%500==0 then inst() end; if f>=N-5 then out:close(); m:exit() end end)
