until [ -s bench_cf2.txt ] && grep -q frames bench_cf2.txt; do sleep 30; done
sh benchlag.sh ~/AeroFgtNeo/work/out_cf3 cf3 > bench_cf3.txt 2>&1
sh benchlag.sh ~/AeroFgtNeo/work/out_dg2 dg2 > bench_dg2.txt 2>&1
sh benchlag.sh ~/AeroFgtNeo/work/out_dg3 dg3 > bench_dg3.txt 2>&1
