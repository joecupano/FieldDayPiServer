#!/usr/bin/env python3
"""FieldDay Pi Server — Web Admin (port 8080)"""

import json
import os
import re
import subprocess
from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, session

app = Flask(__name__)

try:
    with open("/etc/fieldday/admin_secret.key") as f:
        app.secret_key = f.read().strip()
except OSError:
    app.secret_key = "fieldday-dev-key-not-for-production"

SETTINGS_FILE = "/etc/fieldday/ap_settings.json"
HOSTAPD_CONF  = "/etc/hostapd/hostapd.conf"
DNSMASQ_CONF  = "/etc/dnsmasq.conf"
NM_UNMANAGED  = "/etc/NetworkManager/conf.d/99-fieldday-unmanaged.conf"

# ── Auth ───────────────────────────────────────────────────────────────────────

try:
    import pam as _pam
    def _check_password(password):
        return _pam.pam().authenticate("pi", password)
except ImportError:
    def _check_password(password):
        return password == "raspberry"  # dev fallback only


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login", next=request.path))
        return f(*args, **kwargs)
    return decorated


@app.route("/login", methods=["GET", "POST"])
def login():
    if session.get("logged_in"):
        return redirect(url_for("index"))
    if request.method == "POST":
        if _check_password(request.form.get("password", "")):
            session["logged_in"] = True
            return redirect(request.form.get("next") or url_for("index"))
        flash("Incorrect password.", "danger")
    return render_template("login.html", next=request.args.get("next", ""))


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# ── Settings helpers ───────────────────────────────────────────────────────────

def load_settings():
    try:
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    except Exception:
        return {
            "ssid": "FieldDay",
            "passphrase": "fieldday1234",
            "channel": 6,
            "hw_mode": "g",
            "ap_interface": "wlan1",
            "ap_ip": "192.168.73.1",
            "dhcp_start": "192.168.73.10",
            "dhcp_end": "192.168.73.200",
            "dhcp_mask": "255.255.255.0",
            "dhcp_lease": "24h",
            "domain": "fieldday.local",
        }


def save_settings(s):
    with open(SETTINGS_FILE, "w") as f:
        json.dump(s, f, indent=4)


def _prefix(mask):
    return sum(bin(int(o)).count("1") for o in mask.split("."))


# ── AP helpers ─────────────────────────────────────────────────────────────────

def write_hostapd_conf(s):
    conf = (
        f"interface={s['ap_interface']}\n"
        f"driver=nl80211\n"
        f"ssid={s['ssid']}\n"
        f"hw_mode={s['hw_mode']}\n"
        f"channel={s['channel']}\n"
        f"ieee80211n=1\n"
        f"wmm_enabled=1\n"
        f"macaddr_acl=0\n"
        f"auth_algs=1\n"
        f"ignore_broadcast_ssid=0\n"
        f"wpa=2\n"
        f"wpa_passphrase={s['passphrase']}\n"
        f"wpa_key_mgmt=WPA-PSK\n"
        f"wpa_pairwise=TKIP\n"
        f"rsn_pairwise=CCMP\n"
        f"country_code=US\n"
    )
    with open(HOSTAPD_CONF, "w") as f:
        f.write(conf)


def write_dnsmasq_conf(s):
    conf = (
        f"# FieldDay Pi Server - dnsmasq\n"
        f"interface={s['ap_interface']}\n"
        f"bind-interfaces\n"
        f"dhcp-range={s['dhcp_start']},{s['dhcp_end']},{s['dhcp_mask']},{s['dhcp_lease']}\n"
        f"domain={s['domain']}\n"
        f"local=/{s['domain']}/\n"
        f"address=/{s['domain']}/{s['ap_ip']}\n"
        f"dhcp-option=6,{s['ap_ip']}\n"
    )
    with open(DNSMASQ_CONF, "w") as f:
        f.write(conf)


def apply_interface_ip(s):
    iface  = s["ap_interface"]
    ip     = s["ap_ip"]
    prefix = _prefix(s["dhcp_mask"])
    subprocess.run(["ip", "link", "set", iface, "up"],                    capture_output=True)
    subprocess.run(["ip", "addr", "flush", "dev", iface],                 capture_output=True)
    subprocess.run(["ip", "addr", "add", f"{ip}/{prefix}", "dev", iface], capture_output=True)


