#!/usr/bin/env python3
"""NERV psychograph helper: system stats + system-audio spectrum on stdout.

Line protocol (one line per event, space separated):
  S cpu core_max core_avg mem mem_psi rx tx disk  n_cores c0 c1 ...   (every 1 s)
      cpu/core/mem are 0..100 %, mem_psi = PSI some avg10 %, rx/tx/disk in bytes/s
  H state rms_db peak_hz  v0..v(NB-1)  p0..p(NB-1)
      state: A = active audio, Q = stream open but quiet, X = no playback stream
      v/p   : band level / peak hold, integers 0..99
Capture only runs while at least one playback stream (sink-input) exists, so the
sink can still suspend when nothing plays. Output: ~25 fps while sound is
present, 2 fps while quiet or idle.

stdin (from the HUD): "P" = paused (the HUD is covered by windows): audio capture
and FFT stop, no H lines, S lines only every 5 s. "R" = resume.
"""
import ctypes
import math
import os
import select
import signal
import subprocess
import sys
import time

RATE = 22050
N = 1024
HOP = RATE // 25          # 882 samples -> 25 fps
NB = 32
FMIN, FMAX = 40.0, 10000.0
SILENT_DB = -62.0         # below this RMS the signal counts as silent
IDLE_EVERY = 0.5          # seconds between frames when quiet / no stream
STATS_EVERY = 1.0
STATS_EVERY_PAUSED = 5.0

libc = None
try:
    libc = ctypes.CDLL("libc.so.6", use_errno=True)
except OSError:
    pass


def die_with_parent():
    if libc is not None:
        libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG


die_with_parent()


def out(line):
    try:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        shutdown()


