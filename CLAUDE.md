# t620-hubs — instructions for Claude Code on the box

You are running on one of TJ's HP t620 thin clients (AMD GX-415GA, 256 GB M.2, Ubuntu Server 26.04 LTS).
Its hostname should be `printhub` or `scanhub` — ask TJ which if `hostname` is anything else.

## Do this
1. Check internet: `curl -sI -m8 http://archive.ubuntu.com`. If it fails, help TJ get online (see README "No network").
2. Run `sudo ./install.sh <printhub|scanhub>` from this repo. It is idempotent; re-running is safe.
3. Last line must be `SETUP OK`. If not, read `/var/log/<role>-setup.log`, fix, re-run.
4. Verify (below) and report the box's IP (`hostname -I`) to TJ.

## Verify
- scanhub: `systemctl is-active airsaned`, `scanimage -L` shows the Fujitsu fi-7160 (USB), `curl -s localhost:8090 | head`.
- printhub: `systemctl is-active caddy ustreamer-cam1`, `curl -s -o /dev/null -w '%{http_code}' localhost:8081/cam1/snapshot` → 200.
  Camera→port mapping is `/etc/printhub/cams` (line 1 = cam1 bed, 2 = cam2 nozzle, 3 = cam3 stock). If cams are swapped,
  reorder that file and re-run install.sh.

## Rules
- Network is Google Fiber only, LAN 192.168.1.0/24. Printer (QIDI X-Plus 4, Moonraker) is at 192.168.1.243 unless TJ says otherwise
  (override: `sudo PRINTER_IP=x.x.x.x ./install.sh printhub`).
- Tailscale: only printhub is the subnet router. `sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes=false`
  — NEVER accept-routes on a subnet router (it blackholes the LAN). TJ must approve the login link and the route in the admin console.
- No Pi-hole — TJ explicitly does not want it.
- Don't change the SSH key list or user `tjlawre24`; fail2ban must keep ignoring 192.168.1.0/24 and 100.64.0.0/10.
