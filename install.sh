#!/bin/bash
# Turns a fresh Ubuntu Server install on an HP t620 into printhub or scanhub.
# Usage: sudo ./install.sh printhub|scanhub      (safe to re-run)
set -euo pipefail

ROLE="${1:-}"
case "$ROLE" in printhub|scanhub) ;; *) echo "usage: sudo $0 printhub|scanhub"; exit 1 ;; esac
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

REPO="$(cd "$(dirname "$0")" && pwd)"
USER_NAME=tjlawre24
PRINTER_IP="${PRINTER_IP:-192.168.1.243}"   # QIDI X-Plus 4 (Moonraker)
LOG=/var/log/$ROLE-setup.log
exec > >(tee -a "$LOG") 2>&1
echo "=== $ROLE setup $(date) ==="

curl -sI -m8 http://archive.ubuntu.com >/dev/null \
  || { echo "NO INTERNET - connect Wi-Fi/tether/ethernet first (see README)"; exit 1; }

# --- common ---------------------------------------------------------------
hostnamectl set-hostname "$ROLE"
grep -q "127.0.1.1 $ROLE" /etc/hosts || sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $ROLE/" /etc/hosts
timedatectl set-timezone America/Phoenix

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get -y install avahi-daemon openssh-server curl git cron htop fail2ban usbutils

id "$USER_NAME" >/dev/null 2>&1 || { echo "user $USER_NAME missing - create it in the installer"; exit 1; }
H=$(getent passwd "$USER_NAME" | cut -d: -f6)
install -d -m700 -o "$USER_NAME" -g "$USER_NAME" "$H/.ssh"
touch "$H/.ssh/authorized_keys"
while read -r k; do grep -qF "$k" "$H/.ssh/authorized_keys" || echo "$k" >> "$H/.ssh/authorized_keys"; done < "$REPO/common/authorized_keys"
chown "$USER_NAME:$USER_NAME" "$H/.ssh/authorized_keys"; chmod 600 "$H/.ssh/authorized_keys"
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$USER_NAME; chmod 440 /etc/sudoers.d/90-$USER_NAME

install -m644 "$REPO/common/jail.local" /etc/fail2ban/jail.local
systemctl enable --now avahi-daemon ssh fail2ban
systemctl restart fail2ban

# Tailscale (login is a separate step: see README)
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh

# --- roles ----------------------------------------------------------------
scanhub() {
  apt-get -y install sane-utils libsane1 sane-airscan build-essential cmake \
    libsane-dev libjpeg-dev libpng-dev libavahi-client-dev libusb-1.0-0-dev
  # AirSane, same commit the Pi ran
  rm -rf /opt/AirSane /opt/AirSane-build
  git clone https://github.com/SimulPiscator/AirSane.git /opt/AirSane
  git -C /opt/AirSane checkout 129cc3bf7258251a0a694dee7741285b59d88f9f
  mkdir -p /opt/AirSane-build && cd /opt/AirSane-build && cmake /opt/AirSane && make -j4 && make install
  mkdir -p /etc/airsane
  install -m644 "$REPO"/scanhub/airsane/* /etc/airsane/
  install -m644 "$REPO/scanhub/default-airsane" /etc/default/airsane
  install -m644 "$REPO/scanhub/fujitsu.conf" /etc/sane.d/fujitsu.conf
  getent group scanner >/dev/null && { id saned >/dev/null 2>&1 && usermod -aG scanner saned; usermod -aG scanner,lp "$USER_NAME"; }
  systemctl daemon-reload
  systemctl enable --now airsaned
  systemctl restart airsaned
  sleep 2
  systemctl is-active --quiet airsaned
}

printhub() {
  apt-get -y install ustreamer caddy v4l-utils python3
  # Cameras: one uStreamer per USB camera, pinned to its physical port.
  # Ports 8082/8083/8084 = cam1 (bed) / cam2 (nozzle) / cam3 (stock).
  # Mapping lives in /etc/printhub/cams (edit + run `sudo t620-hubs/install.sh printhub` to re-apply).
  mkdir -p /etc/printhub
  if [ ! -s /etc/printhub/cams ]; then
    ls /dev/v4l/by-path/*video-index0 2>/dev/null | head -3 > /etc/printhub/cams || true
  fi
  rm -f /etc/systemd/system/ustreamer-cam*.service
  n=0
  while read -r dev; do
    [ -n "$dev" ] || continue
    n=$((n+1)); port=$((8081+n))
    cat > /etc/systemd/system/ustreamer-cam$n.service <<EOF
[Unit]
Description=uStreamer cam$n (USB camera)
After=network.target

[Service]
ExecStart=/usr/bin/ustreamer --device=$dev --host=127.0.0.1 --port=$port --format=MJPEG --resolution=1280x720 --desired-fps=30 --quality=70 --tcp-nodelay
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
  done < /etc/printhub/cams
  systemctl daemon-reload
  for i in $(seq 1 $n); do systemctl enable --now ustreamer-cam$i; systemctl restart ustreamer-cam$i; done
  echo "cameras found: $n (mapping in /etc/printhub/cams)"

  install -m644 "$REPO/printhub/Caddyfile" /etc/caddy/Caddyfile
  systemctl enable --now caddy; systemctl reload caddy || systemctl restart caddy

  # Tailscale subnet router needs IP forwarding
  printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' > /etc/sysctl.d/99-tailscale.conf
  sysctl -p /etc/sysctl.d/99-tailscale.conf

  # Klipper config backup, daily 03:00
  install -d -o "$USER_NAME" -g "$USER_NAME" "$H/klipper-backup"
  sed "s|^PRINTER = .*|PRINTER = \"http://$PRINTER_IP\"|" "$REPO/printhub/backup.py" > "$H/klipper-backup/backup.py"
  chown "$USER_NAME:$USER_NAME" "$H/klipper-backup/backup.py"; chmod 755 "$H/klipper-backup/backup.py"
  CRON="0 3 * * * $H/klipper-backup/backup.py >> $H/klipper-backup/backup.log 2>&1"
  (crontab -u "$USER_NAME" -l 2>/dev/null | grep -v klipper-backup; echo "$CRON") | crontab -u "$USER_NAME" -
  sudo -u "$USER_NAME" "$H/klipper-backup/backup.py" || echo "WARN: printer backup failed - is the printer on at $PRINTER_IP?"

  systemctl is-active --quiet caddy
}

$ROLE
touch /root/${ROLE^^}_SETUP_OK
IP=$(hostname -I | awk '{print $1}')
echo
echo "SETUP OK - $ROLE at $IP ($ROLE.local). Log: $LOG"
echo "Next (optional): sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes=false"
