-- vtap.lua: VRAM data writes that land in the fix layer ($7000-$7fff) via the LSPC port
-- (REG_VRAMADDR 0x3c0000, REG_VRAMRW 0x3c0002, REG_VRAMMOD 0x3c0004): per write the real
-- frame, PC, address, data, from frame F0 on; and per 100 frames a count by PC.  Env: OUT, N, F0
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]; local scr=m.screens[":screen"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "6050"); local F0=tonumber(os.getenv("F0") or "5500")
local addr, mod = 0, 1
local bypc = {}
local taps = {}
local function inst()
  for _,t in ipairs(taps) do t:remove() end; taps={}
  taps[1]=sp:install_write_tap(0x3c0000,0x3c0005,"vr",function(o,d,mk)
    if o==0x3c0000 then addr=d&0xffff
    elseif o==0x3c0004 then mod=d&0xffff; if mod>=0x8000 then mod=mod-0x10000 end
    elseif o==0x3c0002 then
      if addr>=0x7000 and addr<=0x7fff then
        local pc=cpu.state["PC"].value; local f=scr:frame_number()
        bypc[pc]=(bypc[pc] or 0)+1
        if f>=F0 then out:write(string.format("W %d %06x %04x %04x\n",f,pc,addr,d&0xffff)) end
      end
      addr=(addr+mod)&0xffff
    end
  end)
end
inst()
emu.register_frame_done(function()
  local f=HARNESS_GAME_FRAME(); local rf=scr:frame_number()
  if rf%100==0 then
    local t={} for pc,n in pairs(bypc) do t[#t+1]=string.format("%06x:%d",pc,n) end; table.sort(t)
    out:write(string.format("C %d %s\n",rf,table.concat(t," "))); bypc={}; out:flush(); inst()
  end
  if rf>=N then out:close(); m:exit() end
end)
