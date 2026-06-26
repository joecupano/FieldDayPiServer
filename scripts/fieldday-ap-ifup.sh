#!/bin/bash
# Brings up the AP WiFi interface with the static IP from ap_settings.json.
# Runs as a systemd oneshot before hostapd and dnsmasq start.

SETTINGS="/etc/fieldday/ap_settings.json"

if [ ! -f "$SETTINGS" ]; then
    echo "ERROR: $SETTINGS not found" >&2
    exit 1
fi

AP_IFACE=$(python3 -c "import json,sys; d=json.load(open('$SETTINGS')); print(d['ap_interface'])")
AP_IP=$(python3    -c "import json,sys; d=json.load(open('$SETTINGS')); print(d['ap_ip'])")
MASK=$(python3     -c "import json,sys; d=json.load(open('$SETTINGS')); print(d['dhcp_mask'])")

# Convert dotted netmask to prefix length
mask_to_prefix() {
    local mask="$1"
    local bits=0
    IFS='.' read -ra octets <<< "$mask"
    for o in "${octets[@]}"; do
        while (( o > 0 )); do
            (( bits += o & 1 )) || true
            (( o >>= 1 )) || true
        done
    done
    echo "$bits"
}

PREFIX=$(mask_to_prefix "$MASK")

echo "Bringing up AP interface $AP_IFACE with ${AP_IP}/${PREFIX}..."
ip link set "$AP_IFACE" up
ip addr flush dev "$AP_IFACE" 2>/dev/null || true
ip addr add "${AP_IP}/${PREFIX}" dev "$AP_IFACE"
