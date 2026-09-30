#!/usr/bin/env python3
"""NERV tactical HUD data feed.

Long-running, low-cost collector for the zalo.nerv-tactical desktop HUD.
Emits one compact JSON object per line on stdout every TICK seconds:
nearby Wi-Fi networks (NetworkManager's cached scan list via nmcli; a real
scan is requested at most once per SCAN_EVERY, persisted across restarts),
the associated link (iw dev <wlan> link), interface rates (/proc/net/dev),
the system timezone (/etc/localtime), CPU (/proc/stat), temps
(hwmon, nvidia-smi only while the dGPU is already awake), disks (statvfs),
top process (/proc/*/stat deltas), uptime, and the latest kernel messages
(a `journalctl -k -f` child read without polling).

Exits when stdout closes or its parent (omarchy-shell) goes away.
"""
import json
import os
import select
import signal
import subprocess
import sys
import time
import zlib

TICK = 3.0
SLOW_EVERY = 10       # ticks between disk / timezone refresh (30 s)
GPU_EVERY = 5         # ticks between nvidia-smi calls when dGPU is awake
LIST_EVERY = 20       # ticks between reads of NM's cached scan list (60 s, no radio work)
SCAN_EVERY = 600      # seconds between real scans we request (wall clock, persisted)
SCAN_SETTLE = 9       # seconds after a scan request before re-reading the list
MAX_NETS = 20         # blips sent to the radar (strongest first; connected always kept)
# last scan time + its results (the kernel's BSS cache forgets networks ~30 s after a scan, so
# we keep our own; user-private tmpfs, survives shell restarts, gone at logout)
SCAN_STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "nerv-tactical-wifi.json")
PARENT = os.getppid()
CLK = os.sysconf("SC_CLK_TCK")


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default


# ------------------------------------------------------------------ network
def default_iface():
    # /proc/net/route: first default route (destination 00000000)
    best = None
    for line in read("/proc/net/route").splitlines()[1:]:
        p = line.split()
        if len(p) > 7 and p[1] == "00000000":
            metric = int(p[6])
            if best is None or metric < best[1]:
                best = (p[0], metric)
    return best[0] if best else ""


def net_bytes(iface):
    for line in read("/proc/net/dev").splitlines()[2:]:
        name, _, rest = line.partition(":")
        if name.strip() == iface:
            f = rest.split()
            return int(f[0]), int(f[8])
    return 0, 0


def wifi_dev():
    try:
        for d in sorted(os.listdir("/sys/class/net")):
            if os.path.isdir(f"/sys/class/net/{d}/wireless"):
                return d
    except OSError:
        pass
    return ""


def run(cmd, timeout=3):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None


def link_info(dev):
    """Associated BSS from `iw dev <dev> link` (netlink, unprivileged, no radio work)."""
    r = run(["iw", "dev", dev, "link"], 2) if dev else None
    if not r or not r.stdout.startswith("Connected"):
        return None
    out = {"bssid": r.stdout.split()[2].lower()}
    for line in r.stdout.splitlines()[1:]:
        k, _, v = line.strip().partition(":")
        v = v.strip()
        try:
            if k == "SSID":
                out["ssid"] = v
            elif k == "freq":
                out["freq"] = round(float(v))
            elif k == "signal":
                out["dbm"] = int(v.split()[0])
            elif k == "rx bitrate":
                out["rxBit"] = float(v.split()[0])
            elif k == "tx bitrate":
                out["txBit"] = float(v.split()[0])
        except (ValueError, IndexError):
            pass
    return out


def nm_split(line):
    # nmcli -t -e yes: fields separated by ':'; literal ':' and backslash are backslash-escaped
    f, cur, esc = [], "", False
    for ch in line:
        if esc:
            cur += ch
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            f.append(cur)
            cur = ""
        else:
            cur += ch
    f.append(cur)
    return f


def sec_short(s):
    s = s.upper()
    if not s.strip():
        return "OPEN"
    if "802.1X" in s:
        return "EAP"
    if "WPA3" in s and "WPA2" not in s and "WPA1" not in s:
        return "SAE"
    if "WPA" in s:
        return "PSK"
    if "WEP" in s:
        return "WEP"
    return s.split()[0][:4]


def band(freq):
    return "2.4G" if freq < 3000 else "5G" if freq < 5925 else "6G"


def pct_to_dbm(p):
    # inverse of NetworkManager's nm_wifi_utils_level_to_quality (-100..-40 dBm -> 0..100 %)
    return round(-40 - (100 - p) * 0.6)


def bearing(key):
    return (zlib.crc32(key.encode()) % 3600) / 10.0


