import QtQuick
import "Pal.js" as Pal

// PSYCHOGRAPH 心理グラフ: six green-phosphor pilot channels written by a sweep
// head, with phosphor persistence behind the head and an erase gap ahead of it.
// Every trace IS its metric's time series (no synthesized waves):
//   01 CPU  total busy %            (/proc/stat)                          0-100 %
//   02 GPU  busy %                  (nvidia-smi only while the dGPU is awake, else
//                                    iGPU gpu_busy_percent, else SLEEP flat line) 0-100 %
//   03 MEM  used %                  (MemTotal - MemAvailable)             0-100 %
//   04 NET↓ receive rate            (/proc/net/dev, real ifaces)          autoscale B/s
//   05 NET↑ transmit rate                                                  autoscale B/s
//   06 PING TCP connect time to 1.1.1.1:443, one probe / 8 s            autoscale ms
// Autoscaled channels pick a 1-2-5 full scale from the largest value on screen;
// the full scale is printed under each readout (FS ...). A strip's top rule is
// full scale, the dotted midline half scale, the bottom 0 (ticks on the right edge).
//
// Motion (vsync, FrameAnimation): the helper samples once per second; the head
// advances continuously (time based, sub-pixel) and writes one column per px,
// whose value is the smoothstep interpolation between the two samples around
// (now - lag), so the trace passes through every real sample and the readout
// shows exactly the value under the head. The scope is cut into narrow Canvas
// tiles: a column write repaints only the 1-2 tiles it touches (from the sample
// ring), a full-scale change repaints them all once, and the persistence fade is
// each tile's opacity. Covered / hidden: FrameAnimation stops, ~0 cost.
NervFrame {
  id: root

  title: "PSYCHOGRAPH"
  jpTitle: "心理グラフ"
  code: "CH-06 · SWEEP " + sweepSec + "s · 1Hz"
  status: level >= 2 ? "EMERGENCY" : level >= 1 ? "WARNING" : "STABLE"
  statusJp: level >= 2 ? "緊急" : level >= 1 ? "警告" : "安定"
  statusColor: level >= 2 ? Pal.red : level >= 1 ? Pal.amber : Pal.green
  statusLit: level < 2 || blinkOn
  accent: level >= 2 ? Pal.red : Pal.orange

  // ---------------------------------------------------------------- layout
  property bool live: true                      // false while covered / hidden: motion stops
  readonly property int nch: 6
  readonly property int stripY: headerH + 8
  readonly property int stripH: Math.max(12, Math.floor((height - stripY - 27) / nch))
  readonly property int traceX: 94
  readonly property int traceW: Math.max(80, Math.floor(width - traceX - 102))   // 324 at 520 px
  readonly property int readX: traceX + traceW + 8
  readonly property int sweepSec: 18
  readonly property real speed: traceW / sweepSec          // px per second
  readonly property int gap: 14                            // erase gap ahead of the head (px)
  readonly property int tileW: 6                           // Canvas tile width (px)
  readonly property int nTiles: Math.ceil(traceW / tileW)
  readonly property real fadePx: speed * 4.6               // persistence e-fold (4.6 s)
  readonly property real lag: 1.1                          // display delay: the head is always between two samples

  // ---------------------------------------------------------------- state
  property int level: 0
  property bool blinkOn: true
  property bool hasData: false
  property var readouts: ["--", "--", "--", "--", "--", "--"]
  property var subs: ["FS 100%", "FS 100%", "FS 100%", "FS --", "FS --", "FS --"]
  property var headL: [0, 0, 0, 0, 0, 0]        // ink of the column under the head
  property var headY: [NaN, NaN, NaN, NaN, NaN, NaN]   // head dot y (px, strip-local), NaN = none
  property var scales: [100, 100, 100, 10240, 10240, 50]
  property var ecores: []                       // eased per-core load 0..100
  property real headX: 0                        // sub-pixel head position in the trace (px)
  property int headCol: 0                       // last written column
  property int headTile: 0                      // tile under the head (drives the persistence fade)
  property string diskText: "DISK --"
  property real textAcc: 0
  property bool coreOdd: false
  property var pend: ({})                       // tiles touched since the last repaint

  // plain JS state (not bound to by anything)
  property var hist: []                          // [ch][col] raw value; NaN = erased / no data, Infinity = offline
  property var lvls: []                          // [ch][col] ink 0 green, 1 amber, 2 red, 3 dim (asleep)
  property var jit: []                           // [col] phosphor jitter (px)
  property var samples: []                       // recent helper samples {t, v:[6], gs, psi}
  property var headV: [NaN, NaN, NaN, NaN, NaN, NaN]
  property var colTmp: [0, 0, 0, 0, 0, 0]
  property var tgtCores: []
  property real tgtDisk: 0
  property real eDisk: 0
  property bool settled: true
  property real clock: 0
  property string gpuSrc: "s"
  property real memUsed: 0
  property real memTotal: 0
  property int nCores: 0

  readonly property var channels: [
    { pilot: "PILOT 01", name: "CPU", jp: "中央演算" },
    { pilot: "PILOT 02", name: "GPU", jp: "画像演算" },
    { pilot: "PILOT 03", name: "MEM", jp: "記憶領域" },
    { pilot: "PILOT 04", name: "NET↓", jp: "受信" },
    { pilot: "PILOT 05", name: "NET↑", jp: "送信" },
    { pilot: "PILOT 06", name: "PING", jp: "応答遅延" }
  ]
  readonly property string pingHost: "1.1.1.1"   // public resolver (psychograph.py PING_HOST)
  readonly property var inkNames: ["green", "amber", "red", "ash"]
  readonly property var inkCols: [Pal.green, Pal.amber, Pal.red, Pal.ash]

  // (re)allocate the sample ring (on a width change the trace restarts empty)
  function alloc() {
    var h = [], l = [], j = []
    for (var c = 0; c < nch; c++) {
      var a = new Array(traceW), b = new Array(traceW)
      for (var i = 0; i < traceW; i++) { a[i] = NaN; b[i] = 0 }
      h.push(a); l.push(b)
    }
    for (var k = 0; k < traceW; k++) j.push((Math.random() - 0.5) * 0.6)
    hist = h; lvls = l; jit = j
    headX = (clock * speed) % traceW
    headCol = Math.floor(headX)
    repaintAll()
    grid.requestPaint()
  }
  function repaintAll() {
    for (var t = 0; t < tiles.count; t++) { var it = tiles.itemAt(t); if (it) it.requestPaint() }
    pend = ({})
  }
  Component.onCompleted: alloc()
  onTraceWChanged: alloc()

  // ---------------------------------------------------------------- data
  // one stats sample from the helper: S cpu mem memMiB totMiB psi rx tx disk gpu gsrc ping n c0..
  function push(p) {
    var gs = p[10]
    var ping = +p[11]
    var s = {
      t: clock,
      v: [+p[1], gs === "s" ? 0 : +p[9], +p[2], +p[6], +p[7],
          ping === -1 ? Infinity : ping < 0 ? NaN : ping],
      gs: gs, psi: +p[5]
    }
    var n = +p[12]
    var cs = []
    for (var k = 0; k < n; k++) cs.push(+p[13 + k])
    tgtCores = cs
    tgtDisk = +p[8]
    gpuSrc = gs; memUsed = +p[3]; memTotal = +p[4]; nCores = n
    var snap = !hasData || !live || !visible      // first sample / covered: no interpolation, take it
    hasData = true
    settled = false
    if (ecores.length !== cs.length) ecores = cs.slice()
    if (snap) {
      s.t = clock - lag                           // shown at once; the next live sample interpolates from it
      samples = [s]
      ecores = cs.slice(); eDisk = tgtDisk
      diskText = "DISK R+W " + Pal.fmtRate(eDisk) + "/s"
      for (var z = 0; z < cs.length; z++) { var ci = cores.itemAt(z); if (ci) ci.load = Math.max(0, Math.min(1, cs[z] / 100)) }
      headV = s.v.slice()
      updateText()
    } else {
      var a = samples
      a.push(s)
      while (a.length > 4) a.shift()
    }
    rescale()
  }

  // every channel's value at clock time T (smoothstep between the bracketing samples);
  // returns the nearer sample (for its flags) or null before any data
  function sampleAt(T, out) {
    var a = samples, n = a.length
    if (n === 0) return null
    var i = n - 1
    while (i > 0 && a[i].t > T) i--
    var s0 = a[i]
    if (i === n - 1 || T <= s0.t) {               // past the newest (late sample) / before the oldest: hold
      for (var c = 0; c < nch; c++) out[c] = s0.v[c]
      return s0
    }
    var s1 = a[i + 1]
    var span = s1.t - s0.t
    var u = span > 0 ? Math.max(0, Math.min(1, (T - s0.t) / span)) : 1
    u = u * u * (3 - 2 * u)
    for (var q = 0; q < nch; q++) {
      var x = s0.v[q], y = s1.v[q]
      if (x === Infinity || y === Infinity) out[q] = Infinity          // failed probe: offline
      else if (x !== x || y !== y) out[q] = u < 0.5 ? x : y
      else out[q] = x + (y - x) * u
    }
    return u < 0.5 ? s0 : s1
  }

  function levelOf(c, v, s) {
    if (v !== v) return 0
    switch (c) {
    case 0: return v > 85 ? 2 : v > 60 ? 1 : 0
    case 1: return s && s.gs === "s" ? 3 : v > 90 ? 2 : v > 70 ? 1 : 0
    case 2: return (v > 90 || (s && s.psi > 10)) ? 2 : (v > 75 || (s && s.psi > 1)) ? 1 : 0
    case 5: return v === Infinity ? 2 : v > 400 ? 2 : v > 150 ? 1 : 0
    default: return 0
    }
  }

  // 1-2-5 full scale >= x: ms 50, 100, 200, 500 ...; bytes 10K .. 500K, 1M .. 500M, 1G ..
  function nice(x, bytes, floor) {
    x = Math.max(x, floor)
    var m = [1, 2, 5, 10, 20, 50, 100, 200, 500]
    var units = bytes ? [1024, 1048576, 1073741824] : [1, 1000, 1000000]
    for (var u = 0; u < units.length; u++)
      for (var i = 0; i < m.length; i++) if (m[i] * units[u] >= x) return m[i] * units[u]
    return x
  }

  // autoscale NET / PING from the largest finite value on screen (+ the newest sample)
  function rescale() {
    var sc = scales.slice(), changed = false
    for (var c = 3; c < nch; c++) {
      var mx = 0, h = hist[c]
      if (!h) continue
      for (var i = 0; i < h.length; i++) { var v = h[i]; if (v === v && v !== Infinity && v > mx) mx = v }
      var last = samples.length ? samples[samples.length - 1].v[c] : 0
      if (last === last && last !== Infinity && last > mx) mx = last
      var f = c === 5 ? nice(mx, false, 50) : nice(mx, true, 10240)
      if (f !== sc[c]) { sc[c] = f; changed = true }
    }
    if (changed) { scales = sc; repaintAll() }
    updateSubs()
  }

  function updateSubs() {
    var gsn = gpuSrc === "d" ? "dGPU" : gpuSrc === "i" ? "iGPU" : "NO GPU AWAKE"
    var s = [
      "FS 100% · " + (nCores || "--") + " THR",
      "FS 100% · " + gsn,
      "FS 100% · " + (memTotal > 0 ? (memUsed / 1024).toFixed(1) + "/" + (memTotal / 1024).toFixed(0) + "G" : "--"),
      "FS " + Pal.fmtRate(scales[3]) + "/s",
      "FS " + Pal.fmtRate(scales[4]) + "/s",
      "FS " + scales[5] + "ms · " + pingHost
    ]
    if (s.join("|") !== subs.join("|")) subs = s
  }

  function fmtValue(c, v) {
    if (c === 1 && gpuSrc === "s") return "SLEEP 休止"
    if (c === 5) return v === Infinity ? "OFFLINE 切断" : v !== v ? "PROBING" : v.toFixed(v < 100 ? 1 : 0) + "ms"
    if (v !== v) return "--"
    if (c === 3 || c === 4) return Pal.fmtRate(v) + "/s"
    return v.toFixed(1) + "%"
  }

  // readouts = the values under the head (what the trace is drawing right now)
  function updateText() {
    var r = []
    for (var c = 0; c < nch; c++) r.push(fmtValue(c, headV[c]))
    if (r.join("|") !== readouts.join("|")) readouts = r
    var L = [], mx = 0
    var s = samples.length ? samples[samples.length - 1] : null
    for (var q = 0; q < nch; q++) {
      var l = levelOf(q, headV[q], s)
      L.push(l)
      if (l < 3) mx = Math.max(mx, l)
    }
    if (L.join() !== headL.join()) headL = L
    if (mx !== level) level = mx
  }

  // strip-local y (px) of value v on channel c (full scale 2 px below the top rule)
  function yOf(c, v) {
    var sh = stripH
    if (v === Infinity) return 2
    var f = v / scales[c]
    f = f < 0 ? 0 : (f > 1 ? 1 : f)
    return sh - 2 - f * (sh - 4)
  }

  // ease the core strip and the disk readout toward the latest sample (frame-time based)
  function ease(dt) {
    if (settled) return
    var moving = false
    var kd = 1 - Math.exp(-dt / 0.3)
    var dd = tgtDisk - eDisk
    if (Math.abs(dd) > Math.max(1, tgtDisk * 0.004)) { eDisk += dd * kd; moving = true } else eDisk = tgtDisk
    // cores: 8 px bars, eased on every other frame
    coreOdd = !coreOdd
    var ec = ecores, tc = tgtCores
    var kc = 1 - Math.exp(-2 * dt / 0.3)
    for (var q = 0; q < ec.length && q < tc.length; q++) {
      var dq = tc[q] - ec[q]
      if (dq === 0) continue
      moving = true
      if (coreOdd) continue
      if (Math.abs(dq) > 0.3) ec[q] += dq * kc; else ec[q] = tc[q]
      var it = cores.itemAt(q)
      if (it) it.load = Math.max(0, Math.min(1, ec[q] / 100))
    }
    if (!moving) settled = true
  }

  function tileOf(col) { return Math.floor((((col % traceW) + traceW) % traceW) / tileW) }

  // write column k (the data at display time T) and erase the column `gap` ahead
  function writeCol(k, T, dirty) {
    var W = traceW, e = (k + gap) % W
    var v = colTmp
    var s = sampleAt(T, v)
    for (var c = 0; c < nch; c++) {
      hist[c][k] = s ? v[c] : NaN
      lvls[c][k] = s ? levelOf(c, v[c], s) : 0
    }
    // the new segment (k-1 -> k) lives in k's tile, and in the left tile at a boundary
    dirty[tileOf(k)] = true
    if (k % tileW === 0 && k > 0) dirty[tileOf(k - 1)] = true
    // erase a whole tile at once when the gap front enters it (one repaint per tile)
    if (e % tileW === 0) {
      var e1 = Math.min(e + tileW, W)
      for (var c2 = 0; c2 < nch; c2++) for (var x = e; x < e1; x++) hist[c2][x] = NaN
      dirty[tileOf(e)] = true
    }
  }

  // driven by the plugin's frame() signal (the wall host's shared vsync clock when embedded)
  property var ticker: null
  Connections {
    target: root.ticker
    enabled: root.live && root.visible
    function onFrame(frameTime, currentFrame) {
      var dt = Math.min(Math.max(frameTime, 0), 0.1)
      root.clock += dt
      var W = root.traceW
      if (root.hist.length === 0 || root.hist[0].length !== W) return
      var hx = (root.clock * root.speed) % W
      var col = Math.floor(hx)
      var last = root.headCol
      if (col !== last) {
        var dirty = root.pend
        var steps = ((col - last) % W + W) % W
        if (steps > W / 2) steps = 1                // clock jump: just continue
        var T = root.clock - root.lag
        for (var s = 0; s < steps; s++) {
          last = (last + 1) % W
          root.writeCol(last, T - (steps - 1 - s) / root.speed, dirty)
        }
        root.headCol = last
        var ht = Math.floor(last / root.tileW)
        if (ht !== root.headTile) root.headTile = ht
        var hy = [], hv = root.headV
        for (var c = 0; c < root.nch; c++) {
          var v = root.hist[c][last]
          hv[c] = v
          hy.push(v === v ? root.yOf(c, v) + root.jit[last] : NaN)
        }
        root.headY = hy
        // repaint the touched tiles every second column (the head dots lead the line)
        if (last % 2 === 1 || steps > 1) {
          for (var t in dirty) { var it = tiles.itemAt(+t); if (it) it.requestPaint() }
          root.pend = ({})
        }
      }
      root.headX = hx
      root.ease(dt)
      root.textAcc += dt
      if (root.textAcc >= 0.1) {                    // readout digits tick at 10 Hz
        root.textAcc = 0
        root.updateText()
        var dk = "DISK R+W " + Pal.fmtRate(root.eDisk) + "/s"
        if (dk !== root.diskText) root.diskText = dk
      }
    }
  }

  Timer {
    interval: 400
    repeat: true
    running: root.level >= 2 && root.visible && root.live
    onTriggered: root.blinkOn = !root.blinkOn
    onRunningChanged: if (!running) root.blinkOn = true
  }

  // ---------------------------------------------------------------- static graticule
  // strip top rule = full scale, dotted midline = half scale, bottom = 0
  onStripHChanged: { grid.requestPaint(); repaintAll() }
  Canvas {
    id: grid
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var x0 = root.traceX, w = root.traceW, sh = root.stripH
      for (var c = 0; c < root.nch; c++) {
        var y = root.stripY + c * sh
        ctx.fillStyle = Pal.rgba("green", 0.16)
        ctx.fillRect(x0, y, w, 1)
        ctx.fillStyle = Pal.rgba("green", 0.14)
        for (var x = x0; x < x0 + w; x += 6) ctx.fillRect(x, y + sh / 2, 2, 1)
        ctx.fillStyle = Pal.rgba("orange", 0.5)
        ctx.fillRect(8, y + sh - 1, 78, 1)
        // scale ticks on the trace's right edge: FS, 1/2, 0
        ctx.fillStyle = Pal.rgba("green", 0.6)
        ctx.fillRect(x0 + w + 1, y + 2, 4, 1)
        ctx.fillRect(x0 + w + 1, y + Math.round(sh / 2), 2, 1)
        ctx.fillRect(x0 + w + 1, y + sh - 2, 4, 1)
      }
      ctx.fillStyle = Pal.rgba("green", 0.16)
      ctx.fillRect(x0, root.stripY + root.nch * sh, w, 1)
      for (var d = 0; d <= 12; d++) {
        var gx = x0 + Math.round(d * w / 12)
        ctx.fillStyle = Pal.rgba("green", d % 3 === 0 ? 0.18 : 0.08)
        ctx.fillRect(gx, root.stripY, 1, root.nch * sh)
      }
      ctx.strokeStyle = Pal.rgba("green", 0.45)
      ctx.lineWidth = 1
      ctx.strokeRect(x0 - 0.5, root.stripY - 0.5, w + 1, root.nch * sh + 1)
      // time ticks under the scope: 1.5 s apart, major every 4.5 s
      var yb = root.stripY + root.nch * sh + 1
      ctx.fillStyle = Pal.rgba("green", 0.5)
      for (var t = 0; t <= 12; t++) {
        var tx = x0 + Math.round(t * w / 12)
        ctx.fillRect(tx, yb, 1, t % 3 === 0 ? 4 : 2)
      }
    }
  }

  // ---------------------------------------------------------------- traces (tiles)
  Repeater {
    id: tiles
    model: root.nTiles
    delegate: Canvas {
      id: tile
      required property int index
      readonly property int t0: index * root.tileW
      readonly property int t1: Math.min(t0 + root.tileW, root.traceW)
      x: root.traceX + t0
      y: root.stripY
      width: Math.max(1, t1 - t0)
      height: root.nch * root.stripH
      // phosphor persistence: age of this tile behind the head (updates per written column)
      opacity: {
        var W = root.traceW
        var age = ((root.headTile * root.tileW - t0) % W + W) % W
        return 0.3 + 0.7 * Math.exp(-Math.max(0, age) / root.fadePx)
      }
      onHeightChanged: requestPaint()
      onWidthChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var H = root.hist, LV = root.lvls, J = root.jit, W = root.traceW
        if (H.length === 0 || H[0].length !== W) return
        var sh = root.stripH
        var k0 = Math.max(t0, 1), k1 = Math.min(t1, W - 1)
        for (var pass = 0; pass < 2; pass++) {
          ctx.lineWidth = pass === 0 ? 3 : 1
          for (var c = 0; c < root.nch; c++) {
            var cy = c * sh
            var h = H[c], lv = LV[c]
            var open = false, cur = -1
            for (var k = k0; k <= k1; k++) {
              var a = h[k - 1], b = h[k]
              if (a !== a || b !== b) {                 // NaN: erased / never written / no probe yet
                if (open) { ctx.stroke(); open = false }
                continue
              }
              var col = (lv[k - 1] === 3 || lv[k] === 3) ? 3 : Math.max(lv[k - 1], lv[k])
              if (!open || col !== cur) {
                if (open) ctx.stroke()
                cur = col
                ctx.strokeStyle = Pal.rgba(root.inkNames[col], pass === 0 ? 0.16 : (col === 3 ? 0.7 : 1))
                ctx.beginPath()
                ctx.moveTo(k - 1 - t0 + 0.5, cy + root.yOf(c, a) + J[k - 1])
                open = true
              }
              ctx.lineTo(k - t0 + 0.5, cy + root.yOf(c, b) + J[k])
            }
            if (open) ctx.stroke()
          }
        }
      }
    }
  }

  // write head: beam, erase-gap shading and per-channel head dots move as one
  // group (one x binding per frame), clipped to the scope; the gap wraps.
  Item {
    x: root.traceX; y: root.stripY
    width: root.traceW; height: root.nch * root.stripH
    clip: true
    Item {
      x: root.headX
      width: 1; height: parent.height
      Rectangle {
        width: 1; height: parent.height
        antialiasing: true
        color: Pal.green
        opacity: 0.85
      }
      Rectangle {
        x: 1; width: root.gap; height: parent.height
        antialiasing: true
        color: Pal.green
        opacity: 0.08
      }
      Repeater {
        model: root.nch
        delegate: Rectangle {
          required property int index
          readonly property real hy: root.headY[index]
          x: -1.5
          y: index * root.stripH + (hy === hy ? hy : 0) - 1.5
          width: 3; height: 3
          antialiasing: true
          color: root.inkCols[root.headL[index]]
          visible: root.hasData && hy === hy
        }
      }
    }
    Rectangle {                                   // wrapped part of the erase gap
      width: Math.max(0, root.headX + 1 + root.gap - root.traceW)
      height: parent.height
      antialiasing: true
      color: Pal.green
      opacity: 0.08
      visible: width > 0
    }
  }

  // ---------------------------------------------------------------- per-core load strip (eased)
  Item {
    id: coreMap
    readonly property int n: root.ecores.length
    readonly property real cw: Math.min(14, (root.traceX + root.traceW - 150) / Math.max(1, n))
    x: 150
    y: root.stripY + root.nch * root.stripH + 8
    Repeater {
      id: cores
      model: coreMap.n
      delegate: Item {
        required property int index
        // initial value; afterwards pushed by ease()
        property real load: Math.max(0, Math.min(1, (root.ecores[index] || 0) / 100))
        x: index * coreMap.cw
        width: coreMap.cw - 2
        height: 8
        Rectangle { anchors.fill: parent; color: Pal.green; opacity: 0.1 }
        Rectangle {
          width: parent.width
          height: Math.max(1, 8 * parent.load)
          y: 8 - height
          antialiasing: true
          color: parent.load > 0.95 ? Pal.red : parent.load > 0.75 ? Pal.amber : Pal.green
          opacity: 0.35 + 0.65 * parent.load
        }
      }
    }
  }

  // ---------------------------------------------------------------- labels + readouts
  Repeater {
    model: root.nch
    delegate: Item {
      id: lab
      required property int index
      readonly property var ch: root.channels[index]
      readonly property int lvl: root.headL[index]
      x: 9
      y: root.stripY + index * root.stripH
      width: 80
      height: root.stripH

      Text {
        y: 1
        text: lab.ch.pilot
        color: Pal.ash
        font.family: Pal.mono
        font.weight: Font.DemiBold
        font.pixelSize: 7
        font.letterSpacing: 1.4
      }
      Row {
        y: 9
        spacing: 4
        Text {
          text: lab.ch.name
          color: lab.lvl === 2 ? Pal.red : lab.lvl === 1 ? Pal.amber : Pal.orange
          font.family: Pal.mono
          font.weight: Font.Bold
          font.pixelSize: 9
          font.letterSpacing: 1.4
        }
        Text {
          anchors.baseline: parent.children[0].baseline
          text: lab.ch.jp
          color: Pal.orange
          opacity: 0.75
          font.family: Pal.jp
          font.weight: Font.Bold
          font.pixelSize: 8
        }
      }
      // value under the head
      Text {
        x: root.readX - 9
        y: -1
        text: root.readouts[lab.index]
        color: root.inkCols[lab.lvl]
        font.family: Pal.mono
        font.weight: Font.Bold
        font.pixelSize: 10
        font.letterSpacing: 0.8
      }
      // full scale of the strip (+ source / context)
      Text {
        x: root.readX - 9
        y: root.stripH - 10
        text: root.subs[lab.index]
        color: Pal.green
        opacity: 0.6
        font.family: Pal.mono
        font.weight: Font.DemiBold
        font.pixelSize: 7
        font.letterSpacing: 0.5
      }
    }
  }

  // footer: per-core strip caption + disk throughput
  Row {
    x: 9
    y: root.stripY + root.nch * root.stripH + 6
    spacing: 4
    Text {
      text: "CORES"
      color: Pal.orange
      font.family: Pal.mono
      font.weight: Font.Bold
      font.pixelSize: 8
      font.letterSpacing: 1.4
    }
    Text {
      text: "論理核 ×" + root.ecores.length
      color: Pal.orange
      opacity: 0.75
      font.family: Pal.jp
      font.weight: Font.Bold
      font.pixelSize: 8
    }
  }
  Text {
    x: root.readX
    y: root.stripY + root.nch * root.stripH + 6
    text: root.hasData ? root.diskText : "解析中…"
    color: Pal.green
    opacity: 0.8
    font.family: Pal.mono
    font.weight: Font.DemiBold
    font.pixelSize: 7
    font.letterSpacing: 0.8
  }
}
