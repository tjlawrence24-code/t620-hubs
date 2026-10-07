#!/usr/bin/env python3
"""Pull all QIDI X-Plus 4 Klipper config files via Moonraker and commit to a local git repo."""
import os, sys, json, urllib.request, subprocess, datetime

PRINTER = "http://192.168.68.116"
DEST = os.path.expanduser("~/klipper-backup/config")

def api(path):
    with urllib.request.urlopen(f"{PRINTER}{path}", timeout=15) as r:
        return json.load(r)

def main():
    os.makedirs(DEST, exist_ok=True)
    files = api("/server/files/list?root=config")["result"]
    n = 0
    for f in files:
        rel = f["path"]
        dst = os.path.join(DEST, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        url = f"{PRINTER}/server/files/config/{urllib.parse.quote(rel)}"
        try:
            with urllib.request.urlopen(url, timeout=30) as r, open(dst, "wb") as out:
                out.write(r.read())
            n += 1
        except Exception as e:
            print(f"  skip {rel}: {e}", file=sys.stderr)
    print(f"downloaded {n} files")

    repo = os.path.expanduser("~/klipper-backup")
    if not os.path.isdir(os.path.join(repo, ".git")):
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.email", "printpi@local"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "printpi backup"], cwd=repo, check=True)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    diff = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo)
    if diff.returncode != 0:
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        subprocess.run(["git", "commit", "-q", "-m", f"backup {stamp}"], cwd=repo, check=True)
        print("committed changes")
    else:
        print("no changes")

if __name__ == "__main__":
    import urllib.parse
    main()
