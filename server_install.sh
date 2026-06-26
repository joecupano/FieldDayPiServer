#!/bin/bash

###
### Field Day Pi Server Install
###
### Supports: Raspberry Pi OS Trixie/Bookworm/Bullseye on Pi 3, 4, and 5
###
### Edit fdnetwork.conf in this directory before running.
###

##
## REVISION: 20260626-0003
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

# ── 2. Load network configuration ─────────────────────────────────────────────
CONF="$SCRIPT_DIR/fdnetwork.conf"
[ -f "$CONF" ] || err "fdnetwork.conf not found in $SCRIPT_DIR"
source "$CONF"
log "Config   : $CONF"

# ── 3. Detect Pi model and OS release ──────────────────────────────────────────
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

# ── 4. System update ───────────────────────────────────────────────────────────
log "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# ── 5. Disable Bluetooth ───────────────────────────────────────────────────────
log "Disabling Bluetooth..."
if ! grep -q "dtoverlay=disable-bt" "$BOOT_CONFIG"; then
    printf '\n# Disable Bluetooth (FieldDay Pi Server)\ndtoverlay=disable-bt\n' >> "$BOOT_CONFIG"
fi
systemctl disable --now hciuart.service   2>/dev/null || true
systemctl disable --now bluetooth.service 2>/dev/null || true

# ── 6. Install required packages ───────────────────────────────────────────────
log "Installing packages..."
apt-get install -y \
    hostapd dnsmasq \
    nginx \
    samba samba-common-bin \
    iw wireless-tools \
    git

# ── 7. Detect USB WiFi adapter ─────────────────────────────────────────────────
log "Detecting USB WiFi adapter..."
AP_IFACE=""
for iface in $(ls /sys/class/net/); do
    [[ "$iface" != wlan* ]] && continue
    dev_path=$(readlink -f "/sys/class/net/$iface/device" 2>/dev/null || true)
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

# ── 8. Install runtime network config ─────────────────────────────────────────
log "Installing network config to /etc/fieldday/..."
mkdir -p /etc/fieldday
cp "$CONF" /etc/fieldday/fdnetwork.conf
echo "AP_IFACE=\"$AP_IFACE\"" >> /etc/fieldday/fdnetwork.conf

# ── 9. Tell NetworkManager to ignore the AP interface (Bookworm/Trixie) ────────
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    log "Configuring NetworkManager to ignore $AP_IFACE..."
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/99-fieldday-unmanaged.conf << NMEOF
[keyfile]
unmanaged-devices=interface-name:$AP_IFACE
NMEOF
    nmcli general reload 2>/dev/null || true
fi

# ── 10. Configure hostapd ──────────────────────────────────────────────────────
log "Configuring hostapd (SSID: $AP_SSID, channel: $AP_CHANNEL)..."
cat > /etc/hostapd/hostapd.conf << HAEOF
interface=$AP_IFACE
driver=nl80211
ssid=$AP_SSID
hw_mode=g
channel=$AP_CHANNEL
ieee80211n=1
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$AP_PASSPHRASE
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
country_code=US
HAEOF

if [ -f /etc/default/hostapd ]; then
    sed -i 's|#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
fi

systemctl unmask hostapd
systemctl enable hostapd

# ── 11. Configure dnsmasq ──────────────────────────────────────────────────────
log "Configuring dnsmasq (DHCP: $DHCP_START – $DHCP_END, domain: $DOMAIN)..."
[ -f /etc/dnsmasq.conf ] && mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
cat > /etc/dnsmasq.conf << DMEOF
# FieldDay Pi Server - dnsmasq
interface=$AP_IFACE
bind-interfaces
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,$DHCP_LEASE
domain=$DOMAIN
local=/$DOMAIN/
address=/$DOMAIN/$AP_IP
dhcp-option=6,$AP_IP
DMEOF

systemctl enable dnsmasq