def wifi_list(dev):
    """NetworkManager's cached scan results. `--rescan no`: never triggers radio work."""
    r = run(["nmcli", "-t", "-e", "yes", "-f", "IN-USE,BSSID,SSID,CHAN,FREQ,RATE,SIGNAL,SECURITY",
             "dev", "wifi", "list", "ifname", dev, "--rescan", "no"])
    if not r or r.returncode != 0:
        return None
    nets = []
    for line in r.stdout.splitlines():
        f = nm_split(line)
        if len(f) < 8:
            continue
        try:
            freq = int(f[4].split()[0])
            sig = int(f[6])
            ch = int(f[3])
        except (ValueError, IndexError):
            continue
        bssid = f[1].lower()
        nets.append({"id": bssid or f[2], "ssid": f[2], "ch": ch, "freq": freq, "band": band(freq),
                     "sig": sig, "dbm": pct_to_dbm(sig), "sec": sec_short(f[7]),
                     "cur": f[0].strip() == "*", "brg": bearing(bssid or f[2])})
    nets.sort(key=lambda n: (n["cur"], n["sig"]), reverse=True)
    return nets


def request_scan(dev):
    r = run(["nmcli", "dev", "wifi", "rescan", "ifname", dev], 5)
    ok = bool(r and r.returncode == 0)
    msg = (r.stderr.strip() if r else "nmcli failed")[:120]
    info(f"wifi scan requested on {dev}: " + ("ok" if ok else msg))
    return ok


def load_state():
    try:
        st = json.loads(read(SCAN_STATE) or "{}")
        return float(st.get("at", 0)), {x["id"]: x for x in st.get("nets", []) if "id" in x}
    except (ValueError, TypeError, KeyError, AttributeError):
        return 0.0, {}


def save_state(at, known):
    try:
        tmp = SCAN_STATE + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump({"at": round(at), "nets": list(known.values())}, f, separators=(",", ":"))
        os.replace(tmp, SCAN_STATE)
    except OSError:
        pass


def merge_scan(known, got, full):
    """Fold a cached-list read into our own result cache. `full`: read right after our scan,
    so networks missing from it are gone (unless the read looks like a failed scan)."""
    now = time.time()
    for x in known.values():
        x["cur"] = False
    if full and len(got) > 1:
        known = {k: v for k, v in known.items() if any(g["id"] == k for g in got)}
    for g in got:
        g["seen"] = round(now)
        known[g["id"]] = g
    # safety net: forget anything not seen for two scan periods
    return {k: v for k, v in known.items() if now - v.get("seen", 0) < 2 * SCAN_EVERY + 60}


def info(msg):
    try:
        sys.stderr.write("[info] " + msg + "\n")
        sys.stderr.flush()
    except OSError:
        pass


# ------------------------------------------------------------------ timezone
def timezone():
    name = ""
    try:
        t = os.readlink("/etc/localtime")
        if "zoneinfo/" in t:
            name = t.split("zoneinfo/", 1)[1]
    except OSError:
        pass
    if not name:
        name = os.environ.get("TZ", "").lstrip(":")
    if not name:
        r = run(["timedatectl", "show", "-p", "Timezone", "--value"], 2)
        name = r.stdout.strip() if r else ""
    time.tzset()
    lt = time.localtime()
    return {"name": name or "UTC", "abbr": lt.tm_zone or "", "off": lt.tm_gmtoff or 0}


# ------------------------------------------------------------------ cpu / procs
def cpu_times():
    f = read("/proc/stat").split("\n", 1)[0].split()[1:]
    v = [int(x) for x in f]
    idle = v[3] + (v[4] if len(v) > 4 else 0)
    return sum(v), idle


def proc_scan():
    out = {}
    try:
        pids = [d for d in os.listdir("/proc") if d.isdigit()]
    except OSError:
        return out, 0
    for pid in pids:
        s = read(f"/proc/{pid}/stat")
        if not s:
            continue
        r = s.rfind(")")
        name = s[s.find("(") + 1:r]
        f = s[r + 2:].split()
        try:
            out[pid] = (name, int(f[11]) + int(f[12]))
        except (IndexError, ValueError):
            pass
    return out, len(pids)


# ------------------------------------------------------------------ temps
def hwmon_temps():
    t = {}
    base = "/sys/class/hwmon"
    try:
        mons = os.listdir(base)
    except OSError:
        return t
    for m in mons:
        name = read(f"{base}/{m}/name").strip()
        key = {"k10temp": "cpu", "coretemp": "cpu", "amdgpu": "igpu", "nvme": "nvme",
               "acpitz": "acpi"}.get(name)
        if not key or key in t:
            continue
        v = read(f"{base}/{m}/temp1_input").strip()
        if v.lstrip("-").isdigit():
            t[key] = round(int(v) / 1000.0, 1)
    return t