def update_nm_unmanaged(iface):
    if not os.path.isdir("/etc/NetworkManager/conf.d"):
        return
    with open(NM_UNMANAGED, "w") as f:
        f.write(f"[keyfile]\nunmanaged-devices=interface-name:{iface}\n")
    subprocess.run(["nmcli", "general", "reload"], capture_output=True)


def apply_ap_config(s):
    write_hostapd_conf(s)
    write_dnsmasq_conf(s)
    update_nm_unmanaged(s["ap_interface"])
    apply_interface_ip(s)
    subprocess.run(["systemctl", "restart", "hostapd"], capture_output=True)
    subprocess.run(["systemctl", "restart", "dnsmasq"], capture_output=True)


def service_status(name):
    r = subprocess.run(["systemctl", "is-active", name], capture_output=True, text=True)
    return r.stdout.strip()


def get_connected_clients():
    clients = []
    try:
        with open("/var/lib/misc/dnsmasq.leases") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 4:
                    clients.append({
                        "mac":      parts[1],
                        "ip":       parts[2],
                        "hostname": parts[3] if parts[3] != "*" else "—",
                    })
    except FileNotFoundError:
        pass
    return clients


# ── Routes ─────────────────────────────────────────────────────────────────────

@app.route("/")
@login_required
def index():
    s = load_settings()
    return render_template(
        "index.html",
        settings=s,
        ap_status=service_status("hostapd"),
        clients=get_connected_clients(),
    )


@app.route("/ap", methods=["GET", "POST"])
@login_required
def ap_config():
    s = load_settings()

    if request.method == "POST":
        errors = []
        new_s  = dict(s)

        ssid = request.form.get("ssid", "").strip()
        if not ssid or len(ssid) > 32:
            errors.append("SSID must be 1–32 characters.")
        else:
            new_s["ssid"] = ssid

        passphrase = request.form.get("passphrase", "").strip()
        if passphrase:
            if len(passphrase) < 8 or len(passphrase) > 63:
                errors.append("Passphrase must be 8–63 characters (leave blank to keep current).")
            else:
                new_s["passphrase"] = passphrase

        try:
            ch = int(request.form.get("channel", 6))
            if ch not in range(1, 12):
                raise ValueError()
            new_s["channel"] = ch
        except (ValueError, TypeError):
            errors.append("Channel must be 1–11.")

        ip_re = r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"
        for field in ("ap_ip", "dhcp_start", "dhcp_end"):
            val = request.form.get(field, "").strip()
            if not re.match(ip_re, val):
                errors.append(f"Invalid IP address for {field}.")
            else:
                new_s[field] = val

        domain = request.form.get("domain", "").strip().lower()
        if not re.match(r"^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z]{2,})*$", domain):
            errors.append("Invalid domain name.")
        else:
            new_s["domain"] = domain

        if errors:
            for e in errors:
                flash(e, "danger")
            return render_template("ap.html", settings=s)

        save_settings(new_s)
        try:
            apply_ap_config(new_s)
            flash("AP configuration saved and applied. Clients will reconnect shortly.", "success")
        except Exception as exc:
            flash(f"Settings saved but apply failed: {exc}", "warning")

        return redirect(url_for("ap_config"))

    return render_template("ap.html", settings=s)


@app.route("/ap/restart", methods=["POST"])
@login_required
def restart_ap():
    try:
        subprocess.run(["systemctl", "restart", "hostapd"], check=True)
        subprocess.run(["systemctl", "restart", "dnsmasq"], check=True)
        flash("Access point restarted.", "success")
    except subprocess.CalledProcessError as e:
        flash(f"Restart failed: {e}", "danger")
    return redirect(url_for("index"))


@app.route("/api/status")
@login_required
def api_status():
    return jsonify({
        "hostapd": service_status("hostapd"),
        "dnsmasq": service_status("dnsmasq"),
        "clients": get_connected_clients(),
    })


# ── Entrypoint ─────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False, threaded=True)
