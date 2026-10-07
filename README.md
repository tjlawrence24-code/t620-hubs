# t620-hubs

One-command setup for TJ's two HP t620 thin clients, replacing the Raspberry Pi `printpi`:

| Hub | Runs |
|---|---|
| `scanhub` | AirSane (Fujitsu fi-7160 → network/AirScan scanner on :8090), SANE |
| `printhub` | uStreamer cams (8082-8084) + Caddy (:8081 `/cam1..3`), Klipper config backup (03:00), Tailscale subnet router |

Both: avahi (`<hub>.local`), OpenSSH with TJ's Mac key, passwordless sudo, fail2ban (LAN + tailnet never banned).

## Install
1. Install Ubuntu Server 26.04 LTS from USB (entire disk, hostname = hub name, user `tjlawre24`, tick OpenSSH).
2. Get the box online (below), then:
   ```bash
   git clone https://github.com/tjlawrence24-code/t620-hubs && sudo t620-hubs/install.sh scanhub   # or printhub
   ```
3. Last line says `SETUP OK`. Log: `/var/log/<hub>-setup.log`.

Or let Claude Code do it: `cd t620-hubs && claude` and say "set this box up" — it reads `CLAUDE.md`.

## No network
- **Wi-Fi**: after install.sh, run `wifi-setup` (asks for network + password, survives reboots). Any adapter is named `wlan0`.
  ```bash
  sudo tee /etc/netplan/60-wifi.yaml >/dev/null <<'Y'
  network:
    version: 2
    wifis:
      WLAN:
        match: {name: "wl*"}
        dhcp4: true
        access-points:
          "Lawrence": {password: "YOUR-WIFI-PASSWORD"}
  Y
  sudo chmod 600 /etc/netplan/60-wifi.yaml && sudo netplan apply
  ```
  Needs `wpasupplicant` — installed only if the installer saw Wi-Fi. Otherwise tether first.
- **Phone USB tethering**: plug in, turn on Personal Hotspot / USB tethering; Ubuntu gets DHCP automatically.
  If not, `ip link` → find the new `enx…`/`usb0` interface → `sudo dhcpcd <iface>` or `sudo networkctl reconfigure <iface>`.
- **USB Ethernet adapter**: plug in; works like built-in Ethernet.