def nvidia_dev():
    base = "/sys/bus/pci/devices"
    try:
        for d in os.listdir(base):
            if read(f"{base}/{d}/vendor").strip() == "0x10de" and read(f"{base}/{d}/class").startswith("0x03"):
                return f"{base}/{d}"
    except OSError:
        pass
    return ""


def nvidia_temp(dev):
    """(state, temp, util). Never wakes a runtime-suspended dGPU."""
    if not dev:
        return "none", None, None
    st = read(f"{dev}/power/runtime_status").strip() or "unknown"
    if st != "active":
        return st, None, None
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=temperature.gpu,utilization.gpu",
                              "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=3).stdout.strip()
        a, b = [x.strip() for x in out.split(",")[:2]]
        return st, float(a), float(b)
    except Exception:
        return st, None, None


# ------------------------------------------------------------------ power
def power():
    base = "/sys/class/power_supply"
    ac, bat = None, None
    try:
        for d in os.listdir(base):
            t = read(f"{base}/{d}/type").strip()
            if t == "Mains" and ac is not True:
                ac = read(f"{base}/{d}/online").strip() == "1"
            elif t == "Battery" and bat is None and read(f"{base}/{d}/scope").strip() != "Device":
                v = read(f"{base}/{d}/capacity").strip()
                bat = int(v) if v.isdigit() else None
    except OSError:
        pass
    return {"ac": ac if ac is not None else True, "bat": bat}


# ------------------------------------------------------------------ disks
SKIP_FS = {"tmpfs", "devtmpfs", "proc", "sysfs", "cgroup2", "overlay", "efivarfs", "securityfs",
           "debugfs", "tracefs", "configfs", "fusectl", "pstore", "bpf", "mqueue", "hugetlbfs",
           "autofs", "devpts", "ramfs", "nsfs", "binfmt_misc", "fuse.portal", "squashfs",
           "fuse.gvfsd-fuse", "rpc_pipefs", "selinuxfs", "zram"}


def disks():
    seen = set()
    out = []
    for line in read("/proc/self/mounts").splitlines():
        p = line.split()
        if len(p) < 3 or p[2] in SKIP_FS or not p[0].startswith("/dev/"):
            continue
        dev, mnt = p[0], p[1].replace("\\040", " ")
        if dev in seen:
            continue
        try:
            s = os.statvfs(mnt)
        except OSError:
            continue
        total = s.f_blocks * s.f_frsize
        if total < 64 * 1024 * 1024:
            continue
        seen.add(dev)
        used = (s.f_blocks - s.f_bfree) * s.f_frsize
        out.append({"mnt": mnt, "dev": os.path.basename(dev), "fs": p[2],
                    "size": total, "pct": round(100.0 * used / total, 1)})
    return out[:6]


# ------------------------------------------------------------------ kernel log
def _die_with_parent():
    try:
        import ctypes
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except Exception:
        pass


