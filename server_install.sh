#!/bin/bash

###
### Field Day Pi Server Install
###
### Supports: Raspberry Pi OS Bookworm/Bullseye on Pi 3, 4, and 5
###

##
## REVISION: 20260626-0001
##

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/fieldday-install.log"

# ── Helpers ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"   | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"     | tee -a "$LOG_FILE"; exit 1; }

# ── 1. Require root ────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Run as root:  sudo bash $0"

# ── 2. Detect Pi model and OS release ──────────────────────────────────────────
PI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "Unknown Pi")
OS_CODENAME=$(lsb_release -cs 2>/dev/null || echo "unknown")
log "Hardware : $PI_MODEL"
log "OS       : Raspberry Pi OS ($OS_CODENAME)"

case "$OS_CODENAME" in
    trixie|bookworm|bullseye|buster) ;;
    *) warn "Untested OS release '$OS_CODENAME' — continuing anyway." ;;
esac

# Locate the boot firmware config (path changed in Bookworm)
if   [ -f /boot/firmware/config.txt ]; then BOOT_CONFIG="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ];          then BOOT_CONFIG="/boot/config.txt"
else err "Cannot locate boot config.txt"; fi
log "Boot cfg : $BOOT_CONFIG"

# ── 3. System update ───────────────────────────────────────────────────────────
log "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# ── 4. Disable Bluetooth ───────────────────────────────────────────────────────
log "Disabling Bluetooth..."
if ! grep -q "dtoverlay=disable-bt" "$BOOT_CONFIG"; then
    printf '\n# Disable Bluetooth (FieldDay Pi Server)\ndtoverlay=disable-bt\n' >> "$BOOT_CONFIG"
fi
systemctl disable --now hciuart.service  2>/dev/null || true
systemctl disable --now bluetooth.service 2>/dev/null || true

# ── 5. Install required packages ───────────────────────────────────────────────
log "Installing packages..."
apt-get install -y \
    hostapd dnsmasq \
    nginx \
    samba samba-common-bin \
    python3 python3-flask \
    iw wireless-tools \
    git

# ── 6. Detect USB WiFi adapter ─────────────────────────────────────────────────
log "Detecting USB WiFi adapter..."
AP_IFACE=""
for iface in $(ls /sys/class/net/); do
    [[ "$iface" != wlan* ]] && continue
    dev_path=$(readlink -f "/sys/class/net/$iface/device" 2>/dev/null || true)
    # USB devices have 'usb' in their sysfs path
    if echo "$dev_path" | grep -qi "usb"; then
        AP_IFACE="$iface"
        log "USB WiFi  : $AP_IFACE"
        break
    fi
done

if [ -z "$AP_IFACE" ]; then
    warn "No USB WiFi adapter detected. Defaulting to wlan1."
    warn "Connect a USB WiFi adapter before the AP will function."
    AP_IFACE="wlan1"
fi

# ── 7. Write AP settings (single source of truth for web UI) ───────────────────
log "Writing AP settings..."
FDCONF_DIR="/etc/fieldday"
mkdir -p "$FDCONF_DIR"

cat > "$FDCONF_DIR/ap_settings.json" << SETTINGS
{
    "ssid": "FieldDay",
    "passphrase": "fieldday1234",
    "channel": 6,
    "hw_mode": "g",
    "ap_interface": "$AP_IFACE",
    "ap_ip": "192.168.73.1",
    "dhcp_start": "192.168.73.10",
    "dhcp_end": "192.168.73.200",
    "dhcp_mask": "255.255.255.0",
    "dhcp_lease": "24h",
    "domain": "fieldday.local"
}
SETTINGS

# ── 8. Tell NetworkManager to ignore the AP interface (Bookworm) ───────────────
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    log "Configuring NetworkManager to ignore $AP_IFACE..."
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/99-fieldday-unmanaged.conf << NMEOF
[keyfile]
unmanaged-devices=interface-name:$AP_IFACE
NMEOF
    nmcli general reload 2>/dev/null || true
fi

# ── 9. Generate hostapd config ─────────────────────────────────────────────────
log "Configuring hostapd (WiFi Access Point)..."
cat > /etc/hostapd/hostapd.conf << HAEOF
interface=$AP_IFACE
driver=nl80211
ssid=FieldDay
hw_mode=g
channel=6
ieee80211n=1
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=fieldday1234
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
country_code=US
HAEOF

# Point hostapd to our config
if [ -f /etc/default/hostapd ]; then
    sed -i 's|#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
fi

systemctl unmask hostapd
systemctl enable hostapd

# ── 10. Generate dnsmasq config ────────────────────────────────────────────────
log "Configuring dnsmasq (DHCP + DNS)..."
[ -f /etc/dnsmasq.conf ] && mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
cat > /etc/dnsmasq.conf << DMEOF
# FieldDay Pi Server - dnsmasq
interface=$AP_IFACE
bind-interfaces
dhcp-range=192.168.73.10,192.168.73.200,255.255.255.0,24h
domain=fieldday.local
local=/fieldday.local/
address=/fieldday.local/192.168.73.1
dhcp-option=6,192.168.73.1
DMEOF

