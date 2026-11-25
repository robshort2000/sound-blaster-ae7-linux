#!/usr/bin/env bash
# Install analog-guard helpers + patched modules. Does not unbind the AE-7.
set -euo pipefail
FIX=/home/rob/ae7-fix
install -d /usr/local/lib/ae7 /usr/local/sbin
install -m 755 "$FIX/stop-corb-dma.py" /usr/local/lib/ae7/stop-corb-dma.py
install -m 755 "$FIX/ae7-analog-guard.sh" /usr/local/sbin/ae7-analog-guard.sh
install -m 755 "$FIX/ae7-cold-bind-boot.sh" /usr/local/sbin/ae7-cold-bind.sh
install -m 644 "$FIX/ae7-analog-guard.service" /etc/systemd/system/ae7-analog-guard.service
install -m 644 "$FIX/ae7-cold-bind.service" /etc/systemd/system/ae7-cold-bind.service
install -m 644 "$FIX/ae7-cold-bind.timer" /etc/systemd/system/ae7-cold-bind.timer
install -m 644 "$FIX/bar2-gpio-hp.py" /usr/local/lib/ae7/bar2-gpio-hp.py
"$FIX/ae7-install-modules.sh"
systemctl daemon-reload
# The oneshot must not be wanted by multi-user.target (that holds the login
# screen). The guard is pulled in by the oneshot, and must not be wanted by
# multi-user either, or a restart of the guard can order itself before boot.
systemctl disable ae7-cold-bind.service ae7-analog-guard.service
systemctl enable ae7-cold-bind.timer
echo "timer $(systemctl is-enabled ae7-cold-bind.timer) $(systemctl is-active ae7-cold-bind.timer)"
