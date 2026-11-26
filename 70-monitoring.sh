#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; require_root
ILS_CT="ils"
# Prometheus/Grafana live on desktop; this script only installs and wires
# node_exporter + the textfile directory the Forth probes write into.
do_ "node_exporter installed" lxc exec "$ILS_CT" -- systemctl is-active prometheus-node-exporter
TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
do_ "textfile dir present" lxc exec "$ILS_CT" -- test -d "$TEXTFILE_DIR"
if [[ "$MODE" == "apply" ]]; then
    lxc exec "$ILS_CT" -- apt-get install -y prometheus-node-exporter
    lxc exec "$ILS_CT" -- mkdir -p "$TEXTFILE_DIR"
    lxc exec "$ILS_CT" -- bash -c "printf '%s\\n' '[Service]' 'ExecStart=' 'ExecStart=/usr/bin/prometheus-node-exporter --collector.textfile.directory=$TEXTFILE_DIR' > /etc/systemd/system/prometheus-node-exporter.service.d/textfile.conf" || true
    lxc exec "$ILS_CT" -- systemctl daemon-reload
    lxc exec "$ILS_CT" -- systemctl restart prometheus-node-exporter
fi
# Probe cadence: minute interval during pilot; TODO: switch to hourly at full
# scale per capacity model. Watchword output goes to the textfile dir.
do_ "probe cron present" lxc exec "$ILS_CT" -- grep -q "watch.4th" /etc/cron.d/ils-probes
if [[ "$MODE" == "apply" ]]; then
    printf '%s\n' "*/1 * * * * ils /opt/meshgraph-ils/ils/probes/watch.4th > $TEXTFILE_DIR/ils.probes 2>/dev/null" \
        | lxc exec "$ILS_CT" -- tee /etc/cron.d/ils-probes >/dev/null
fi
finish