systemctl enable dnsmasq

# ── 11. Install AP interface setup service ─────────────────────────────────────
log "Installing fieldday-ap-ifup service..."
install -m 0755 "$SCRIPT_DIR/scripts/fieldday-ap-ifup.sh" /usr/local/sbin/fieldday-ap-ifup.sh
install -m 0644 "$SCRIPT_DIR/systemd/fieldday-ap-ifup.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable fieldday-ap-ifup

# ── 12. Create fieldday user ───────────────────────────────────────────────────
log "Creating 'fieldday' user..."
if ! id fieldday &>/dev/null; then
    adduser --disabled-password --gecos "Field Day" fieldday
fi
echo "fieldday:fd2021" | chpasswd

# ── 13. Configure Samba ────────────────────────────────────────────────────────
log "Configuring Samba..."
if ! grep -q "\[fieldday\]" /etc/samba/smb.conf; then
    cat >> /etc/samba/smb.conf << 'SMBEOF'

### FieldDay Pi Server ###
[fieldday]
    path = /home/fieldday
    valid users = fieldday
    read only = no
    browsable = yes
    create mask = 0775
    directory mask = 0775

[pi]
    path = /home/pi
    valid users = pi
    read only = no
    browsable = yes
    create mask = 0775
    directory mask = 0775
SMBEOF
fi

printf 'fd2021\nfd2021\n'    | smbpasswd -a fieldday -s 2>/dev/null || true
printf 'raspberry\nraspberry\n' | smbpasswd -a pi      -s 2>/dev/null || true
systemctl restart smbd

# ── 14. Configure nginx ────────────────────────────────────────────────────────
log "Configuring nginx..."
cp -r "$SCRIPT_DIR/sample-web-site/." /var/www/html/
systemctl enable nginx
systemctl restart nginx

# ── 15. Configure static Ethernet IP (eth0 fallback) ──────────────────────────
log "Configuring eth0 static IP fallback..."
if [ -f /etc/dhcpcd.conf ] && ! grep -q "FieldDay Pi Server" /etc/dhcpcd.conf; then
    # Bullseye and earlier: dhcpcd profiles
    cat >> /etc/dhcpcd.conf << 'DHEOF'

### FieldDay Pi Server ###
profile fieldday_net
static ip_address=192.168.73.100/24
static routers=192.168.73.1
static domain_name_servers=192.168.73.1

interface eth0
fallback fieldday_net
DHEOF
elif systemctl is-active --quiet NetworkManager 2>/dev/null; then
    # Bookworm: use nmcli for wired fallback
    if ! nmcli connection show "FieldDay-eth0" &>/dev/null; then
        nmcli connection add \
            type ethernet \
            con-name "FieldDay-eth0" \
            ifname eth0 \
            ipv4.method manual \
            ipv4.addresses "192.168.73.100/24" \
            ipv4.gateway "192.168.73.1" \
            ipv4.dns "192.168.73.1" \
            connection.autoconnect-priority 50 2>/dev/null || true
    fi
fi

# ── 16. Install Flask web admin ────────────────────────────────────────────────
log "Installing FieldDay web admin (port 8080)..."
ADMIN_DIR="/opt/fieldday-admin"
mkdir -p "$ADMIN_DIR"
cp -r "$SCRIPT_DIR/web-admin/." "$ADMIN_DIR/"

install -m 0644 "$SCRIPT_DIR/systemd/fieldday-admin.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable fieldday-admin
systemctl restart fieldday-admin

# ── 17. Done ───────────────────────────────────────────────────────────────────
log ""
log "╔══════════════════════════════════════════════════════════╗"
log "║          FieldDay Pi Server — Install Complete           ║"
log "╠══════════════════════════════════════════════════════════╣"
log "║  Pi Model    : $PI_MODEL"
log "║  OS          : $OS_CODENAME"
log "║  AP Interface: $AP_IFACE  (USB WiFi required)"
log "║  AP SSID     : FieldDay"
log "║  AP IP       : 192.168.73.1"
log "║  Eth0 IP     : 192.168.73.100 (static fallback)"
log "║  Domain      : fieldday.local"
log "║  Web Admin   : http://192.168.73.1:8080/"
log "║  Field Day   : http://192.168.73.100/"
log "║  Bluetooth   : disabled (takes effect after reboot)"
log "╠══════════════════════════════════════════════════════════╣"
log "║  Default AP passphrase : fieldday1234                    ║"
log "║  Samba fieldday user   : fd2021                          ║"
log "╚══════════════════════════════════════════════════════════╝"
log ""
read -rp "Reboot now to activate Bluetooth disable + AP? [y/N] " REBOOT_NOW
[[ "$REBOOT_NOW" =~ ^[Yy]$ ]] && reboot
