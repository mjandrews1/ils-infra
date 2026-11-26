#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; require_root
ILS_CT="ils"
execute_in_ils() { lxc exec "$ILS_CT" -- bash -c "$*"; }
do_ "tarantool repo registered" lxc exec "$ILS_CT" -- test -f /etc/apt/sources.list.d/tarantool.list
if [[ "$MODE" == "apply" ]] && ! lxc exec ils -- test -f /etc/apt/sources.list.d/tarantool.list 2>/dev/null; then
    execute_in_ils "curl -L https://tarantool.io/installer.sh | sudo bash" # official installer
    execute_in_ils "apt-get install -y tarantool"
fi
do_ "tarantool installed" lxc exec "$ILS_CT" -- tarantool --version
do_ "ils system user exists" lxc exec "$ILS_CT" -- id -u ils
[[ "$MODE" == "apply" ]] && lxc exec "$ILS_CT" -- useradd --system --home /var/lib/tarantool --shell /usr/sbin/nologin ils 2>/dev/null || true
# Instance config lives under /etc/tarantool/instances_enabled/ils.lua, managed
# by the instance tooling (TODO-verify: tt vs tarantoolctl names on 3.x) =
# the unit is the stock tarantool@<instance> template, enabled below.
if [[ "$MODE" == "apply" ]]; then
    mkdir -p /tmp/instances_enabled
    cat > /tmp/instances_enabled/ils.lua << 'EOF'
-- meshgraph ils instance skeleton (real spaces live in meshgraph-ils repo)
box.cfg {
  listen = "127.0.0.1:3301", -- tailnet peers reach via socat/caddy, not direct
  memtx_memory = 18 * 1024^3, -- capacity model: title-only citation space headroom
  wal_mode = "write",
  log_level = 5,
  log = "/var/log/tarantool/ils.log",
}
EOF
    lxc file push /tmp/instances_enabled/ils.lua "$ILS_CT/etc/tarantool/instances_enabled/ils.lua"
fi
do_ "systemd unit 'tarantool@ils'" lxc exec "$ILS_CT" -- systemctl is-enabled "tarantool@ils"
[[ "$MODE" == "apply" ]] && lxc exec "$ILS_CT" -- systemctl enable --now "tarantool@ils" 2>/dev/null || true
finish
