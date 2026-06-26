#!/bin/bash
# Brings up the AP WiFi interface with the static IP from fdnetwork.conf.
# Runs as a systemd oneshot before hostapd and dnsmasq start.

CONF="/etc/fieldday/fdnetwork.conf"

if [ ! -f "$CONF" ]; then
    echo "ERROR: $CONF not found" >&2
    exit 1
fi

source "$CONF"

echo "Bringing up AP interface $AP_IFACE with ${AP_IP}/${AP_PREFIX}..."
ip link set "$AP_IFACE" up
ip addr flush dev "$AP_IFACE" 2>/dev/null || true
ip addr add "${AP_IP}/${AP_PREFIX}" dev "$AP_IFACE"
