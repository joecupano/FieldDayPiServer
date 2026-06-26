# Field Day Pi Server

A self-contained Field Day event server running on a Raspberry Pi.

## Services provided

| Service | Details |
|---------|---------|
| WiFi Access Point | USB WiFi adapter required — SSID **FieldDay**, 192.168.73.0/24 |
| DHCP + DNS | dnsmasq — domain **fieldday.local** |
| Web Admin UI | AP and Samba configuration at `http://192.168.73.1:8080/` |
| Web Server | nginx on port 80 — event info and software downloads |
| Windows File Server | Samba — disabled by default, enabled via Web Admin |

## Hardware requirements

- Raspberry Pi 3, 4, or 5
- 16 GB microSD Class 10 or faster
- **USB WiFi adapter** (required for the Access Point — onboard WiFi is not used)
- Ethernet cable for initial setup (optional after AP is running)

## Software requirements

- **Raspberry Pi OS Trixie or Bookworm** (64-bit Lite recommended) — also works on Bullseye
- Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to write the image

## Initial Pi setup

After flashing the SD card and booting:

```bash
sudo raspi-config
```

Within raspi-config, make these changes:

- Change the `pi` user password
- Set hostname (e.g. `fieldday-pi`)
- Boot to text console (no auto-login)
- Enable SSH
- Set GPU memory to 16 MB
- Set locale/timezone to your region
- Set Predictable Network Interface Names → **No**
- Finish → reboot

## Installation

```bash
sudo apt-get -y install git
git clone https://github.com/joecupano/FieldDayPiServer.git
cd FieldDayPiServer
sudo bash server_install.sh
```

The script detects the OS release and Pi model automatically.  
When prompted, reboot to activate Bluetooth disable and the WiFi AP.

## Default configuration

| Setting | Default |
|---------|---------|
| AP SSID | `FieldDay` |
| AP Passphrase | `fieldday1234` |
| AP Interface | first USB WiFi detected (e.g. `wlan1`) |
| AP IP / Gateway | `192.168.73.1` |
| DHCP Range | `192.168.73.10` – `192.168.73.200` |
| Domain | `fieldday.local` |
| eth0 IP (fallback) | `192.168.73.100` |
| Samba `fieldday` user | `fd2021` |
| Bluetooth | **disabled** |

## Web Admin UI

Access at `http://192.168.73.1:8080/` (or `http://fieldday.local:8080/`) from any device connected to the FieldDay WiFi.

The admin lets you change:

- SSID and passphrase
- WiFi channel (1–11; 1, 6, 11 recommended)
- AP IP address
- DHCP range
- Local domain name

Changes are written to `/etc/hostapd/hostapd.conf` and `/etc/dnsmasq.conf` and applied immediately — connected clients will briefly disconnect.

## Wireless AP notes

- **Only a USB WiFi adapter is used for the AP.** The install script detects USB WiFi automatically (wlan1 or higher). Onboard wlan0 is never used for the AP.
- On Bookworm, NetworkManager is configured to leave the AP interface unmanaged.
- The AP interface is brought up by the `fieldday-ap-ifup` systemd service before hostapd starts.

## Bluetooth

Bluetooth is disabled via `dtoverlay=disable-bt` in the boot config and by masking the `hciuart` and `bluetooth` systemd services. A reboot is required to take effect.

## File structure

```
FieldDayPiServer/
├── server_install.sh          Main install script
├── sample-web-site/           Static HTML copied to /var/www/html
├── web-admin/
│   ├── app.py                 Flask web admin (installed to /opt/fieldday-admin/)
│   ├── templates/
│   │   ├── base.html
│   │   ├── index.html         Dashboard
│   │   └── ap.html            AP configuration form
│   └── static/style.css
├── systemd/
│   ├── fieldday-admin.service Web admin systemd unit
│   └── fieldday-ap-ifup.service  AP interface IP setup
└── scripts/
    └── fieldday-ap-ifup.sh    Brings up AP interface with static IP
```

## Runtime file locations

| File | Purpose |
|------|---------|
| `/etc/fieldday/ap_settings.json` | AP settings (source of truth for web UI) |
| `/etc/hostapd/hostapd.conf` | Generated from ap_settings.json |
| `/etc/dnsmasq.conf` | Generated from ap_settings.json |
| `/opt/fieldday-admin/` | Web admin application |
| `/var/www/html/` | Main Field Day website |

## Samba shares

After install, the following shares are available:

```
\\192.168.73.100\fieldday   → /home/fieldday  (user: fieldday / pass: fd2021)
\\192.168.73.100\pi         → /home/pi        (user: pi / pass: raspberry)
```

Place N3FJP or other log databases in `/home/fieldday`.
