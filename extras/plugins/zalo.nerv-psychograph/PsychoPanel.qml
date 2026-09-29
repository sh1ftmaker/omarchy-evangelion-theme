import QtQuick
import "Pal.js" as Pal

// PSYCHOGRAPH 心理グラフ: six green-phosphor pilot channels written by a sweep
// head, with phosphor persistence behind the head and an erase gap ahead of it.
// Calm machine = calm traces; load drives the amplitude and turns the ink amber / red.
//
// Motion (vsync, FrameAnimation): the head advances continuously (time based,
// sub-pixel) and writes one synthesized EEG sample per 1 px column; the sample
// amplitude comes from the channel value, which eases toward the latest 1 s
// stats sample every frame. The scope is cut into narrow Canvas tiles: a column
// write repaints only the 1-2 tiles it touches (from the sample ring), and the
// persistence fade is each tile's opacity (age of the tile behind the head), so
// nothing large is rasterised per frame. Readout numbers, meters and the core
// map ease toward new samples. Covered / hidden: FrameAnimation stops, ~0 cost.
NervFrame {
  id: root

  title: "PSYCHOGRAPH"
  jpTitle: "心理グラフ"
  code: "CH-06 · SWEEP " + sweepSec + "s"
  status: level >= 2 ? "EMERGENCY" : level >= 1 ? "WARNING" : "STABLE"
  statusJp: level >= 2 ? "緊急" : level >= 1 ? "警告" : "安定"
  statusColor: level >= 2 ? Pal.red : level >= 1 ? Pal.amber : Pal.green
  statusLit: level < 2 || blinkOn
  accent: level >= 2 ? Pal.red : Pal.orange

  // ---------------------------------------------------------------- layout
  // Derived from the frame size (520 x 190 at the reference wall rect): the six
  // strips share the height, the trace takes the width left of the readouts.
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
  readonly property real ampPx: stripH / 2 - 2.5

  // ---------------------------------------------------------------- state
  property int level: 0
  property bool blinkOn: true
  property bool hasData: false
  property var curL: [0, 0, 0, 0, 0, 0]
  property var readouts: ["--", "--", "--", "--", "--", "--"]
  property var ev: [0, 0, 0, 0, 0, 0]          // eased channel values 0..1 (meters, amplitude)
  property var ecores: []                       // eased per-core load 0..100
  property real headX: 0                        // sub-pixel head position in the trace (px)
  property int headCol: 0                       // last written column
  property int headTile: 0                      // tile under the head (drives the persistence fade)
  property string syncText: "SYNC --"
  property real textAcc: 0
  property bool coreOdd: false
  property var pend: ({})                       // tiles touched since the last repaint
  property var headY: [0, 0, 0, 0, 0, 0]        // last written sample per channel (-1..1)

  // plain JS state (not bound to by anything)
  property var hist: []                          // [ch][col] sample -1..1, NaN = erased
  property var lvls: []                          // [ch][col] level 0..2
  property var tgtV: [0, 0, 0, 0, 0, 0]
  property var tgtRaw: [0, 0, 0, 0, 0, 0, 0]     // cpu cmax mem psi rx tx disk
  property var eRaw: [0, 0, 0, 0, 0, 0, 0]
  property var tgtCores: []
  property bool settled: true
  property real clock: 0

  readonly property var channels: [
    { pilot: "PILOT 01", name: "CPU", jp: "中央演算" },
    { pilot: "PILOT 02", name: "CORE", jp: "最大負荷" },
    { pilot: "PILOT 03", name: "MEM", jp: "記憶圧力" },
    { pilot: "PILOT 04", name: "NET▼", jp: "受信" },
    { pilot: "PILOT 05", name: "NET▲", jp: "送信" },
    { pilot: "PILOT 06", name: "DISK", jp: "入出力" }
  ]
  readonly property var inkNames: ["green", "amber", "red"]
  readonly property var inkCols: [Pal.green, Pal.amber, Pal.red]

  // (re)allocate the sample ring (on a width change the trace restarts empty)
  function alloc() {
    var h = [], l = []
    for (var c = 0; c < nch; c++) {
      var a = new Array(traceW), b = new Array(traceW)
      for (var i = 0; i < traceW; i++) { a[i] = NaN; b[i] = 0 }
      h.push(a); l.push(b)
    }
    hist = h; lvls = l
    headX = (clock * speed) % traceW
    headCol = Math.floor(headX)
    for (var t = 0; t < tiles.count; t++) { var it = tiles.itemAt(t); if (it) it.requestPaint() }
    grid.requestPaint()
  }
  Component.onCompleted: alloc()
  onTraceWChanged: alloc()

  function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
  function logNorm(bytes, decades) { return clamp01(Math.log(Math.max(bytes, 1) / 1024) / Math.LN10 / decades) }

  // one stats sample from the helper: S cpu cmax cavg mem psi rx tx disk n c0..
  function push(p) {
    var cpu = +p[1], cmax = +p[2], mem = +p[4], psi = +p[5]
    var rx = +p[6], tx = +p[7], disk = +p[8], n = +p[9]
    var v = [cpu / 100, cmax / 100, mem / 100, logNorm(rx, 5), logNorm(tx, 5), logNorm(disk, 6)]
    var L = [
      cpu > 85 ? 2 : cpu > 60 ? 1 : 0,
      cmax > 97 ? 2 : cmax > 80 ? 1 : 0,
      (mem > 90 || psi > 10) ? 2 : (mem > 75 || psi > 1) ? 1 : 0,
      v[3] > 0.88 ? 2 : v[3] > 0.7 ? 1 : 0,
      v[4] > 0.88 ? 2 : v[4] > 0.7 ? 1 : 0,
      v[5] > 0.88 ? 2 : v[5] > 0.72 ? 1 : 0
    ]
    tgtV = v
    tgtRaw = [cpu, cmax, mem, psi, rx, tx, disk]
    var cs = []
    for (var k = 0; k < n; k++) cs.push(+p[10 + k])
    if (ecores.length !== cs.length) ecores = cs.slice()
    tgtCores = cs
    curL = L
    var mx = 0
    // one pegged core is normal: it can raise WARNING, never EMERGENCY
    for (var j = 0; j < nch; j++) mx = Math.max(mx, j === 1 ? Math.min(L[j], 1) : L[j])
    level = mx
    var snap = !hasData || !live || !visible      // first sample / covered: no easing, take it
    hasData = true
    settled = false
    if (snap) {
      ev = v.slice(); eRaw = tgtRaw.slice(); ecores = cs.slice()
      readouts = fmtReadouts(eRaw)
      syncText = "SYNC " + (100 - v[0] * 100).toFixed(1)
      for (var q = 0; q < nch; q++) { var mi = meters.itemAt(q); if (mi) mi.val = v[q] }
      for (var z = 0; z < cs.length; z++) { var ci = cores.itemAt(z); if (ci) ci.load = Math.max(0, Math.min(1, cs[z] / 100)) }
    }
  }

  function fmtReadouts(r) {
    return [
      r[0].toFixed(1) + "%",
      Math.round(r[1]) + "%",
      Math.round(r[2]) + "%" + (tgtRaw[3] >= 0.1 ? " P" + r[3].toFixed(0) : ""),
      Pal.fmtRate(r[4]) + "/s",
      Pal.fmtRate(r[5]) + "/s",
      Pal.fmtRate(r[6]) + "/s"
    ]
  }

  // ease meters / readouts / core map toward the latest sample (exponential, frame-time based)
  // The eased values live in plain arrays and are pushed straight into the meter /
  // core items (no array-property rebinding per frame); text readouts tick at ~20 Hz.
  function ease(dt) {
    if (settled) return
    var k = 1 - Math.exp(-dt / 0.3)
    var moving = false
    var e = ev
    for (var c = 0; c < nch; c++) {
      var d = tgtV[c] - e[c]
      if (d === 0) continue
      if (Math.abs(d) > 0.0015) { e[c] += d * k; moving = true } else e[c] = tgtV[c]
      var m = meters.itemAt(c)
      if (m) m.val = e[c]
    }
    var r = eRaw
    for (var i = 0; i < r.length; i++) {
      var dr = tgtRaw[i] - r[i]
      if (Math.abs(dr) > Math.max(0.05, Math.abs(tgtRaw[i]) * 0.004)) { r[i] += dr * k; moving = true } else r[i] = tgtRaw[i]
    }
    // core map: 8 px bars, eased on every other frame
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
    textAcc += dt
    if (textAcc >= 0.1 || !moving) {                  // readout digits tick at 10 Hz
      textAcc = 0
      var s = fmtReadouts(r)
      if (s.join("|") !== readouts.join("|")) readouts = s
      var sy = "SYNC " + (100 - e[0] * 100).toFixed(1)
      if (sy !== syncText) syncText = sy
    }
    if (!moving) settled = true
  }

  // synthesized EEG sample for channel c at time t, amplitude from the eased value
  function synth(c, t, v) {
    var amp = 0.06 + 0.9 * Math.pow(v, 0.8)
    var w = 0.55 * Math.sin(6.2832 * (0.85 + c * 0.13) * t + c * 1.9)
          + 0.30 * Math.sin(6.2832 * (2.9 + c * 0.37) * t + c * 0.7)
          + 0.35 * (Math.random() - 0.5)
    if (v > 0.55 && Math.random() < (v - 0.55) * 0.9) w = (Math.random() < 0.5 ? -1 : 1) * (0.8 + 0.2 * Math.random())
    var y = w * amp
    return y < -1 ? -1 : (y > 1 ? 1 : y)
  }

  function tileOf(col) { return Math.floor((((col % traceW) + traceW) % traceW) / tileW) }

  // write column k and erase the column `gap` ahead; collects touched tiles in `dirty`
  function writeCol(k, dirty) {
    var W = traceW, e = (k + gap) % W
    for (var c = 0; c < nch; c++) {
      hist[c][k] = synth(c, clock, ev[c])
      lvls[c][k] = curL[c]
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
        for (var s = 0; s < steps; s++) {
          last = (last + 1) % W
          root.writeCol(last, dirty)
        }
        root.headCol = last
        var ht = Math.floor(last / root.tileW)
        if (ht !== root.headTile) root.headTile = ht
        var hy = []
        for (var c = 0; c < root.nch; c++) hy.push(root.hist[c][last])
        root.headY = hy
        // repaint the touched tiles every second column (the head dots lead the line)
        if (last % 2 === 1 || steps > 1) {
          for (var t in dirty) { var it = tiles.itemAt(+t); if (it) it.requestPaint() }
          root.pend = ({})
        }
      }
      root.headX = hx
      root.ease(dt)
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
  onStripHChanged: grid.requestPaint()
  Canvas {
    id: grid
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var x0 = root.traceX, w = root.traceW
      for (var c = 0; c < root.nch; c++) {
        var y = root.stripY + c * root.stripH
        ctx.fillStyle = Pal.rgba("green", 0.16)
        ctx.fillRect(x0, y, w, 1)
        ctx.fillStyle = Pal.rgba("green", 0.14)
        for (var x = x0; x < x0 + w; x += 6) ctx.fillRect(x, y + root.stripH / 2, 2, 1)
        ctx.fillStyle = Pal.rgba("orange", 0.5)
        ctx.fillRect(8, y + root.stripH - 1, 78, 1)
        // meter ghosts
        ctx.fillStyle = Pal.rgba("green", 0.1)
        for (var sgi = 0; sgi < 10; sgi++) ctx.fillRect(root.readX + sgi * 7.4, y + root.stripH - 7, 6, 3)
      }
      ctx.fillStyle = Pal.rgba("green", 0.16)
      ctx.fillRect(x0, root.stripY + root.nch * root.stripH, w, 1)
      for (var d = 0; d <= 12; d++) {
        var gx = x0 + Math.round(d * w / 12)
        ctx.fillStyle = Pal.rgba("green", d % 3 === 0 ? 0.18 : 0.08)
        ctx.fillRect(gx, root.stripY, 1, root.nch * root.stripH)
      }
      ctx.strokeStyle = Pal.rgba("green", 0.45)
      ctx.lineWidth = 1
      ctx.strokeRect(x0 - 0.5, root.stripY - 0.5, w + 1, root.nch * root.stripH + 1)
      var yb = root.stripY + root.nch * root.stripH + 1
      ctx.fillStyle = Pal.rgba("green", 0.5)
      for (var t = 0; t <= 48; t++) {
        var tx = x0 + Math.round(t * w / 48)
        ctx.fillRect(tx, yb, 1, t % 4 === 0 ? 4 : 2)
      }
      // core map ghosts are per-item below
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
        return 0.2 + 0.8 * Math.exp(-Math.max(0, age) / root.fadePx)
      }
      onHeightChanged: requestPaint()
      onWidthChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var H = root.hist, LV = root.lvls, W = root.traceW
        if (H.length === 0 || H[0].length !== W) return
        var amp = root.ampPx, sh = root.stripH
        var k0 = Math.max(t0, 1), k1 = Math.min(t1, W - 1)
        for (var pass = 0; pass < 2; pass++) {
          ctx.lineWidth = pass === 0 ? 3 : 1
          for (var c = 0; c < root.nch; c++) {
            var cy = c * sh + sh / 2
            var h = H[c], lv = LV[c]
            var open = false, cur = -1
            for (var k = k0; k <= k1; k++) {
              var a = h[k - 1], b = h[k]
              if (a !== a || b !== b) {                 // NaN: erased / never written
                if (open) { ctx.stroke(); open = false }
                continue
              }
              var col = Math.max(lv[k - 1], lv[k])
              if (!open || col !== cur) {
                if (open) ctx.stroke()
                cur = col
                ctx.strokeStyle = Pal.rgba(root.inkNames[col], pass === 0 ? 0.16 : 1)
                ctx.beginPath()
                ctx.moveTo(k - 1 - t0 + 0.5, cy - a * amp)
                open = true
              }
              ctx.lineTo(k - t0 + 0.5, cy - b * amp)
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
          y: index * root.stripH + root.stripH / 2 - (hy === hy ? hy : 0) * root.ampPx - 1.5
          width: 3; height: 3
          antialiasing: true
          color: root.inkCols[root.curL[index]]
          visible: root.hasData
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

  // ---------------------------------------------------------------- readout meters (10 segments, eased)
  // Eased fill in three colour zones (segments 0-6 level ink, 7-8 amber, 9 red);
  // the segment gaps are knocked out by the static mask canvas above them.
  Repeater {
    id: meters
    model: root.nch
    delegate: Item {
      id: mrow
      required property int index
      property real val: 0                       // eased 0..1, pushed by ease()
      readonly property real w: val * 74 - 1.1   // lit extent (segment i spans 7.4 i .. 7.4 i + 6)
      x: root.readX
      y: root.stripY + index * root.stripH + root.stripH - 7
      opacity: 0.95
      Rectangle {
        width: Math.max(0, Math.min(mrow.w, 50.4)); height: 3
        color: root.inkCols[root.curL[mrow.index]]
        visible: width > 0
      }
      Rectangle {
        x: 51.8; width: Math.max(0, Math.min(mrow.w - 51.8, 13.4)); height: 3
        color: Pal.amber
        visible: width > 0
      }
      Rectangle {
        x: 66.6; width: Math.max(0, Math.min(mrow.w - 66.6, 6)); height: 3
        color: Pal.red
        visible: width > 0
      }
    }
  }
  Canvas {
    id: meterMask
    x: root.readX; y: root.stripY
    width: 76; height: root.nch * root.stripH
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = "rgba(5,4,3,0.92)"
      for (var c = 0; c < root.nch; c++)
        for (var i = 0; i < 9; i++) ctx.fillRect(i * 7.4 + 6, c * root.stripH + root.stripH - 7, 1.4, 3)
    }
  }

  // ---------------------------------------------------------------- core map (eased)
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

  // ---------------------------------------------------------------- labels
  Repeater {
    model: root.nch
    delegate: Item {
      id: lab
      required property int index
      readonly property var ch: root.channels[index]
      readonly property int lvl: root.curL[index]
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
          color: lab.lvl >= 2 ? Pal.red : lab.lvl >= 1 ? Pal.amber : Pal.orange
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
      Text {
        x: root.readX - 9
        y: 2
        text: root.readouts[lab.index]
        color: lab.lvl >= 2 ? Pal.red : lab.lvl >= 1 ? Pal.amber : Pal.green
        font.family: Pal.mono
        font.weight: Font.Bold
        font.pixelSize: 10
        font.letterSpacing: 0.8
      }
    }
  }

  // footer: core map caption
  Row {
    x: 9
    y: root.stripY + root.nch * root.stripH + 6
    spacing: 4
    Text {
      text: "CORE MAP"
      color: Pal.orange
      font.family: Pal.mono
      font.weight: Font.Bold
      font.pixelSize: 8
      font.letterSpacing: 1.4
    }
    Text {
      text: "神経接続 ×" + root.ecores.length
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
    text: root.hasData ? root.syncText : "解析中…"
    color: Pal.green
    opacity: 0.8
    font.family: Pal.mono
    font.weight: Font.DemiBold
    font.pixelSize: 8
    font.letterSpacing: 1.2
  }
}
