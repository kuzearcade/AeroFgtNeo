#!/bin/sh
# dis.sh <bin> <addr> <count>  - disassemble big-endian 68K binary at addr
f=$(mktemp); tail -c +$(($2+1)) "$1" | head -c $(($3*10)) > $f
~/mame/unidasm $f -arch m68000 -basepc $(printf %x $(($2))) 2>/dev/null; rm -f $f
