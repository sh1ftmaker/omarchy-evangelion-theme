import QtQuick
import "Pal.js" as Pal

// HARMONICS ハーモニクス: segmented bar spectrum of the system audio output
// (32 log bands, 40 Hz - 10 kHz): orange blocks, amber/red tops, peak-hold
// ticks, RMS level meter. Frames arrive at ~25 fps while sound plays and 2 fps
// otherwise. Motion is vsync (FrameAnimation): bars ease toward the latest FFT
// frame (fast attack, slow decay), peak-hold ticks hold then fall with gravity,
// the level meter eases, and an idle scan sweeps the flatline when nothing plays.
// Covered / hidden: FrameAnimation stops.
NervFrame {
  id: root

  title: "HARMONICS"
  jpTitle: "ハーモニクス"
  code: "32 BAND · 40Hz-10kHz"
  status: sigState === "X" ? "SIGNAL LOST" : sigState === "Q" ? "NO SOUND"
        : lvl >= 2 ? "OVERLOAD" : lvl >= 1 ? "HARMONICS DEVIATION" : "HARMONICS NORMAL"
  statusJp: sigState === "X" ? "信号途絶" : sigState === "Q" ? "無音"
        : lvl >= 2 ? "過負荷" : lvl >= 1 ? "偏差" : "正常"
  statusColor: sigState === "X" ? Pal.red : sigState === "Q" ? Pal.ash
        : lvl >= 2 ? Pal.red : lvl >= 1 ? Pal.amber : Pal.green
  statusLit: sigState !== "X" || blink
  accent: sigState === "A" && lvl >= 1 ? Pal.amber : Pal.orange

  // layout derived from the frame size (520 x 132 at the reference wall rect)
  readonly property int nb: 32
  readonly property int rows: 13
  readonly property int specX: 84
  readonly property int specY: headerH + 9
  readonly property int rowH: Math.max(3, Math.floor((height - specY - 27) / rows))   // 6 at 132 px
  readonly property int barW: Math.max(4, Math.floor((width - specX - 20) / nb))      // 13 at 520 px
  readonly property int specW: nb * barW
  readonly property int specH: rows * rowH

  property string sigState: "X"
  property real db: -99
  property real peakHz: 0
  property int lvl: 0
  property bool blink: true
  property var vals: []
  property var peaks: []
  property bool live: true                     // false while covered / hidden: motion stops
  property real dbN: 0                         // eased level meter 0..1
  property real clock: 0
  // per-band animation state (plain JS, pushed into the delegates imperatively)
  property var dsp: []
  property var pkv: []
  property var pkHold: []
  property var pkVel: []

  readonly property var noteNames: ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
  function noteOf(hz) {
    if (hz < 20) return "--"
    var m = Math.round(69 + 12 * Math.log(hz / 440) / Math.LN2)
    return noteNames[(m % 12 + 12) % 12] + (Math.floor(m / 12) - 1)
  }

  // H state db hz v0..v31 p0..p31
  function frame(p) {
    sigState = p[1]
    db = +p[2]
    peakHz = +p[3]
    var v = [], k = []
    for (var i = 0; i < nb; i++) { v.push(+p[4 + i] / 99); k.push(+p[4 + nb + i] / 99) }
    vals = v; peaks = k
    lvl = sigState !== "A" ? 0 : db > -4 ? 2 : db > -14 ? 1 : 0
    blink = !blink
  }

  // ---------------------------------------------------------------- motion
  // driven by the plugin's frame() signal (the wall host's shared vsync clock when embedded)
  property var ticker: null
  Connections {
    target: root.ticker
    enabled: root.live && root.visible
    function onFrame(frameTime, currentFrame) {
      var dt = Math.min(Math.max(frameTime, 0), 0.1)
      root.clock += dt
      var ka = 1 - Math.exp(-dt / 0.028), kd = 1 - Math.exp(-dt / 0.16)
      var D = root.dsp, P = root.pkv, Hd = root.pkHold, Vl = root.pkVel, T = root.vals
      if (D.length !== root.nb) {
        D = []; P = []; Hd = []; Vl = []
        for (var z = 0; z < root.nb; z++) { D.push(0); P.push(0); Hd.push(0); Vl.push(0) }
        root.dsp = D; root.pkv = P; root.pkHold = Hd; root.pkVel = Vl
      }
      for (var i = 0; i < root.nb; i++) {
        var tg = root.sigState === "A" ? (T[i] || 0) : 0
        var d = D[i], nd = d
        if (tg > d) nd = d + (tg - d) * ka
        else nd = d + (tg - d) * kd
        if (Math.abs(tg - nd) < 0.002) nd = tg
        var p = P[i], np = p
        if (nd >= p) { np = nd; Hd[i] = 0.45; Vl[i] = 0 }
        else if (Hd[i] > 0) Hd[i] -= dt
        else { Vl[i] += 2.6 * dt; np = Math.max(nd, p - Vl[i] * dt) }
        if (nd !== d || np !== p) {
          D[i] = nd; P[i] = np
          var it = bars.itemAt(i)
          if (it) { it.dv = nd; it.pv = np }
        }
      }
      var tdb = root.sigState === "A" ? Math.max(0, Math.min(1, (root.db + 60) / 60)) : 0
      var dd = tdb - root.dbN
      if (Math.abs(dd) > 0.002) root.dbN += dd * (dd > 0 ? ka : kd)
      else if (dd !== 0) root.dbN = tdb
    }
  }

  // ---------------------------------------------------------------- static ground
  Canvas {
    id: ground
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var x0 = root.specX, y0 = root.specY, w = root.specW, h = root.specH
      Pal.hexGrid(ctx, x0 - 4, y0 - 2, w + 8, h + 4, 7, Pal.rgba("orange", 0.07))
      // dB rules every 4 rows
      ctx.fillStyle = Pal.rgba("orange", 0.14)
      for (var r = 0; r <= root.rows; r += 4) ctx.fillRect(x0, y0 + h - r * root.rowH, w, 1)
      // frequency axis
      ctx.fillStyle = Pal.rgba("orange", 0.55)
      ctx.fillRect(x0, y0 + h + 1, w, 1)
      var fr = [63, 125, 250, 500, 1000, 2000, 4000, 8000]
      for (var i = 0; i < fr.length; i++) {
        var fx = x0 + Math.log(fr[i] / 40) / Math.log(250) * w
        ctx.fillRect(Math.round(fx), y0 + h + 1, 1, 4)
      }
      for (var t = 0; t <= root.nb; t++) ctx.fillRect(x0 + t * root.barW, y0 + h + 1, 1, 2)
      // unlit segment ghosts
      for (var gb = 0; gb < root.nb; gb++)
        for (var gr = 0; gr < root.rows; gr++) {
          var gk = gr / root.rows
          ctx.fillStyle = Pal.rgba(gk > 0.82 ? "red" : gk > 0.64 ? "amber" : "orange", 0.07)
          ctx.fillRect(x0 + gb * root.barW + 2, y0 + h - (gr + 1) * root.rowH + 1, root.barW - 3, root.rowH - 1)
        }
      for (var gs = 0; gs < root.rows; gs++) {
        ctx.fillStyle = Pal.rgba("orange", 0.08)
        ctx.fillRect(60, y0 + h - (gs + 1) * root.rowH + 1, 11, root.rowH - 1)
      }
      // level meter well
      ctx.strokeStyle = Pal.rgba("orange", 0.5)
      ctx.lineWidth = 1
      ctx.strokeRect(58.5, y0 - 0.5, 14, h + 1)
    }
  }

  // ---------------------------------------------------------------- live bars
  // Plain Rectangles (GPU scene graph) instead of a Canvas: a frame only moves
  // ~130 geometry properties, no software rasterisation. Rows are snapped to
  // whole segments; the segment gaps come from the static overlay below.
  readonly property color baseCol: sigState === "A" && lvl >= 1 ? Pal.amber : Pal.orange

  Repeater {
    id: bars
    model: root.nb
    delegate: Item {
      id: bar
      required property int index
      property real dv: 0                        // eased level 0..1 (set per frame)
      property real pv: 0                        // falling peak 0..1
      readonly property real n: dv * root.rows
      readonly property real pk: pv * root.rows
      x: root.specX + index * root.barW + 2
      y: root.specY
      width: root.barW - 3
      height: root.specH

      Rectangle {
        width: parent.width; y: root.specH - height
        height: Math.min(bar.n, 9) * root.rowH
        color: root.baseCol
        visible: height > 0
      }
      Rectangle {
        width: parent.width; y: root.specH - 9 * root.rowH - height
        height: Math.max(0, Math.min(bar.n - 9, 2)) * root.rowH
        color: Pal.amber
        visible: height > 0
      }
      Rectangle {
        width: parent.width; y: root.specH - 11 * root.rowH - height
        height: Math.max(0, Math.min(bar.n - 11, 2)) * root.rowH
        color: Pal.red
        visible: height > 0
      }
      Rectangle {
        x: -1; width: parent.width + 2; height: 2
        y: root.specH - bar.pk * root.rowH
        antialiasing: true
        visible: bar.pk > 0.5
        color: bar.pk > root.rows * 0.82 ? Pal.red : Pal.amber
      }
    }
  }

  // RMS level meter: 13 segments over -60..0 dB
  Item {
    id: meter
    readonly property real n: root.dbN * root.rows
    x: 60; y: root.specY; width: 11; height: root.specH
    Rectangle { width: parent.width; y: root.specH - height; height: Math.min(meter.n, 9) * root.rowH; color: Pal.orange; visible: height > 0 }
    Rectangle { width: parent.width; y: root.specH - 9 * root.rowH - height; height: Math.max(0, Math.min(meter.n - 9, 2)) * root.rowH; color: Pal.amber; visible: height > 0 }
    Rectangle { width: parent.width; y: root.specH - 11 * root.rowH - height; height: Math.max(0, Math.min(meter.n - 11, 2)) * root.rowH; color: Pal.red; visible: height > 0 }
  }

  onBarWChanged: { ground.requestPaint(); gaps.requestPaint() }
  onRowHChanged: { ground.requestPaint(); gaps.requestPaint() }

  // segment gaps (static, drawn over the bars)
  Canvas {
    id: gaps
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = "rgba(5,4,3,0.9)"
      for (var r = 0; r <= root.rows; r++) {
        var y = root.specY + root.specH - r * root.rowH
        ctx.fillRect(root.specX, y, root.specW, 1)
        ctx.fillRect(60, y, 11, 1)
      }
    }
  }

  // flatline when nothing plays, with a scan pulse sweeping along it (idle shimmer)
  Item {
    x: root.specX; y: root.specY + root.specH - 4
    width: root.specW; height: 6
    visible: root.sigState !== "A"
    clip: true
    Rectangle {
      y: 3; width: parent.width; height: 2
      color: root.sigState === "X" ? Pal.red : Pal.orange
      opacity: root.sigState === "X" && !root.blink ? 0.35 : 0.9
    }
    Item {
      id: scan
      readonly property real span: parent.width + 80
      x: (root.clock * 70) % span - 40
      width: 40; height: 6
      Rectangle { x: 0; y: 2; width: 26; height: 4; color: root.sigState === "X" ? Pal.red : Pal.amber; opacity: 0.25; antialiasing: true }
      Rectangle { x: 14; y: 2; width: 16; height: 4; color: root.sigState === "X" ? Pal.red : Pal.amber; opacity: 0.55; antialiasing: true }
      Rectangle { x: 26; y: 1; width: 6; height: 6; color: Pal.bone; opacity: 0.85; antialiasing: true }
    }
  }

  // ---------------------------------------------------------------- readouts
  Column {
    x: 9
    y: root.specY - 1
    spacing: 1
    Text {
      text: "LEVEL"
      color: Pal.ash
      font.family: Pal.mono; font.weight: Font.DemiBold; font.pixelSize: 7; font.letterSpacing: 1.4
    }
    Text {
      text: root.sigState === "A" ? root.db.toFixed(1) : "-∞"
      color: root.lvl >= 2 ? Pal.red : root.lvl >= 1 ? Pal.amber : Pal.orange
      font.family: Pal.mono; font.weight: Font.Bold; font.pixelSize: 12
    }
    Text {
      text: "dBFS 音圧"
      color: Pal.orange; opacity: 0.75
      font.family: Pal.jp; font.weight: Font.Bold; font.pixelSize: 7
    }
    Item { width: 1; height: 3 }
    Text {
      text: "PEAK 主音"
      color: Pal.ash
      font.family: Pal.jp; font.weight: Font.Bold; font.pixelSize: 7
    }
    Text {
      text: root.sigState === "A" && root.peakHz > 0 ? Math.round(root.peakHz) + "Hz" : "----"
      color: Pal.orange
      font.family: Pal.mono; font.weight: Font.Bold; font.pixelSize: 10
    }
    Text {
      text: root.sigState === "A" ? root.noteOf(root.peakHz) : "--"
      color: Pal.amber
      font.family: Pal.mono; font.weight: Font.Bold; font.pixelSize: 9; font.letterSpacing: 1
    }
  }

  // band labels (Hz)
  Repeater {
    model: [[63, "63"], [125, "125"], [250, "250"], [500, "500"], [1000, "1k"], [2000, "2k"], [4000, "4k"], [8000, "8k"]]
    delegate: Text {
      required property var modelData
      x: root.specX + Math.log(modelData[0] / 40) / Math.log(250) * root.specW - implicitWidth / 2
      y: root.specY + root.specH + 5
      text: modelData[1]
      color: Pal.orange
      opacity: 0.85
      font.family: Pal.mono; font.weight: Font.DemiBold; font.pixelSize: 7; font.letterSpacing: 0.5
    }
  }
  Text {
    x: root.specX + root.specW - implicitWidth
    y: root.specY + root.specH + 14
    text: "Hz 周波数"
    color: Pal.ash
    font.family: Pal.jp; font.weight: Font.Bold; font.pixelSize: 7
  }
  Text {
    x: root.specX
    y: root.specY + root.specH + 14
    text: root.sigState === "X" ? "MONITOR IDLE · 待機" : "@DEFAULT_MONITOR · 22.05kHz · FFT1024"
    color: Pal.ash
    font.family: Pal.mono; font.weight: Font.DemiBold; font.pixelSize: 7; font.letterSpacing: 1
  }
}
