-- botfire.lua (HARNESS_BOTFILE): over the movie's rows, autofire (the shot pressed every other
-- frame, both players) and the bombs spent during boss fights (a bomb press 2 frames in every 24
-- while an object of a boss type is active in the stage pool and the player has bombs); the movie's
-- own bomb presses dropped.  Per frame to <OUT dir>/bot.txt: frame, boss active (0/1), bombs P1, bombs
-- P2, active objects in the pools, bomb presses so far, the boss type seen (every pool scanned).  Addresses: the original's work RAM at
-- 0xff0000 is the conversion's at 0x101000 (- 0xeef000).
local BOSS={77,78,79,80,81,91,92,98,99,102,103,104,106,118,119,120,121,122,131,144,145,146,147,148,149,150,151,154,156,162,163,164,165,166,167,168,169,170,171,172,173}
local bt={}; for _,t in ipairs(BOSS) do bt[t]=true end
local neo=(HARNESS_TARGET=="neo"); local sp=HARNESS_SPACE
local B=neo and 0x101000 or 0xff0000          -- the pools: OBJ1 .. OBJ5 (end), 0x60 a slot
local P4=B+0x48c0; local P4N=64; local PEND=B+0x60c0
local PL={B+0x6c0, B+0x720}                    -- the players (+0x1e bombs)
local out=io.open((os.getenv("OUT") or "lag.txt"):gsub("[^/]*$","bot.txt"),"w")   -- (next to the probe's OUT)
local presses=0
function HARNESS_BOT(gf, v)
  local boss=false; local btype=0
  local nact=0
  for a=B,PEND-1,0x60 do
    if sp:read_u8(a)~=0 then nact=nact+1
      local t=sp:read_u16(a+0x16)
      if bt[t] then boss=true; btype=t end
    end
  end
  local w={v[1],v[2],v[3]}
  local bombs={}
  for p=1,2 do
    local b=w[p]|0x30                           -- the shot and bomb bits released
    if gf%4~=3 then b=b&~0x10 end              -- autofire: held 3 frames, released 1 (the game counts a
                                               -- button once held 2 frames (0xde2) and fires on the held
                                               -- value's edge, then while held: the 2-frame cadence of
                                               -- 2026-10-18 never fired a main shot, AUDIT.md 30)
    bombs[p]=sp:read_u16(PL[p]+0x1e)
    if boss and bombs[p]>0 and sp:read_u8(PL[p])~=0 and gf%24<2 then b=b&~0x20; if gf%24==0 then presses=presses+1 end end
    w[p]=b
  end
  out:write(string.format("%d %d %d %d %d %d %d\n",gf+1,boss and 1 or 0,bombs[1],bombs[2],nact,presses,btype))
  if gf%500==0 then out:flush() end
  return w
end
