until [ -s bench_dg3.txt ] && grep -q frames bench_dg3.txt; do sleep 30; done
sh benchlag.sh ~/AeroFgtNeo/work/out_cf4 cf4 > bench_cf4.txt 2>&1