# ── 12. Install AP interface setup service ─────────────────────────────────────
log "Installing fieldday-ap-ifup service..."
install -m 0755 "$SCRIPT_DIR/scripts/fieldday-ap-ifup.sh" /usr/local/sbin/fieldday-ap-ifup.sh
install -m 0644 "$SCRIPT_DIR/systemd/fieldday-ap-ifup.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable fieldday-ap-ifup

# ── 13. Configure nginx ────────────────────────────────────────────────────────
log "Configuring nginx..."
cp -r "$SCRIPT_DIR/sample-web-site/." /var/www/html/
systemctl enable nginx
systemctl restart nginx

# ── 14. Configure static Ethernet IP (eth0 fallback) ──────────────────────────
log "Configuring eth0 static IP fallback ($AP_IP prefix $AP_PREFIX)..."
ETH_IP="${AP_IP%.*}.100"   # derive .100 from the AP IP subnet

if [ -f /etc/dhcpcd.conf ] && ! grep -q "FieldDay Pi Server" /etc/dhcpcd.conf; then
    cat >> /etc/dhcpcd.conf << DHEOF

### FieldDay Pi Server ###
profile fieldday_net
static ip_address=$ETH_IP/$AP_PREFIX
static routers=$AP_IP
static domain_name_servers=$AP_IP

interface eth0
fallback fieldday_net
DHEOF
elif systemctl is-active --quiet NetworkManager 2>/dev/null; then
    if ! nmcli connection show "FieldDay-eth0" &>/dev/null; then
        nmcli connection add \
            type ethernet \
            con-name "FieldDay-eth0" \
            ifname eth0 \
            ipv4.method manual \
            ipv4.addresses "$ETH_IP/$AP_PREFIX" \
            ipv4.gateway "$AP_IP" \
            ipv4.dns "$AP_IP" \
            connection.autoconnect-priority 50 2>/dev/null || true
    fi
fi

# ── 15. Configure Samba ────────────────────────────────────────────────────────
log "Configuring Samba (share: $SHARE_NAME -> $SHARE_DIR, user: $SMB_USER)..."

mkdir -p "$SHARE_DIR"
chown pi:pi "$SHARE_DIR"
chmod 0775 "$SHARE_DIR"

if ! id "$SMB_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -M "$SMB_USER"
fi

if ! grep -q "\[$SHARE_NAME\]" /etc/samba/smb.conf; then
    cat >> /etc/samba/smb.conf << SMBEOF

### FieldDay Pi Server ###
[$SHARE_NAME]
    path = $SHARE_DIR
    valid users = $SMB_USER
    force user = pi
    read only = no
    browsable = yes
    create mask = 0775
    directory mask = 0775
SMBEOF
fi

printf '%s\n%s\n' "$SMB_PASS" "$SMB_PASS" | smbpasswd -a "$SMB_USER" -s
systemctl enable --now smbd

# ── 16. Done ───────────────────────────────────────────────────────────────────
log ""
log "╔══════════════════════════════════════════════════════════╗"
log "║          FieldDay Pi Server — Install Complete           ║"
log "╠══════════════════════════════════════════════════════════╣"
log "║  Pi Model  : $PI_MODEL"
log "║  OS        : $OS_CODENAME"
log "║  AP SSID   : $AP_SSID  (passphrase: $AP_PASSPHRASE)"
log "║  AP IP     : $AP_IP  (interface: $AP_IFACE)"
log "║  Eth0 IP   : $ETH_IP (static fallback)"
log "║  Domain    : $DOMAIN"
log "║  Web       : http://$ETH_IP/"
log "║  Samba     : \\\\$ETH_IP\\$SHARE_NAME  (user: $SMB_USER)"
log "║  Bluetooth : disabled (takes effect after reboot)"
log "╚══════════════════════════════════════════════════════════╝"
log ""
read -rp "Reboot now to activate Bluetooth disable + AP? [y/N] " REBOOT_NOW
[[ "$REBOOT_NOW" =~ ^[Yy]$ ]] && reboot
