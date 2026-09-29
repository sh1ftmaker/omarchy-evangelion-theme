import QtQuick

// The council chamber: frame, the arc of 12 monoliths over a faint floor, and the footer
// (speaker dossier, voice print, minutes ticker). Laid out in design px (368x250 nominal).
SeeleFrame {
  id: c

  property var hud

  title: "SOUND ONLY"
  jp: "人類補完委員会"
  code: "CLOSED SESSION // 非公開審議 · 12 VOICE CHANNELS"
  fillAlpha: hud.fillAlpha

  // ------------------------------------------------------------- geometry
  readonly property real footH: 80
  readonly property real stageTop: header + 8
  readonly property real stageH: height - footH - stageTop
  readonly property real floorY: stageTop + stageH - 12
  readonly property real rise: Math.min(16, stageH * 0.11)
  readonly property real w0: 26 * (width - 12) / 356
  readonly property real h0: Math.min(106, (stageH - 16) / 1.04)

  function dOf(i) { return Math.abs(i - 5.5) / 5.5 }
  function sOf(i) { var d = dOf(i); return 0.74 + 0.30 * d * d }
  // cumulative x of slab i, with equal gaps filling the stage width
  readonly property var xs: {
    var tot = 0, i
    for (i = 0; i < 12; i++) tot += w0 * sOf(i)
    var gap = (width - 20 - tot) / 11, x = 10, out = []
    for (i = 0; i < 12; i++) { out.push(x); x += w0 * sOf(i) + gap }
    return out
  }
  function bottomOf(i) { var d = dOf(i); return floorY - rise * (1 - d * d) }

  // ------------------------------------------------------------- header right: session clock
  Row {
    anchors.right: parent.right
    anchors.rightMargin: c.cut + 5
    y: 2
    height: c.header - 4
    spacing: 4
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 5; height: 5
      color: "#FF1A1A"
      opacity: c.hud.blinkOn ? 1 : 0.2
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "SESSION " + c.hud.clock
      color: "#FF1A1A"
      font.family: "IBM Plex Mono"
      font.weight: Font.Bold
      font.pixelSize: 8
      font.letterSpacing: 1.4
    }
  }

  // ------------------------------------------------------------- floor (painted on resize)
  Canvas {
    id: floor
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var g = getContext("2d")
      g.reset()
      var W = width, cx = W / 2
      function arcY(x, off) { var d = Math.min(1, Math.abs(x - cx) / (W / 2 - 10)); return c.floorY + off - (c.rise + off * 0.4) * (1 - d * d) }
      g.lineWidth = 1
      for (var r = 0; r < 4; r++) {
        var off = 6 + r * r * 5
        g.strokeStyle = "rgba(255,26,26," + (0.22 - r * 0.045) + ")"
        g.beginPath()
        for (var x = 8; x <= W - 8; x += 4) { var y = arcY(x, off); if (x === 8) g.moveTo(x, y); else g.lineTo(x, y) }
        g.stroke()
      }
      // radial floor lines toward a vanishing point above the stage
      g.strokeStyle = "rgba(106,0,0,0.55)"
      g.beginPath()
      var vy = c.stageTop + 8, fy = c.height - c.footH - 2
      for (var i = -6; i <= 6; i++) {
        var bx = cx + i * W / 9
        var t0 = (c.floorY - c.rise - vy) / (fy - vy)
        g.moveTo(cx + (bx - cx) * t0, c.floorY - c.rise + 4); g.lineTo(bx, fy)
      }
      g.stroke()
      // the axis: a hairline from the speaker's station down to the floor
      g.strokeStyle = "rgba(255,26,26,0.18)"
      g.beginPath(); g.moveTo(cx + 0.5, c.stageTop - 2); g.lineTo(cx + 0.5, fy); g.stroke()
    }
  }

  // slow drifting scan along the floor arcs: a bright copy of the arcs (painted once) seen
  // through a moving clip window; only x changes per frame
  Item {
    id: scan
    readonly property real bw: 34
    // one sweep every 7 s, then 3 s dark
    readonly property real u: (c.hud.t % 10) / 7
    visible: u <= 1
    x: -bw + u * (c.width + bw)
    y: c.floorY - c.rise - 4
    width: bw
    height: c.height - c.footH - y
    clip: true
    Canvas {
      id: scanArcs
      x: -scan.x; y: -scan.y
      width: c.width; height: c.height
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var g = getContext("2d")
        g.reset()
        var W = width, cx = W / 2
        function arcY(x, off) { var d = Math.min(1, Math.abs(x - cx) / (W / 2 - 10)); return c.floorY + off - (c.rise + off * 0.4) * (1 - d * d) }
        g.lineWidth = 1
        for (var r = 0; r < 4; r++) {
          var off = 6 + r * r * 5
          g.strokeStyle = "rgba(255,26,26," + (0.75 - r * 0.15) + ")"
          g.beginPath()
          for (var x = 8; x <= W - 8; x += 4) { var y = arcY(x, off); if (x === 8) g.moveTo(x, y); else g.lineTo(x, y) }
          g.stroke()
        }
      }
    }
    // leading edge tick
    Rectangle { x: scan.bw - 1; width: 1; height: parent.height; color: "#FF1A1A"; opacity: 0.25 }
  }

  // ------------------------------------------------------------- the council
  Repeater {
    model: 12
    Monolith {
      required property int index
      readonly property var seat: index < c.hud.seats.length ? c.hud.seats[index] : null
      member: index + 1
      s: c.sOf(index)
      lean: index < 6 ? -c.dOf(index) : c.dOf(index)
      x: c.xs[index]
      width: c.w0 * s
      height: c.h0 * s
      y: c.bottomOf(index) - height
      live: seat !== null
      name: seat ? seat.name : ""
      pid: seat ? seat.pid : 0
      animate: c.hud.animate
      cpu: seat ? seat.cpu : 0
      level: c.hud.lvl(cpu)
      speaker: c.hud.speaker === index
    }
  }

  // ------------------------------------------------------------- footer
  readonly property real fy: height - footH

  Rectangle { x: 6; y: c.fy; width: c.width - 12; height: 1; color: "#FF1A1A"; opacity: 0.35 }

  // speaker line
  Row {
    x: 9; y: c.fy + 4
    spacing: 5
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 4; height: 8
      color: "#FF1A1A"
      opacity: c.hud.blinkOn ? 1 : 0.25
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: c.hud.spk ? "MEMBER " + c.hud.two(c.hud.speaker + 1) : "MEMBER --"
      color: "#FF1A1A"
      font.family: "IBM Plex Mono"
      font.weight: Font.Bold
      font.pixelSize: 10
      font.letterSpacing: 2
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "発言中 ／ SPEAKING"
      color: "#FF1A1A"
      opacity: 0.8
      font.family: "Noto Sans CJK JP"
      font.weight: Font.Bold
      font.pixelSize: 8
    }
  }

  // voice print of the speaker's CPU history
  VoiceTrace {
    x: 8; y: c.fy + 19
    width: c.width * 0.53
    height: 32
    hist: c.hud.hist
    time: c.hud.t % 600   // keep float32 phase precision in the shader
    prog: c.hud.sampleProg
  }
  Text {
    x: 9; y: c.fy + 52
    text: "VOICE PRINT // 声紋 · " + c.hud.hist.length * 2 + "s"
    color: "#FF1A1A"
    opacity: 0.45
    font.family: "IBM Plex Mono"
    font.weight: Font.DemiBold
    font.pixelSize: 6
    font.letterSpacing: 1.2
  }

  // dossier
  Column {
    x: c.width * 0.53 + 18
    y: c.fy + 5
    spacing: 0
    Repeater {
      model: [
        ["PROC", c.hud.spk ? c.hud.spk.name.toUpperCase() : "----", true],
        ["PID", c.hud.spk ? String(c.hud.spk.pid) : "----", false],
        ["RSS", c.hud.spk ? c.hud.fmtBytes(c.hud.spk.rss) : "----", false],
        ["CPU", c.hud.spk ? c.hud.spk.now.toFixed(1) + "% · " + c.hud.spk.thr + " THR" : "----", false],
        ["COUNCIL", c.hud.procs + " PROC · " + c.hud.threads + " THR", false]
      ]
      Row {
        required property var modelData
        spacing: 0
        Text {
          width: 40
          text: modelData[0]
          color: "#FF1A1A"
          opacity: 0.5
          font.family: "IBM Plex Mono"
          font.weight: Font.DemiBold
          font.pixelSize: 7
          font.letterSpacing: 1
        }
        Text {
          width: c.width * 0.47 - 18 - 40 - 12
          elide: Text.ElideRight
          text: modelData[1]
          color: modelData[2] ? "#FFE9C8" : "#FF1A1A"
          font.family: "IBM Plex Mono"
          font.weight: Font.Bold
          font.pixelSize: 7
          font.letterSpacing: 1
        }
      }
    }
  }

  // minutes ticker
  Item {
    id: tick
    x: 6; y: c.height - 17
    width: c.width - 6 - c.cut - 2
    height: 11
    Rectangle { width: tag.implicitWidth + 10; height: parent.height; color: "#6A0000" }
    Text {
      id: tag
      x: 5
      anchors.verticalCenter: parent.verticalCenter
      text: "議事録 MINUTES"
      color: "#FF1A1A"
      font.family: "Noto Sans CJK JP"
      font.weight: Font.Bold
      font.pixelSize: 7
    }
    Item {
      id: lane
      x: tag.implicitWidth + 14
      width: parent.width - x
      height: parent.height
      clip: true
      property string shown: ""
      property real off: 0
      property real t0: 0
      Text {
        id: tt
        anchors.verticalCenter: parent.verticalCenter
        x: lane.width - lane.off
        text: lane.shown
        color: "#FF1A1A"
        opacity: 0.85
        font.family: "IBM Plex Mono"
        font.weight: Font.DemiBold
        font.pixelSize: 7
        font.letterSpacing: 1
      }
      // continuous sub-pixel scroll at 20 design px/s, time-based; latch the minutes once
      // per pass so the line never jumps mid-scroll
      Connections {
        target: c.hud
        function onTChanged() {
          var t = c.hud.t
          lane.off = (t - lane.t0) * 20
          if (lane.shown === "" || lane.width - lane.off < -tt.implicitWidth) {
            lane.t0 = t
            lane.off = 0
            lane.shown = c.hud.hasData ? c.hud.minutes : ""
          }
        }
        // demo toggled: drop the latched line now (it may hold real / fake names)
        function onDemoChanged() { lane.shown = "" }
      }
    }
  }
}
