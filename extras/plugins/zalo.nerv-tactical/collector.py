#!/usr/bin/env python3
"""NERV tactical HUD data feed.

Long-running, low-cost collector for the zalo.nerv-tactical desktop HUD.
Emits one compact JSON object per line on stdout every TICK seconds:
TCP contacts (ss), interface rates (/proc/net/dev), CPU (/proc/stat), temps
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
SLOW_EVERY = 10       # ticks between disk / ssid refresh (30 s)
GPU_EVERY = 5         # ticks between nvidia-smi calls when dGPU is awake
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


def ssid(iface):
    if not iface or not os.path.isdir(f"/sys/class/net/{iface}/wireless"):
        return ""
    try:
        out = subprocess.run(["iw", "dev", iface, "link"], capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return ""
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("SSID:"):
            return line[5:].strip()
    return ""


def split_addr(a):
    # 1.2.3.4:443  |  [::ffff:1.2.3.4]:443  |  [2001:db8::1]:443
    host, _, port = a.rpartition(":")
    host = host.strip("[]")
    if host.startswith("::ffff:"):
        host = host[7:]
    if "%" in host:
        host = host.split("%", 1)[0]
    return host, port


def contacts():
    try:
        out = subprocess.run(["ss", "-tniH", "state", "established"],
                             capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return []
    lines = out.splitlines()
    hosts = {}
    cur = None
    for line in lines:
        if not line.startswith("\t"):
            p = line.split()
            if len(p) >= 4:
                rhost, rport = split_addr(p[3])
                cur = hosts.setdefault(rhost, {"ip": rhost, "port": rport, "n": 0, "rtt": 0.0,
                                               "rx": 0, "tx": 0})
                cur["n"] += 1
                if rport.isdigit() and cur["port"].isdigit() and int(rport) < int(cur["port"]):
                    cur["port"] = rport
            continue
        if cur is None:
            continue
        for tok in line.split():
            k, _, v = tok.partition(":")
            if k == "rtt":
                try:
                    r = float(v.split("/")[0])
                    cur["rtt"] = r if cur["rtt"] == 0 else min(cur["rtt"], r)
                except ValueError:
                    pass
            elif k == "bytes_received":
                cur["rx"] += int(v)
            elif k == "bytes_acked":
                cur["tx"] += int(v)
    return list(hosts.values())


def bearing(ip):
    return (zlib.crc32(ip.encode()) % 3600) / 10.0


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
    ssid_s = ""
    dsk = []
    gpu = ("none", None, None)
    nv = nvidia_dev()
    last_net = None
    last_cpu = cpu_times()
    last_procs, _ = proc_scan()
    last_hosts = {}
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
            ssid_s = ssid(iface)
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

        hs = contacts()
        cur = {}
        for h in hs:
            b = h["rx"] + h["tx"]
            prev = last_hosts.get(h["ip"])
            h["rate"] = max(0, b - prev) / dt if prev is not None else 0
            cur[h["ip"]] = b
            h["brg"] = bearing(h["ip"])
        last_hosts = cur
        hs.sort(key=lambda h: (h["rate"], h["rx"] + h["tx"]), reverse=True)
        total_conns = sum(h["n"] for h in hs)

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
            "conns": [{k: (round(v, 1) if isinstance(v, float) else v) for k, v in h.items()} for h in hs[:28]],
            "hosts": len(hs),
            "total": total_conns,
            "iface": iface, "ssid": ssid_s,
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