def start_klog():
    try:
        return subprocess.Popen(["journalctl", "-k", "-f", "-n", "4", "-o", "cat", "--no-pager"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0,
                                preexec_fn=_die_with_parent)
    except Exception:
        return None


def squash_kmsg(line):
    line = " ".join(line.split())
    if line.startswith("[UFW BLOCK]"):
        kv = dict(t.split("=", 1) for t in line.split() if "=" in t)
        dpt = kv.get("DPT", "")
        return "INTRUSION REPELLED 迎撃 SRC " + kv.get("SRC", "?") + " PROTO " + kv.get("PROTO", "?") \
            + (" DPT " + dpt if dpt else "")
    return line[:110]


def main():
    iface = ""
    wdev = ""
    tz = timezone()
    nets = []
    scan_at, known = load_state()   # wall-clock time of our last scan request (0 = never) + results
    list_due = 0.0                  # monotonic time of a pending post-scan list read
    dsk = []
    gpu = ("none", None, None)
    nv = nvidia_dev()
    last_net = None
    last_cpu = cpu_times()
    last_procs, _ = proc_scan()
    last_t = time.monotonic()
    kmsgs = []
    klog = start_klog()
    kbuf = b""
    n = 0
    next_tick = time.monotonic()
    while True:
        # wait until next tick, draining the kernel log as it arrives
        while True:
            now = time.monotonic()
            wait = next_tick - now
            if wait <= 0:
                break
            if klog and klog.stdout:
                r, _, _ = select.select([klog.stdout], [], [], wait)
                if r:
                    chunk = os.read(klog.stdout.fileno(), 8192)
                    if not chunk:
                        klog = None
                        continue
                    kbuf += chunk
                    while b"\n" in kbuf:
                        ln, kbuf = kbuf.split(b"\n", 1)
                        s = ln.decode("utf-8", "replace").strip()
                        if s:
                            kmsgs.append(squash_kmsg(s))
                    kmsgs = kmsgs[-4:]
            else:
                time.sleep(wait)
        next_tick += TICK
        if time.monotonic() - next_tick > TICK:
            next_tick = time.monotonic() + TICK
        if os.getppid() != PARENT:
            break

        now = time.monotonic()
        dt = max(0.5, now - last_t)
        last_t = now

        if n % SLOW_EVERY == 0:
            iface = default_iface()
            wdev = wifi_dev()
            tz = timezone()
            dsk = disks()
        if n % GPU_EVERY == 0:
            gpu = nvidia_temp(nv)

        rx, tx = net_bytes(iface)
        if last_net and last_net[0] == iface:
            rxr = max(0, rx - last_net[1]) / dt
            txr = max(0, tx - last_net[2]) / dt
        else:
            rxr = txr = 0
        last_net = (iface, rx, tx)

        tot, idle = cpu_times()
        dtot = max(1, tot - last_cpu[0])
        cpu = 100.0 * (1 - (idle - last_cpu[1]) / dtot)
        last_cpu = (tot, idle)

        procs, nprocs = proc_scan()
        top = ("", "", 0.0)
        for pid, (name, ticks) in procs.items():
            prev = last_procs.get(pid)
            if prev and prev[0] == name:
                d = ticks - prev[1]
                if d > 0:
                    pct = 100.0 * d / CLK / dt
                    if pct > top[2]:
                        top = (name, pid, pct)
        last_procs = procs

        # wifi: request a real scan at most once per SCAN_EVERY (state survives restarts); between
        # scans only re-read NetworkManager's cached list once a minute and fold it into our cache
        link = link_info(wdev)
        if wdev:
            wall_now = time.time()
            if wall_now - scan_at >= SCAN_EVERY or scan_at > wall_now + 60:
                request_scan(wdev)
                scan_at = wall_now
                save_state(scan_at, known)
                list_due = now + SCAN_SETTLE
            full = bool(list_due) and now >= list_due
            if n % LIST_EVERY == 0 or full:
                if full:
                    list_due = 0.0
                got = wifi_list(wdev)
                if got is not None:
                    known = merge_scan(known, got, full)
                    if full:
                        save_state(scan_at, known)
                    nets = sorted(known.values(), key=lambda x: (x["cur"], x["sig"]), reverse=True)
            elif not nets and known:
                nets = sorted(known.values(), key=lambda x: (x["cur"], x["sig"]), reverse=True)
        else:
            nets = []
        cur = next((x for x in nets if x["cur"]), None)
        if link:
            if cur is None:
                cur = next((x for x in nets if x["id"] == link["bssid"]), None)
            link.update({k: cur[k] for k in ("ch", "band", "sec", "sig", "brg")} if cur else
                        {"ch": 0, "band": band(link.get("freq", 2400)), "sec": "", "sig": 0,
                         "brg": bearing(link["bssid"])})
            link["cur"] = True
            link["id"] = cur["id"] if cur else link["bssid"]
        sent = nets[:MAX_NETS]
        if cur is not None and cur not in sent:
            sent = [cur] + nets[:MAX_NETS - 1]

        load = read("/proc/loadavg").split()[:3]
        mi = {}
        for line in read("/proc/meminfo").splitlines()[:5]:
            k, _, v = line.partition(":")
            mi[k] = int(v.split()[0])
        mem = 100.0 * (1 - mi.get("MemAvailable", 0) / max(1, mi.get("MemTotal", 1)))

        temps = hwmon_temps()
        temps["dgpu"] = gpu[1]
        payload = {
            "n": n,
            "wifi": {
                "dev": wdev, "nets": sent, "count": len(nets),
                "ssids": len({x["ssid"] for x in nets if x["ssid"]}),
                "open": sum(1 for x in nets if x["sec"] == "OPEN"),
                "link": link, "scanAt": round(scan_at), "scanEvery": SCAN_EVERY,
            },
            "tz": tz,
            "iface": iface, "ssid": link.get("ssid", "") if link else "",
            "rx": round(rxr), "tx": round(txr),
            "cpu": round(cpu, 1), "mem": round(mem, 1), "load": load, "procs": nprocs,
            "top": {"name": top[0], "pid": top[1], "pct": round(top[2], 1)},
            "temps": temps, "dgpu": gpu[0], "dgpuUtil": gpu[2],
            "uptime": float(read("/proc/uptime", "0 0").split()[0]),
            "disks": dsk,
            "power": power(),
            "kmsg": kmsgs[-3:],
        }
        try:
            sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
            sys.stdout.flush()
        except (BrokenPipeError, OSError):
            break
        n += 1
    if klog:
        klog.terminate()


if __name__ == "__main__":
    _die_with_parent()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        main()
    except KeyboardInterrupt:
        pass
