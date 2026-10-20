until [ -s bench_cf6.txt ] && grep -q frames bench_cf6.txt; do sleep 30; done
sh benchlag.sh ~/AeroFgtNeo/work/out_cf6 cf6 "16 17 18 19 20 21 22 23 24" > bench_cf6b.txt 2>&1
