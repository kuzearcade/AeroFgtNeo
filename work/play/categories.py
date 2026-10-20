"""categories.py: object type -> category, description (from the rendered sheets work/catalog/sprites/type_*.png
and where each type appears) -> work/catalog/sprites/categories.tsv and categories.md"""
import json, hashlib, glob, collections, os
C = 'work/play/cen'; O = json.load(open('work/catalog/sprites/objects.json'))
STAGE = {'f864c44b': 'attract demo', '925a6b96': 'coast/mountain river', 'c76be495': 'military base A', '4509f48d': 'city 1 (skyscrapers)',
         'c9e34390': 'city 2 (streets)', '41841f1c': 'jungle base', '3abea85c': 'river valley', '1b9b5afb': 'city 3 (ruins)',
         'b9fc1cc0': 'military base B', 'd4064101': 'desert (boss)', '5c1b5af9': 'night ocean (fleet)', 'd483e2b9': 'runway / space finale',
         'b4ab461b': 'final stage', '5a3e9faa': 'desert', '6efef99c': 'map / select', '42e3a930': 'stage intro screens'}
CAT = {
 # player side
 '0000': ('player', 'player aircraft (per pilot, banking frames)'),
 '0010': ('player', 'player option / support pod'),
 '0011': ('player shots', 'player main shot (twin)'), '0012': ('player shots', 'player main shot (power-up levels)'),
 '000f': ('player shots', 'player secondary shot / missile'), '000e': ('player shots', 'shot impact spark'),
 '0016': ('player shots', 'player special weapon sparks'), '0017': ('player shots', 'player support-weapon projectiles'),
 '000d': ('player bomb', 'bomb blast (screen-filling disc)'), '0020': ('player bomb', 'bomb flash / big explosion stages'),
 # HUD / text
 '0002': ('HUD/text', 'lives and bomb stock icons'), '0003': ('HUD/text', '"PRESS 1P/2P BUTTON" prompt'),
 '0004': ('HUD/text', '"CREDIT" counter'), '0005': ('HUD/text', 'digits (credits, continue count)'),
 '0006': ('HUD/text', '"GAME OVER" / "CONTINUE?"'), '0001': ('screens', 'title, map, pilot select and intro screen sprites (portraits, world map, logos)'),
 # enemy fire
 '000b': ('enemy bullets', 'small round bullets (most frequent sprite in the game)'), '002d': ('enemy bullets', 'small red bullets'),
 '0018': ('enemy bullets', 'pair bullets (two-piece, the bullet storm)'), '00cb': ('enemy bullets', 'ring bullets'),
 '00ca': ('enemy bullets', 'oval / laser bullets'), '0069': ('enemy bullets', 'desert missiles'), '0073': ('enemy bullets', 'ocean missiles'),
 '0074': ('enemy bullets', 'ocean torpedoes'), '007b': ('enemy bullets', 'ocean shells'), '00a0': ('enemy bullets', 'finale bullets'),
 '00a1': ('enemy bullets', 'finale streak shots'), '0065': ('enemy bullets', 'desert shells'),
 # effects
 '0009': ('explosions', 'explosions (regular)'), '0033': ('explosions', 'ring / sparkle burst'), '0099': ('explosions', 'smoke clouds (finale)'),
 '009b': ('explosions', 'smoke puffs (finale)'), '006c': ('explosions', 'sand / dust puffs (desert)'), '0060': ('explosions', 'debris (desert)'),
 # shadows
 '002f': ('shadows', 'enemy aircraft shadows'), '0034': ('shadows', 'aircraft shadows (ground stages)'), '0088': ('shadows', 'large bomber shadow'),
 '0038': ('terrain overlay', 'cloud overlay sprites'), '0037': ('terrain overlay', 'rock / crater overlay (finale)'),
 # air enemies
 '002e': ('enemy aircraft', 'fighter jets (many formations; 109 tables)'), '0030': ('enemy aircraft', 'fighter jets (variant)'),
 '0031': ('enemy aircraft', 'fighter jets (variant 2)'), '0032': ('enemy aircraft', 'fighter jets (variant 3)'),
 '0021': ('enemy aircraft', 'escort jets (base B)'), '0036': ('enemy aircraft', 'heavy bombers / gunships'),
 '0035': ('enemy aircraft', 'attack helicopters'), '006f': ('enemy aircraft', 'ocean fighters'), '0070': ('enemy aircraft', 'ocean fighters (variant)'),
 '0089': ('enemy aircraft', 'finale fighters'), '008a': ('enemy aircraft', 'finale craft'), '008b': ('enemy aircraft', 'finale craft 2'),
 '008c': ('enemy aircraft', 'finale craft 3'), '008d': ('enemy aircraft', 'finale pods'), '008e': ('enemy aircraft', 'finale heavy craft'),
 '008f': ('enemy aircraft', 'finale drones'),
 # ground / naval
 '0056': ('ground enemies', 'gun turrets (coast/river)'), '0057': ('ground enemies', 'tanks (coast/river)'), '0058': ('ground enemies', 'bunkers'),
 '0059': ('ground enemies', 'rotating turrets'), '005d': ('ground enemies', 'armoured vehicles'), '005e': ('ground enemies', 'gun emplacements'),
 '0064': ('ground enemies', 'desert crates / emplacements'), '006b': ('ground enemies', 'desert turrets'),
 '006e': ('ground enemies', 'ocean gun boats / turrets'), '0071': ('naval', 'battleships'), '0072': ('naval', 'submarine / long ship'),
 '007c': ('naval', 'ship turrets'), '0045': ('ground enemies', 'city vehicles'), '0046': ('ground enemies', 'city cars / small vehicles'),
 '0080': ('ground structures', 'silos / storage (bases)'), '0081': ('ground structures', 'hangar doors (bases)'),
 '0082': ('ground structures', 'camouflaged roofs (bases)'), '0084': ('ground structures', 'runway lights / star field'),
 '0085': ('ground structures', 'camouflaged hangar (left)'), '0086': ('ground structures', 'camouflaged hangar (right)'),
 '009d': ('ground structures', 'runway markings (left)'), '009e': ('ground structures', 'runway markings (right)'),
 '009f': ('ground structures', 'runway structures'), '005f': ('ground structures', 'desert ground panels'),
 # city
 '0044': ('city / buildings', 'buildings (destructible; 49 columns, 275 tiles the largest)'), '0049': ('city / buildings', 'tower block tops'),
 '004a': ('city / buildings', 'building-mounted laser beam'), '0052': ('city / buildings', 'antenna / pylons'),
 '0053': ('city / buildings', 'building parts'), '0054': ('city / buildings', 'large building corners'), '0055': ('city / buildings', 'building edges'),
 # bosses
 '004d': ('bosses', 'city boss: green flying fortress (hull)'), '004e': ('bosses', 'city boss: fortress (damaged hull)'),
 '004f': ('bosses', 'city boss: fortress turrets'), '0050': ('bosses', 'city boss: fortress guns'), '0051': ('bosses', 'city boss: fortress parts (29 tables)'),
 '005b': ('bosses', 'river boss: dark mech fortress (core)'), '005c': ('bosses', 'river boss: mech fortress (body)'),
 '0062': ('bosses', 'desert boss: landship sand wake (left)'), '0063': ('bosses', 'desert boss: sand wake (right)'),
 '0066': ('bosses', 'desert boss: landship hull'), '0067': ('bosses', 'desert boss: gun towers'), '0068': ('bosses', 'desert boss: cannon'),
 '006a': ('bosses', 'desert boss: tracks'), '0076': ('bosses', 'ocean boss: battleship core'), '0077': ('bosses', 'ocean boss: turret pods'),
 '0078': ('bosses', 'ocean boss: rotors'), '0079': ('bosses', 'ocean boss: gun platform'), '007a': ('bosses', 'ocean boss: wake / beam'),
 '0083': ('bosses', 'base boss: golden sphere (opening shell)'), '0090': ('bosses', 'finale: orb drones (red)'), '0091': ('bosses', 'finale: orb drones'),
 '0092': ('bosses', 'finale: orb drones 2'), '0093': ('bosses', 'finale: orb drones 3'), '0094': ('bosses', 'finale: orbs 4'),
 '0095': ('bosses', 'finale: orbs 5'), '0096': ('bosses', 'finale: orbs 6'), '0097': ('bosses', 'finale: orb core'),
 '009a': ('bosses', 'finale: giant bomber'), '009c': ('bosses', 'finale: bomber shadow / silhouette'), '00a2': ('bosses', 'finale: transforming wings (22 tables)'),
 '00a3': ('bosses', 'final boss: sparks'), '00a4': ('bosses', 'final boss: core'), '00a5': ('bosses', 'final boss: armour plates'),
 '00a6': ('bosses', 'final boss: vents'), '00a7': ('bosses', 'final boss: guns'), '00a8': ('bosses', 'final boss: engines'),
 '00a9': ('bosses', 'final boss: left arm'), '00aa': ('bosses', 'final boss: right arm'), '00ab': ('bosses', 'final boss: central tower'),
 '00ac': ('bosses', 'final boss: beam'), '00ad': ('bosses', 'final boss: hull'),
}
H = {}
for f in glob.glob(C + '/lut_*.bin'): H[int(f[-7:-4])] = hashlib.md5(open(f, 'rb').read()).hexdigest()[:8]
sc = {}
for l in open(C + '/scenes.txt'): s = int(l.split()[0]); sc[s] = STAGE.get(H.get(s, ''), H.get(s, '?'))
CAT.update({   # corrections from the code (work/catalog/batches/desc_*.tsv, the type handlers)
 '000b': ('explosions', 'debris / smoke particles from the emitter type 0x0c (the most frequent sprite)'),
 '000e': ('player', 'overlay that follows player 1'),
 '000f': ('items', 'power-up item (shot power, bomb, full power; points when maxed)'),
 '0010': ('items', 'bonus pickup (10 points)'),
 '0018': ('player shots', 'weapon blast pieces (homing-missile / bomb blasts: the attract-demo "storm")'),
 '0020': ('player bomb', 'bomb strike: squadron jets (part)'), '0021': ('player bomb', 'bomb strike: squadron jets'),
 '002e': ('shadows', 'aircraft shadow (copies its parent, drawn on alternate frames)'),
 '002f': ('shadows', 'scroll-following shadow sprites'),
 '0033': ('enemy aircraft', 'turning aircraft (faces the player)'),
 '0034': ('ground enemies', 'ground tank / gun with rotating turret'),
 '0037': ('enemy aircraft', 'part of enemy type 0x38'), '0038': ('enemy aircraft', 'gunship (fires bullet patterns)'),
 '0052': ('bosses', 'city boss part (antenna)'), '0053': ('bosses', 'city boss part'), '0054': ('bosses', 'city boss part (corner)'),
 '0055': ('bosses', 'city boss part (edge)'), '005d': ('bosses', 'river boss part: armoured vehicle'),
 '0064': ('bosses', 'desert boss attachment (crate / emplacement)'), '0065': ('bosses', 'desert boss part'),
 '0069': ('bosses', 'desert boss launcher (damageable)'),
 '0084': ('bosses', 'base boss: main body (controls parts 0x85-0x88)'), '0085': ('bosses', 'base boss: hangar part (left)'),
 '0086': ('bosses', 'base boss: hangar part (right)'),
})
rows = []
for ty in sorted(O, key=lambda x: int(x, 16)):
    es = O[ty]; fr = sum(e['frames'] for e in es); defs = set(d for e in es for d in e['defs'] if d)
    st = collections.Counter()
    for e in es:
        for s in e['scenes']: st[sc.get(s, '?')] += e['frames']
    tiles = max((e.get('tiles', 0) for e in es), default=0); area = max((e.get('size', [0, 0])[0] * e.get('size', [0, 0])[1] for e in es), default=0)
    cat, desc = CAT.get(ty, ('unclassified', ''))
    rows.append((cat, ty, desc, len(es), len(defs), tiles, area, fr, ', '.join(k for k, _ in st.most_common(4))))
rows.sort(key=lambda r: (r[0], -r[7]))
with open('work/catalog/sprites/categories.tsv', 'w') as o:
    o.write('category\ttype\tdescription\ttables\tdefs\tmax_tiles\tmax_px\tobject_frames\tstages\n')
    for r in rows: o.write('\t'.join(str(x) for x in r) + '\n')
cs = collections.defaultdict(lambda: [0, 0, 0])
for r in rows: c = cs[r[0]]; c[0] += 1; c[1] += r[3]; c[2] += r[7]
for k, v in sorted(cs.items(), key=lambda x: -x[1][2]): print('%-20s types %3d tables %4d object-frames %8d' % (k, *v))
print('unclassified:', [r[1] for r in rows if r[0] == 'unclassified'])
