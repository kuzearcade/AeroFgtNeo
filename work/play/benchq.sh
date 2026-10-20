#!/bin/sh
# benchq.sh <name>...: bench9 one build after another
cd $HOME/AeroFgtNeo/work/play
for b in "$@"; do sh bench9.sh ../out_$b $b > bench_$b.txt 2>&1; done
