#!/usr/bin/env python3
"""Process-monitor feed for zalo.nerv-seele (PROCESSES / プロセス監視; no deps).

Every tick (2 s while the desktop is visible, 5 s otherwise; the shell writes
"active"/"idle" lines on stdin) it reads /proc/[pid]/stat for every process,
computes the *current* CPU% (per-core, like top) from jiffy deltas, smooths it,
and puts the 12 hungriest processes into 12 slots. Slots are sticky: a process
keeps its slot until it exits or a challenger clearly out-consumes the weakest
one, so the monoliths never shuffle on small fluctuations. The LOG lines are
plain language ("firefox EXITED · slot 03 free", "slot 03 → code"). One JSON
line per tick on stdout.
"""
import json
import os
import select
import sys
import time

SEATS = 12
HIST = 64
TCK = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
SELF = os.getpid()

prev = {}        # pid -> (utime+stime, starttime)
ema = {}         # pid -> smoothed cpu%
names = {}       # pid -> comm
seats = [None] * SEATS
hist = {}        # pid -> [cpu history] for seated pids
speaker = -1
log = []
prev_t = None
prev_total = None
interval = 2.0


def stamp():
    return time.strftime("%H:%M")


def note(s):
    log.append(stamp() + " " + s)
    del log[:-8]


def read_total():
    with open("/proc/stat") as f:
        v = [int(x) for x in f.readline().split()[1:]]
    idle = v[3] + v[4]
    return sum(v[:8]), idle


def scan():
    """-> {pid: (ticks, start, comm, rss_bytes, threads)}"""
    out = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open("/proc/" + d + "/stat", "rb") as f:
                s = f.read()
        except OSError:
            continue
        r = s.rfind(b")")
        comm = s[s.find(b"(") + 1:r].decode("utf-8", "replace")
        f = s[r + 2:].split()
        # f[0] = state (field 3); utime=14 stime=15 threads=20 start=22 rss=24
        try:
            out[int(d)] = (int(f[11]) + int(f[12]), int(f[19]), comm, int(f[21]) * PAGE, int(f[17]))
        except (IndexError, ValueError):
            pass
    return out


def tag(i):
    return "slot %02d" % (i + 1)


def tick():
    global prev_t, speaker, prev_total
    now = time.monotonic()
    procs = scan()
    tot, idl = read_total()
    dt = (now - prev_t) if prev_t else None
    machine = 0.0
    if prev_total:
        dtot = tot - prev_total[0]
        if dtot > 0:
            machine = 100.0 * (1 - (idl - prev_total[1]) / dtot)
    prev_total = (tot, idl)
    prev_t = now
    with open("/proc/uptime") as f:
        up = float(f.read().split()[0])
    # "STARTED" in the log = the process is under 15 s old when it takes a slot
    fresh = lambda p: up - procs[p][1] / TCK < 15
    cur = {}
    threads = 0
    for pid, (ticks, start, comm, rss, thr) in procs.items():
        threads += thr
        p = prev.get(pid)
        if dt and p and p[1] == start:
            c = max(0.0, (ticks - p[0]) / TCK / dt * 100.0)
        else:
            c = 0.0
        cur[pid] = c
        e = ema.get(pid)
        ema[pid] = c if e is None else e * 0.45 + c * 0.55
        names[pid] = comm
    for pid in list(prev):
        if pid not in procs:
            prev.pop(pid, None)
            ema.pop(pid, None)
            if pid not in seats:  # seated names are kept for the EXITED note
                names.pop(pid, None)
    for pid, v in procs.items():
        prev[pid] = (v[0], v[1])
    if not dt:
        return None

    # ---- seating
    for i, pid in enumerate(seats):
        if pid is not None and pid not in procs:
            note(names.pop(pid, "?") + " EXITED · " + tag(i) + " free")
            seats[i] = None
            hist.pop(pid, None)
    seated = set(p for p in seats if p is not None)
    cands = sorted((p for p in procs if p not in seated and p != SELF), key=lambda p: -ema[p])
    ci = 0
    first = all(p is None for p in seats)
    for i in range(SEATS):
        if seats[i] is None and ci < len(cands):
            seats[i] = cands[ci]
            ci += 1
            if not first:
                c = seats[i]
                note(names[c] + " STARTED → " + tag(i) if fresh(c) else tag(i) + " → " + names[c])
    for _ in range(3):  # at most 3 replacements per tick
        if ci >= len(cands):
            break
        c = cands[ci]
        weak = min(range(SEATS), key=lambda i: ema.get(seats[i], 0.0))
        w = ema.get(seats[weak], 0.0)
        if ema[c] > w * 1.6 + 1.5:
            old = seats[weak]
            hist.pop(old, None)
            seats[weak] = c
            note((names[c] + " STARTED → " + tag(weak) + ", was " if fresh(c) else tag(weak) + ": ") + names[old]
                 + ("" if fresh(c) else " → " + names[c]))
            ci += 1
        else:
            break

    for pid in seats:
        h = hist.setdefault(pid, [])
        h.append(round(cur.get(pid, 0.0), 1))
        del h[:-HIST]

    # ---- the top process (hysteresis so the top slot isn't passed back and forth)
    best = max(range(SEATS), key=lambda i: ema.get(seats[i], 0.0))
    if speaker < 0 or seats[speaker] is None:
        speaker = best
        note("TOP CPU → " + names[seats[speaker]])
    elif best != speaker and ema[seats[best]] > ema[seats[speaker]] * 1.3 + 0.8:
        speaker = best
        note("TOP CPU → " + names[seats[speaker]])

    out = []
    for pid in seats:
        v = procs[pid]
        out.append({"pid": pid, "name": v[2], "cpu": round(ema[pid], 1), "now": round(cur[pid], 1),
                    "rss": v[3], "thr": v[4]})
    return {"seats": out, "speaker": speaker, "hist": hist.get(seats[speaker], []),
            "procs": len(procs), "threads": threads, "machine": round(machine, 1),
            "ncpu": os.cpu_count(), "log": log}


def main():
    global interval
    stdin_ok = True
    tick()
    time.sleep(0.5)
    while True:
        d = tick()
        if d:
            sys.stdout.write(json.dumps(d, separators=(",", ":")) + "\n")
            sys.stdout.flush()
        deadline = time.monotonic() + interval
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                break
            if not stdin_ok:
                time.sleep(left)
                break
            r, _, _ = select.select([sys.stdin], [], [], left)
            if not r:
                break
            line = sys.stdin.readline()
            if not line:  # stdin closed: keep the default cadence
                stdin_ok = False
                continue
            line = line.strip()
            if line == "idle":
                interval = 5.0
            elif line == "active":
                interval = 2.0


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
