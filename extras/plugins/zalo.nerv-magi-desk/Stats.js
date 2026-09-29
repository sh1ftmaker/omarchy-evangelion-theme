.pragma library
// Parsers for /proc and the CASPER probe. Pure functions: no QML state.

function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v) }

// /proc/stat -> { prev, total, cores[], valid }
function parseStat(text, prev) {
  var lines = String(text || "").split("\n")
  var next = {}, cores = [], total = 0
  var hadPrev = prev && Object.keys(prev).length > 0
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i]
    if (l.indexOf("cpu") !== 0) { if (i > 0) break; else continue }
    var f = l.trim().split(/\s+/)
    var name = f[0], sum = 0, v = []
    for (var j = 1; j <= 8 && j < f.length; j++) { var n = Number(f[j]) || 0; v.push(n); sum += n }
    var idle = (v[3] || 0) + (v[4] || 0)
    next[name] = { idle: idle, total: sum }
    var p = prev ? prev[name] : null
    var frac = 0
    if (p) {
      var dt = sum - p.total, di = idle - p.idle
      frac = dt > 0 ? clamp01(1 - di / dt) : 0
    }
    if (name === "cpu") total = frac
    else cores.push(frac)
  }
  return { prev: next, total: total, cores: cores, valid: hadPrev }
}

// /proc/meminfo -> kB values
function parseMeminfo(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^(\w+):\s+(\d+)/.exec(lines[i])
    if (m) out[m[1]] = Number(m[2])
  }
  var total = out.MemTotal || 0
  var avail = out.MemAvailable !== undefined ? out.MemAvailable : (out.MemFree || 0)
  return {
    total: total,
    used: Math.max(0, total - avail),
    cache: (out.Cached || 0) + (out.SReclaimable || 0),
    swapTotal: out.SwapTotal || 0,
    swapUsed: Math.max(0, (out.SwapTotal || 0) - (out.SwapFree || 0))
  }
}

function num(s) {
  var n = parseFloat(String(s === undefined ? "" : s))
  return isFinite(n) ? n : NaN
}

// gpu.sh line -> object
function parseGpu(text) {
  var line = String(text || "").trim().split("\n")[0] || ""
  var f = line.split("|")
  var src = f[0] || "none"
  if (["nvidia", "amdgpu", "sleep", "none"].indexOf(src) < 0) src = "none"
  return {
    src: src,
    util: num(f[1]) || 0,
    used: num(f[2]) || 0,
    total: num(f[3]) || 0,
    temp: num(f[4]),
    power: num(f[5]),
    name: String(f[6] || "")
  }
}

function pad(n, w) { var s = String(Math.max(0, Math.round(n))); while (s.length < w) s = "0" + s; return s }
function pct(v) { return (v < 0 || isNaN(v)) ? "---%" : pad(v * 100, 3) + "%" }
function gib(kb) { return (kb / 1048576).toFixed(1) }

function uptime(sec) {
  sec = Math.floor(sec || 0)
  var d = Math.floor(sec / 86400); sec -= d * 86400
  var h = Math.floor(sec / 3600); sec -= h * 3600
  var m = Math.floor(sec / 60); var s = sec - m * 60
  return { days: d, clock: pad(h, 2) + ":" + pad(m, 2) + ":" + pad(s, 2) }
}

var HEXD = "0123456789ABCDEF"
function hexStr(n) { var s = ""; for (var i = 0; i < n; i++) s += HEXD[Math.floor(Math.random() * 16)]; return s }
function hexOf(v, w) { var s = Math.max(0, Math.floor(v)).toString(16).toUpperCase(); while (s.length < w) s = "0" + s; return s.slice(-w) }
