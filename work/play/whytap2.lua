-- whytap.lua: per failed update try (DL_WHY written) its reason, with the ring split or not,
-- the hole flag, ORDN, the newest set's state; and hole/ooo commits
dofile(os.getenv("HOME").."/AeroFgtNeo/tests/harness.lua")
local sp=manager.machine.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("V_OUT"),"w")
local T={}; local taps={}; local f=0; local nc,nh,no=0,0,0
local function onwhy(o,d,m)
  if (o&~1)~=0xd0e5e0 then return end
  local sps=sp:read_i8(0xd00fde); local ordn=sp:read_u8(0xd00fae)
  local nw=ordn>0 and sp:read_u8(0xd00faf+ordn-1) or -1
  local st=nw>=0 and sp:read_u8(0xd00b68+nw) or -1
  local k=string.format("why%d spg%d spj%d split%d own%d ordn%d st%d hole%d ooo%d",d,0,0,sps>=0 and 1 or 0,(sps==nw) and 1 or 0,ordn,st,sp:read_u8(0xd0f6e0),sp:read_u8(0xd0f6e2))
  T[k]=(T[k] or 0)+1 end
local function ondelta(o,d,m) if (o&~1)==0xd0f620 and (m&0xff00)~=0 and (d>>8)==1 then nc=nc+1; if sp:read_u8(0xd0f6e0)~=0 then nh=nh+1 end; if sp:read_u8(0xd0f6e2)~=0 then no=no+1 end end end
local function inst() for _,t in ipairs(taps) do t:remove() end; taps={sp:install_write_tap(0xd0e5e0,0xd0e5e1,"why",onwhy),sp:install_write_tap(0xd0f620,0xd0f621,"dl",ondelta)} end
inst()
emu.register_frame_done(function() f=f+1; if f%300==0 then inst() end
  if f%20000==0 then out:write(string.format("F %d commits %d ooo %d hole %d\n",f,nc,no,nh))
    local ks={} for k,v in pairs(T) do ks[#ks+1]=k end table.sort(ks, function(a,b) return T[a]>T[b] end)
    for i=1,math.min(#ks,25) do out:write(string.format("  %7d %s\n",T[ks[i]],ks[i])) end out:flush() end end)
