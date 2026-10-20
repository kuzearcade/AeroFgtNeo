#!/usr/bin/env python3
# Virtual 054c:0cda pad matching /media/fat/config/inputs/NEOGEO_input_054c_0cda_v3.map
# (A 0x132, B 0x131, C 0x133, D 0x130, Start 0x139, Select 0x138, then 0x134 0x135 0x137 0x136).
# aero_pad.py STEP...  step "dirs,buttons,seconds": dirs any of u d l r or '-', buttons '+'-joined
# names (a b c d start select coin x2 x3 x4) or '-'.
import fcntl, os, struct, sys, time
BTN = {'a': 0x132, 'b': 0x131, 'c': 0x133, 'd': 0x130, 'start': 0x139, 'select': 0x138,
       'coin': 0x134, 'x2': 0x135, 'x3': 0x137, 'x4': 0x136}
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY); fcntl.ioctl(fd, UI_SET_EVBIT, EV_ABS)
for c in BTN.values(): fcntl.ioctl(fd, UI_SET_KEYBIT, c)
for a in (0, 1): fcntl.ioctl(fd, UI_SET_ABSBIT, a)
amax = [0] * 64; amax[0] = amax[1] = 2
os.write(fd, struct.pack('80sHHHHI', b'MiSTer test pad', 3, 0x054c, 0x0cda, 1, 0)
         + struct.pack('64i', *amax) + b'\0' * (3 * 64 * 4))
fcntl.ioctl(fd, 0x5501); time.sleep(2.0)
def ev(t, c, v):
    n = time.time(); s = int(n); os.write(fd, struct.pack('llHHi', s, int((n - s) * 1e6), t, c, v))
held = set()
for step in sys.argv[1:]:
    d, b, sec = step.split(',')
    ev(EV_ABS, 0, 0 if 'l' in d else 2 if 'r' in d else 1)
    ev(EV_ABS, 1, 0 if 'u' in d else 2 if 'd' in d else 1)
    want = set() if b == '-' else set(b.split('+'))
    for n in held - want: ev(EV_KEY, BTN[n], 0)
    for n in want - held: ev(EV_KEY, BTN[n], 1)
    held = want; ev(EV_SYN, 0, 0); time.sleep(float(sec))
ev(EV_ABS, 0, 1); ev(EV_ABS, 1, 1)
for n in held: ev(EV_KEY, BTN[n], 0)
ev(EV_SYN, 0, 0); time.sleep(0.5); fcntl.ioctl(fd, 0x5502)