# ------------------------------------------------------------------ FFT
BITS = int(math.log2(N))
REV = [int(format(i, "0%db" % BITS)[::-1], 2) for i in range(N)]
TW = [complex(math.cos(-2 * math.pi * k / N), math.sin(-2 * math.pi * k / N)) for k in range(N // 2)]
WIN = [0.5 - 0.5 * math.cos(2 * math.pi * i / (N - 1)) for i in range(N)]
NORM = N / 4.0 * 32768.0  # hann-windowed full-scale sine -> 1.0


def fft(x):
    a = [x[r] for r in REV]
    size = 2
    while size <= N:
        half = size // 2
        step = N // size
        for st in range(0, N, size):
            k = 0
            for j in range(st, st + half):
                t = TW[k] * a[j + half]
                u = a[j]
                a[j] = u + t
                a[j + half] = u - t
                k += step
        size *= 2
    return a


# log-spaced band edges in FFT bins
BIN_HZ = RATE / N
EDGES = [FMIN * (FMAX / FMIN) ** (i / NB) for i in range(NB + 1)]
BANDS = []
for i in range(NB):
    lo = EDGES[i] / BIN_HZ
    hi = EDGES[i + 1] / BIN_HZ
    b0 = max(1, int(math.floor(lo)))
    b1 = max(b0 + 1, int(math.ceil(hi)))
    BANDS.append((b0, min(b1, N // 2)))
# gentle pink tilt so music does not read as all-bass
TILT = [3.0 * math.log2(math.sqrt(EDGES[i] * EDGES[i + 1]) / 1000.0) for i in range(NB)]

# ------------------------------------------------------------------ stats
_prev = {}


def read_cpu():
    rows = []
    with open("/proc/stat") as f:
        for line in f:
            if not line.startswith("cpu"):
                break
            p = line.split()
            vals = list(map(int, p[1:9]))
            idle = vals[3] + vals[4]
            rows.append((sum(vals), idle))
    res = []
    old = _prev.get("cpu")
    if old and len(old) == len(rows):
        for (t1, i1), (t0, i0) in zip(rows, old):
            dt = t1 - t0
            res.append(0.0 if dt <= 0 else 100.0 * (1.0 - (i1 - i0) / dt))
    _prev["cpu"] = rows
    return res


def read_mem():
    info = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            info[k] = int(v.split()[0])
            if len(info) > 20:
                break
    tot = info.get("MemTotal", 1)
    avail = info.get("MemAvailable", tot)
    used = 100.0 * (1.0 - avail / tot)
    psi = 0.0
    try:
        with open("/proc/pressure/memory") as f:
            psi = float(f.readline().split()[1].split("=")[1])
    except (OSError, IndexError, ValueError):
        pass
    return used, psi


def rate(key, value, now):
    old = _prev.get(key)
    _prev[key] = (value, now)
    if not old or now <= old[1]:
        return 0.0
    return max(0.0, (value - old[0]) / (now - old[1]))


def read_net(now):
    rx = tx = 0
    with open("/proc/net/dev") as f:
        for line in f.readlines()[2:]:
            name, data = line.split(":", 1)
            name = name.strip()
            if name == "lo" or name.startswith(("veth", "docker", "br-", "virbr")):
                continue
            p = data.split()
            rx += int(p[0])
            tx += int(p[8])
    return rate("rx", rx, now), rate("tx", tx, now)


def read_disk(now):
    sectors = 0
    with open("/proc/diskstats") as f:
        for line in f:
            p = line.split()
            name = p[2]
            # whole physical disks only (no partitions, dm, loop, zram)
            if name.startswith(("loop", "ram", "zram", "dm-", "md")):
                continue
            if name.startswith("nvme") or name.startswith("mmcblk"):
                if "p" in name[4:]:
                    continue
            elif name[-1].isdigit():
                continue
            sectors += int(p[5]) + int(p[9])
    return rate("disk", sectors * 512, now)


def stats_line():
    now = time.monotonic()
    cpu = read_cpu()
    mem, psi = read_mem()
    rx, tx = read_net(now)
    disk = read_disk(now)
    if not cpu:
        return None
    cores = cpu[1:]
    cmax = max(cores) if cores else cpu[0]
    cavg = sum(cores) / len(cores) if cores else cpu[0]
    return "S %.1f %.1f %.1f %.1f %.2f %d %d %d %d %s" % (
        cpu[0], cmax, cavg, mem, psi, rx, tx, disk, len(cores),
        " ".join("%d" % round(c) for c in cores))


# ------------------------------------------------------------------ audio
def child_preexec():
    os.setsid()
    die_with_parent()


class Audio:
    def __init__(self):
        self.proc = None
        self.buf = bytearray()
        self.ring = [0.0] * N
        self.pending = 0
        self.lv = [0.0] * NB
        self.pk = [0.0] * NB
        self.pkt = [0.0] * NB
        self.last_emit = 0.0
        self.last_loud = 0.0
        self.streams = 0
        self.stop_at = None

    def start(self):
        if self.proc:
            return
        try:
            self.proc = subprocess.Popen(
                ["parec", "--device=@DEFAULT_MONITOR@", "--format=s16le",
                 "--rate=%d" % RATE, "--channels=1", "--raw",
                 "--latency-msec=40", "--process-time-msec=20",
                 "--client-name=nerv-psychograph", "--stream-name=harmonics"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                preexec_fn=child_preexec)
            os.set_blocking(self.proc.stdout.fileno(), False)
        except OSError:
            self.proc = None

    def stop(self):
        if not self.proc:
            return
        try:
            self.proc.terminate()
            self.proc.wait(timeout=1)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass
        self.proc = None
        self.buf = bytearray()

    def fd(self):
        return self.proc.stdout.fileno() if self.proc else None

    def read(self):
        try:
            data = os.read(self.proc.stdout.fileno(), 65536)
        except BlockingIOError:
            return
        except OSError:
            data = b""
        if not data:
            self.stop()
            return
        self.buf += data
        n = len(self.buf) // 2
        if n == 0:
            return
        samples = memoryview(bytes(self.buf[:n * 2])).cast("h")
        del self.buf[:n * 2]
        s = list(samples)
        if len(s) >= N:
            self.ring = [float(v) for v in s[-N:]]
        else:
            self.ring = self.ring[len(s):] + [float(v) for v in s]
        self.pending += len(s)
        if self.pending >= HOP:
            self.pending %= HOP
            self.analyse()

    def analyse(self):
        now = time.monotonic()
        x = self.ring
        acc = 0.0
        for v in x:
            acc += v * v
        rms = math.sqrt(acc / N) / 32768.0
        db = 20 * math.log10(rms) if rms > 1e-7 else -140.0
        loud = db > SILENT_DB
        if loud:
            self.last_loud = now
        quiet = now - self.last_loud > 0.6
        if quiet and now - self.last_emit < IDLE_EVERY:
            return
        spec = fft([x[i] * WIN[i] for i in range(N)])
        mags = [abs(c) / NORM for c in spec[:N // 2]]
        best, bestk = 0.0, 0
        for k in range(2, N // 2):
            if mags[k] > best:
                best, bestk = mags[k], k
        for i, (b0, b1) in enumerate(BANDS):
            m = max(mags[b0:b1])
            d = 20 * math.log10(m) if m > 1e-9 else -180.0
            v = (d + TILT[i] + 66.0) / 60.0          # -66 dB .. -6 dB -> 0..1
            v = 0.0 if v < 0 else (1.0 if v > 1 else v)
            if quiet:
                v = 0.0
            # fast attack, stepped release
            self.lv[i] = v if v > self.lv[i] else max(v, self.lv[i] - 0.06)
            if self.lv[i] >= self.pk[i]:
                self.pk[i] = self.lv[i]
                self.pkt[i] = now
            elif now - self.pkt[i] > 0.7:
                self.pk[i] = max(self.lv[i], self.pk[i] - 0.03)
        self.last_emit = now
        state = "Q" if quiet else "A"
        hz = 0.0
        if not quiet and 2 <= bestk < N // 2 - 1:
            a, b, c = mags[bestk - 1], mags[bestk], mags[bestk + 1]
            den = a - 2 * b + c
            off = 0.5 * (a - c) / den if den else 0.0
            hz = (bestk + off) * BIN_HZ
        self.emit(state, db, hz)

    def emit(self, state, db, hz):
        out("H %s %.1f %d %s %s" % (
            state, max(db, -99.0), hz,
            " ".join(str(int(v * 99)) for v in self.lv),
            " ".join(str(int(v * 99)) for v in self.pk)))

    def idle_frame(self):
        # no playback stream: decay whatever is left, then flatline
        now = time.monotonic()
        if now - self.last_emit < IDLE_EVERY:
            return
        self.lv = [0.0] * NB
        self.pk = [max(0.0, p - 0.2) for p in self.pk]
        self.last_emit = now
        self.emit("X", -99.0, 0)


def count_streams():
    try:
        r = subprocess.run(["pactl", "list", "sink-inputs", "short"],
                           capture_output=True, text=True, timeout=2)
        return sum(1 for l in r.stdout.splitlines() if l.strip())
    except Exception:
        return 0


def spawn_subscribe():
    try:
        p = subprocess.Popen(["pactl", "subscribe"], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, preexec_fn=child_preexec)
        os.set_blocking(p.stdout.fileno(), False)
        return p
    except OSError:
        return None


audio = Audio()
sub = None


def shutdown(*_):
    audio.stop()
    if sub:
        try:
            sub.terminate()
        except Exception:
            pass
    os._exit(0)


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)
signal.signal(signal.SIGPIPE, signal.SIG_DFL)


def main():
    global sub
    sub = spawn_subscribe()
    sub_buf = b""
    recount_at = time.monotonic()
    paused = False
    stdin_fd = sys.stdin.fileno() if sys.stdin else None
    stdin_buf = b""
    if stdin_fd is not None:
        try:
            os.set_blocking(stdin_fd, False)
        except OSError:
            stdin_fd = None
    stats_line()  # prime the deltas
    next_stats = time.monotonic() + STATS_EVERY
    while True:
        now = time.monotonic()
        if now >= next_stats:
            line = stats_line()
            if line:
                out(line)
            next_stats = now + (STATS_EVERY_PAUSED if paused else STATS_EVERY)
            if sub is None or sub.poll() is not None:
                sub = spawn_subscribe()
                recount_at = now
        if paused:
            recount_at = None
            audio.stop_at = None
            audio.stop()
        elif recount_at is not None and now >= recount_at:
            recount_at = None
            audio.streams = count_streams()
            if audio.streams > 0:
                audio.stop_at = None
                audio.start()
            elif audio.proc and audio.stop_at is None:
                audio.stop_at = now + 3.0
        if audio.stop_at is not None and now >= audio.stop_at:
            audio.stop_at = None
            if audio.streams == 0:
                audio.stop()
        if not audio.proc and not paused:
            audio.idle_frame()

        fds = []
        if stdin_fd is not None:
            fds.append(stdin_fd)
        if sub and sub.stdout:
            fds.append(sub.stdout.fileno())
        afd = audio.fd()
        if afd is not None:
            fds.append(afd)
        deadline = next_stats
        if recount_at is not None:
            deadline = min(deadline, recount_at)
        if audio.stop_at is not None:
            deadline = min(deadline, audio.stop_at)
        if not audio.proc and not paused:
            deadline = min(deadline, audio.last_emit + IDLE_EVERY)
        timeout = max(0.0, deadline - time.monotonic())
        try:
            ready, _, _ = select.select(fds, [], [], timeout)
        except InterruptedError:
            continue
        for fd in ready:
            if stdin_fd is not None and fd == stdin_fd:
                try:
                    chunk = os.read(fd, 1024)
                except BlockingIOError:
                    continue
                except OSError:
                    chunk = b""
                if not chunk:
                    stdin_fd = None   # HUD closed stdin: keep running unpaused
                    if paused:
                        paused = False
                        recount_at = time.monotonic()
                    continue
                stdin_buf += chunk
                cmds = stdin_buf.split(b"\n")
                stdin_buf = cmds[-1]
                for c in cmds[:-1]:
                    c = c.strip()
                    if c == b"P" and not paused:
                        paused = True
                    elif c == b"R" and paused:
                        paused = False
                        recount_at = time.monotonic()
                        next_stats = min(next_stats, time.monotonic())
                continue
            if afd is not None and fd == afd:
                audio.read()
            elif sub and fd == sub.stdout.fileno():
                try:
                    chunk = os.read(fd, 8192)
                except BlockingIOError:
                    chunk = b"x"
                if not chunk:
                    sub = None
                    continue
                sub_buf += chunk
                lines = sub_buf.split(b"\n")
                sub_buf = lines[-1]
                for l in lines[:-1]:
                    if b"sink-input" in l and (b"'new'" in l or b"'remove'" in l):
                        if recount_at is None:
                            recount_at = time.monotonic() + 0.15


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        shutdown()
