#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; require_root
YDB_INSTALLER="ydbinstall.sh" # TODO-verify: fetch current from docs.yottadb.com
YDB_VER="r2.04"               # TODO-verify latest r2.x on provisioning day
ILS_CT="ils"; YDBDIR="/opt/yottadb"
execute_in_ils() { lxc exec "$ILS_CT" -- bash -c "$*"; }
do_ "yottadb installed" bash -c "lxc exec ils -- test -x $YDBDIR/ydb"
if [[ "$MODE" == "apply" ]] && ! lxc exec ils -- test -x "$YDBDIR/ydb" 2>/dev/null; then
    lxc exec "$ILS_CT" -- bash -c "curl -fsSLO https://gitlab.com/YottaDB/DB/YDB/-/raw/master/$YDB_INSTALLER"
    lxc exec "$ILS_CT" -- bash -c "sudo bash ./$YDB_INSTALLER --utf8 --verbose $YDB_VER" \
    | tee /tmp/ydbinstall.log # TODO-verify installer flags
fi
# --- region layout: one region per global family, per the schema annex ---
cat > /tmp/region_layout.gde << 'EOF'
! /tmp/region_layout.gde - GDE script: schema-per-region layout
change -segment DEFAULT -file="$ydb_dir/ydb.dat" -access_method=BG -block=4096
change -region DEFAULT -record=4080 -key=255 -journal=enable -nnull_subscripts=false
add -name %ydb* -region=DEFAULT
add -region ENTITY -dyn_segment=ENTITY -record=4080 -key=1019 -journal=enable
add -segment ENTITY -file="$ydb_dir/ols/entity.dat" -block=16384
add -name ^entity -region=ENTITY
add -region MESH -dyn_segment=MESH -record=4080 -key=1019 -journal=enable
add -segment MESH -file="$ydb_dir/ols/mesh.dat" -block=16384
add -name ^mesh -region=MESH
add -region LINK -dyn_segment=LINK -record=4080 -key=1019 -journal=enable
add -segment LINK -file="$ydb_dir/ols/link.dat" -block=16384
add -name ^link* -region=LINK ! ^link, ^linkIdx, ^meshEdge
add -region ZCHG -dyn_segment=ZCHG -record=1019 -key=1019 -journal=enable
add -segment ZCHG -file="$ydb_dir/ols/zchg.dat" -block=4096
add -name ^zchg* -region=ZCHG ! ^zchg AND ^zchgSeq: the change log and its
! sequence counter are ONE unit for the sync daemon and the crash-recovery
! drill - same region, same journal. (Cross-layer fix, Nov 27 2026.)
add -region CIRC -dyn_segment=CIRC -record=4080 -key=1019 -journal=enable
add -segment CIRC -file="$ydb_dir/ols/circ.dat" -block=8192
add -name ^loan* -region=CIRC ! ^loan, ^loanSeq - written by CIRC.m
add -name ^item* -region=CIRC ! item status/loan pointers
add -name ^patron* -region=CIRC ! PII boundary: patron data lives ONLY here
add -region ERM -dyn_segment=ERM -record=4080 -key=1019 -journal=enable
add -segment ERM -file="$ydb_dir/ols/erm.dat" -block=8192
add -name ^erm -region=ERM
add -name ^isn -region=ERM ! ^isn (issn-issnl) rides ERM/serial identity
show -name
exit
EOF
if [[ "$MODE" == "apply" ]]; then
    lxc file push /tmp/region_layout.gde "$ILS_CT/tmp/"
    execute_in_ils 'export ydb_dir=$ydb_dir && $ydb_dist/mumps -run GDE < /tmp/region_layout.gde' # TODO-verify GDE invocation
    execute_in_ils 'cd $ydb_dir && $ydb_dist/mupip create -region=*' # creates .dat files
    execute_in_ils 'find $ydb_dir -name "*.dat" -exec $ydb_dist/mupip set -journal=enable,nobefore,file={}.mjl {} \;' # TODO-verify filter syntax
fi
do_ "entity region exists" lxc exec "$ILS_CT" -- ls -l /opt/yottadb/ols/entity.dat
do_ "journaling on all regions" lxc exec "$ILS_CT" -- ls /opt/yottadb/ols/*.mjl
finish
