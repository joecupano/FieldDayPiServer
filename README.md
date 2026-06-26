# Field Day Pi Server

A self-contained Field Day event server running on a Raspberry Pi. Provides a WiFi access point, DHCP, local DNS, a web server for event info, and a Samba file share for logging software.

## Services

| Service | Details |
|---------|---------|
| WiFi Access Point | USB WiFi adapter required — defaults to SSID **FieldDay**, 192.168.73.0/24 |
| DHCP + DNS | dnsmasq — default domain **fieldday.local** |
| Web Server | nginx on port 80 — static event info and software downloads |
| Windows File Server | Samba — default share **fieldday**, user **fieldday** |

## Hardware

- Raspberry Pi 3, 4, or 5
- 16 GB microSD Class 10 or faster
- **USB WiFi adapter** — required for the access point; onboard WiFi is not used
- Ethernet for initial setup (optional once the AP is running)

## Software

**Raspberry Pi OS Trixie or Bookworm** (64-bit Lite recommended). Also works on Bullseye.  
Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to write the image.

## Setup

### 1. Initial Pi configuration

After first boot, run `raspi-config` and make these changes:

- Change the `pi` user password
- Set hostname (e.g. `fieldday`)
- Boot to text console (no auto-login)
- Enable SSH
- GPU memory → 16 MB
- Locale and timezone → your region
- Predictable Network Interface Names → **No**
- Finish → reboot

### 2. Clone the repo

```bash
sudo apt-get -y install git
git clone https://github.com/joecupano/FieldDayPiServer.git
cd FieldDayPiServer
```

### 3. Edit fdnetwork.conf

Open `fdnetwork.conf` and adjust any settings before running the install script.  
**All network and Samba configuration lives here** — no prompts during install.

```bash
nano fdnetwork.conf
```

### 4. Run the install script

```bash
sudo bash server_install.sh
```

Reboot when prompted to activate the WiFi AP and Bluetooth disable.

---

## fdnetwork.conf reference

```bash
# WiFi Access Point
AP_SSID="FieldDay"          # Network name clients see
AP_PASSPHRASE="fieldday1234" # WPA2 passphrase (8–63 chars)
AP_CHANNEL=6                # WiFi channel — 1, 6, or 11 recommended
AP_IP="192.168.73.1"        # Pi's IP on the wireless network (gateway)
AP_PREFIX=24                # Subnet prefix length
DHCP_START="192.168.73.10"  # First IP issued to clients
DHCP_END="192.168.73.200"   # Last IP issued to clients
DHCP_LEASE="24h"            # Lease duration
DOMAIN="fieldday.local"     # Local DNS domain

# Samba File Sharing
SHARE_NAME="fieldday"       # Windows share name  \\<ip>\fieldday
SHARE_DIR="/home/pi/fieldday" # Directory on the Pi to share
SMB_USER="fieldday"         # Username for Windows clients
SMB_PASS="fieldday"         # Password for Windows clients
```

The install script copies `fdnetwork.conf` to `/etc/fieldday/fdnetwork.conf` and appends the detected USB WiFi interface name (`AP_IFACE`). Edit the repo copy and re-run the installer to change settings.

---

## Default access after install

| Resource | Address |
|----------|---------|
| WiFi SSID | FieldDay (passphrase: fieldday1234) |
| Pi AP IP | 192.168.73.1 |
| Pi Ethernet IP | 192.168.73.100 (static fallback) |
| Event website | http://192.168.73.100/ |
| Samba share | \\192.168.73.100\fieldday |
| Samba login | fieldday / fieldday |
| Local domain | fieldday.local |

## File structure

```
FieldDayPiServer/
├── fdnetwork.conf             Edit before install — all network settings
├── server_install.sh          Install script
├── sample-web-site/           Static HTML copied to /var/www/html/
├── scripts/
│   └── fieldday-ap-ifup.sh   Brings up the AP interface at boot
└── systemd/
    └── fieldday-ap-ifup.service
```

## Notes

- **Bluetooth** is disabled via `dtoverlay=disable-bt` in the boot config. A reboot is required.
- **USB WiFi only** — the install script detects the first USB wireless interface (typically `wlan1`). Onboard `wlan0` is never used for the AP.
- **File ownership** — the Samba share uses `force user = pi`, so all files created through the share are owned by the `pi` account regardless of which SMB user connects.
- To update the event website, replace files in `/var/www/html/`. See `sample-web-site/` for examples.
