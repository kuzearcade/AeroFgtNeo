-- bramw.lua: who writes the backup RAM (0xd00000-0xd0ffff): per 16-byte line the first frame and
-- PC of a BIOS write (PC >= 0xc00000) and of a cartridge write (PC < 0xc00000), over N frames;
-- and at the end the BIOS's game soft DIP area BIOS_GAME_DIP (0x10fd84, 16 bytes).  Env: OUT, N
local m=manager.machine; local cpu=m.devices[":maincpu"]; local sp=cpu.spaces["program"]
local out=io.open(os.getenv("OUT"),"w"); local N=tonumber(os.getenv("N") or "1500")
local f=0; local B={}; local C={}
local tap=nil
local function wr(o,d,mk)
  local pc=cpu.state["CURPC"].value; local l=o&0xfffff0
  if pc>=0xc00000 then if not B[l] then B[l]={f,pc} end else if not C[l] then C[l]={f,pc} end end end
emu.register_frame_done(function() f=f+1
  if f==1 or f%300==0 then if tap then tap:remove() end; tap=sp:install_write_tap(0xd00000,0xd0ffff,"bram",wr) end
  if f>=N then
    local ks={} for k in pairs(B) do ks[#ks+1]=k end table.sort(ks)
    for _,k in ipairs(ks) do out:write(string.format("BIOS %06x f %d pc %06x%s\n",k,B[k][1],B[k][2],C[k] and string.format("  cart too: f %d pc %06x",C[k][1],C[k][2]) or "")) end
    local kc={} for k in pairs(C) do if k<0xd00420 then kc[#kc+1]=k end end table.sort(kc)
    for _,k in ipairs(kc) do out:write(string.format("CART %06x f %d pc %06x\n",k,C[k][1],C[k][2])) end
    local g={} for i=0,15 do g[#g+1]=string.format("%02x",sp:read_u8(0x10fd84+i)) end
    out:write("BIOS_GAME_DIP "..table.concat(g," ").."\n")
    out:close(); m:exit() end end)
