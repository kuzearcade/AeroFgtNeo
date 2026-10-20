-- botsel.lua (HARNESS_BOTFILE): botfire.lua's autofire and boss bombs, plus the pilot select:
-- NATION=<0..3> is chosen on the pilot-select screen (both players share one cursor, the
-- first pilot of the nation for P1, the second for P2).  The select handler (0x8e6c) stores
-- the cursor at 0xffc000 every frame it runs: a write tap there says the screen is up and
-- what the cursor is; the bot then presses right (an edge a frame, released between) until
-- the cursor is the nation, then the button; the movie's own inputs are replaced meanwhile.
-- Per frame to <OUT dir>/bot.txt: frame, boss active (0/1), bombs P1, bombs P2, active objects,
-- bomb presses so far, the boss type, the stage index (0xffc110), the stage id (0xffc100[index-1]),
-- the pilot (0xffc000), lives P1, lives P2, player shots active (types $0e-$17), and the counts of
-- shot types $11, $12, $16, $17, $0e, $18.  Addresses: the original's work RAM at 0xff0000 is the
-- conversion's at 0x101000 (- 0xeef000); 0xffc000 is 0x10d000.
local BOSS={77,78,79,80,81,91,92,98,99,102,103,104,106,118,119,120,121,122,131,144,145,146,147,148,149,150,151,154,156,162,163,164,165,166,167,168,169,170,171,172,173}
local bt={}; for _,t in ipairs(BOSS) do bt[t]=true end
local neo=(HARNESS_TARGET=="neo"); local sp=HARNESS_SPACE
local B=neo and 0x101000 or 0xff0000          -- the pools: OBJ1 .. OBJ5 (end), 0x60 a slot
local PEND=B+0x60c0
local PL={B+0x6c0, B+0x720}                    -- the players (+0x1e bombs, +0x1c lives)
local C=neo and 0x10d000 or 0xffc000           -- 0xffc000 the pilot, +0x100 the stage order, +0x110 the index
local BOMBHOLD=tonumber(os.getenv("BOMBHOLD") or "2"); local NATION=tonumber(os.getenv("NATION") or "0"); local NATION2=os.getenv("NATION2") and tonumber(os.getenv("NATION2")) or nil
local SEEDLO=os.getenv("SEEDLO") and tonumber(os.getenv("SEEDLO"),16) or nil; local confirming=0; local SEEDSET=os.getenv("SEEDSET") and tonumber(os.getenv("SEEDSET"),16) or nil; local seedset=false
local out=io.open((os.getenv("OUT") or "lag.txt"):gsub("[^/]*$","bot.txt"),"w")   -- (next to the probe's OUT)
local presses=0
local selseen=-10; local selcur=0; local pressed=0; local lastgf=0   -- (lastgf: the bot's own counter - the frame, or the round under HARNESS_BY_ROUND)
local tap=nil
local scrtap=nil
local function inst()
  if tap then tap:remove() end
  if os.getenv("SCRTAP") then   -- (SCRTAP=1: log any non-zero write to the scroll words 0xff8b4a/c, G_DX_SCRX/SCRY)
    if scrtap then scrtap:remove() end
    local S=neo and 0x109b4a or 0xff8b4a
    scrtap=sp:install_write_tap(S,S+3,"scr",function(o,d,mk) if (d&mk)~=0 then out:write(string.format("SCR %d %x %x %x\n",lastgf,o,d,mk)) end end)
  end
  tap=sp:install_write_tap(C,C+1,"sel",function(o,d,mk) if o==C then selseen=lastgf; selcur=d&0xffff; if os.getenv("SELDBG") then out:write(string.format("S %d %d %d\n",selseen,selcur,o)) end end end)
end
inst()
function HARNESS_BOT(gf, v)
  lastgf=gf
  if gf%500==0 then inst() end
  local boss=false; local btype=0
  local nact=0; local nshot=0; local n11,n12,n16,n17,n0e,n18=0,0,0,0,0,0
  for a=B,PEND-1,0x60 do
    if sp:read_u8(a)~=0 then nact=nact+1
      local t=sp:read_u16(a+0x16)
      if bt[t] then boss=true; btype=t end
      if t>=0x0e and t<=0x17 then nshot=nshot+1 end
      if t==0x11 then n11=n11+1 elseif t==0x12 then n12=n12+1 elseif t==0x16 then n16=n16+1 elseif t==0x17 then n17=n17+1 elseif t==0x0e then n0e=n0e+1 elseif t==0x18 then n18=n18+1 end
    end
  end
  local w={v[1],v[2],v[3]}
  local bombs={}
  local insel=(gf-selseen)<=1
  if insel then
    -- the pilot select: the movie's inputs out; right until the cursor is the nation, then A
    w[1]=0xff; w[2]=0xff
    -- (the game debounces: a press counts once held two frames, an edge once the held value
    -- changes - 0xde2: held two frames, released two)
    -- (SEEDLO=<hex>: the button only once the random seed's low byte (0xffc112, stepped once a
    -- frame while the screen is up, period 256) is that value: the stage order (0x9468) is a
    -- function of that byte, so runs on different builds then play the same stages in the same
    -- order; without it the order follows how long the select took, i.e. the build's lag)
    local seed=sp:read_u16(C+0x112)
    if os.getenv("SELDBG") then out:write(string.format("S %d cur %d seed %04x\n",gf,selcur,seed)) end
    pressed=(pressed+1)%4
    if SEEDSET and selcur==NATION and not seedset then sp:write_u16(C+0x112,SEEDSET); seedset=true end   -- (SEEDSET=<hex>: the seed
                                                 -- written once the cursor is on the nation: the same stage order on every build - for A/B runs only)
    -- (the handler ORs the inputs of the players in the game - one cursor, both players get
    -- the nation, P1 its first pilot, P2 its second; a player joining mid-game selects alone:
    -- the presses go to both players, and NATION2=<0..3> is the nation of a select after the
    -- game began - the mixed-nation games of the profile matrix, 2026-10-19)
    local want=NATION
    if NATION2 and sp:read_u16(C+0x110)>0 then want=NATION2 end
    if selcur~=want then
      if pressed<2 then w[1]=0xff&~0x08; w[2]=0xff&~0x08 end
    elseif SEEDLO==nil or (seed&0xff)==SEEDLO or confirming>0 then
      confirming=confirming+1
      if pressed<2 or confirming>1 then w[1]=0xff&~0x10; w[2]=0xff&~0x10 end
    end
  else
    pressed=0; confirming=0; seedset=false
    for p=1,2 do
      local b=w[p]|0x30                           -- the shot and bomb bits released
      if gf%4~=3 then b=b&~0x10 end              -- autofire: held 3 frames, released 1 (the game
                                                 -- counts a button once held 2 frames, 0xde2, and
                                                 -- fires on the held value's edge, then while held)
      bombs[p]=sp:read_u16(PL[p]+0x1e)
      if boss and bombs[p]>0 and sp:read_u8(PL[p])~=0 and gf%24<BOMBHOLD then b=b&~0x20; if gf%24==0 then presses=presses+1 end end
      w[p]=b
    end
  end
  bombs[1]=bombs[1] or sp:read_u16(PL[1]+0x1e); bombs[2]=bombs[2] or sp:read_u16(PL[2]+0x1e)
  local idx=sp:read_u16(C+0x110); local sid=255
  if idx>=1 and idx<=7 then sid=sp:read_u8(C+0x100+idx-1) end
  out:write(string.format("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",gf+1,boss and 1 or 0,bombs[1],bombs[2],nact,presses,btype,idx,sid,sp:read_u16(C),sp:read_u8(PL[1]+0x1c),sp:read_u8(PL[2]+0x1c),nshot,n11,n12,n16,n17,n0e,n18))
  if gf%500==0 then out:flush() end
  return w
end
