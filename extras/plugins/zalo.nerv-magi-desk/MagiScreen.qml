import QtQuick
import "Palette.js" as Pal
import "Draw.js" as Draw
import "Stats.js" as Stats

// The MAGI deliberation screen recomposed for the desktop wall (reference 520x422, but
// every block is placed from width/height so a re-packed nerv-wall.json still fits).
//
//   ┌ MAGI SYSTEM マギ・システム ────────────────────── Q0042 審議中 ┐
//   │ 提訴 APPEAL │ BALTHASAR·2 │ UPTIME   │ 決議 RESOLUTION         │
//   │ meta rows   │   memory    │ system   │ [ 承認 ] DELIBERATION   │
//   │        ╲        MAGI        ╱        │ TALLY 投票集計           │
//   │   CASPER·3 ═══════ MELCHIOR·1        │ SYS LOG 処理記録 (hex)   │
//   └───────────────────────────────────────────────────────────────┘
// Terminal state (votes, verdict, blinks, log text) steps on magi.tick. Continuous motion runs
// on one vsync FrameAnimation (paused whenever the wall is covered or hidden) and only moves
// items: bus packets glide, the SYS LOG scrolls sub-pixel, a scan band sweeps the honeycomb.
// Meters / hex cells ease via Behaviors. Canvases still repaint only on data change.
Item {
  id: scr
  required property var magi
  property real fillAlpha: 0.82
  property real pxScale: 2          // device px per reference px (window scale x output scale)

  // ------------------------------------------------------------------ derived vote state
  readonly property var v: magi.votes
  readonly property int nOk: (v[0] === true ? 1 : 0) + (v[1] === true ? 1 : 0) + (v[2] === true ? 1 : 0)
  readonly property int nNo: (v[0] === false ? 1 : 0) + (v[1] === false ? 1 : 0) + (v[2] === false ? 1 : 0)
  readonly property int nVoters: nOk + nNo
  readonly property bool unanimous: nVoters === 3 && (nOk === 3 || nNo === 3)
  readonly property string resKanji: nOk === 3 ? "可決" : (nNo === 3 ? "否決" : (nOk > nNo ? "承認" : (nNo > nOk ? "否決" : "審議中")))
  readonly property string resText: nOk === 3 ? "PASSED · UNANIMOUS" : (nNo === 3 ? "REJECTED · UNANIMOUS"
    : (nOk > nNo ? "APPROVED " + nOk + "/" + nVoters : (nNo > nOk ? "REJECTED " + nNo + "/" + nVoters : "DELIBERATING")))
  readonly property string resCol: nOk > nNo ? Pal.green : (nNo > nOk ? Pal.red : Pal.orange)
  readonly property bool blinkOn: magi.tick % 2 === 0
  readonly property string queryNo: Stats.pad(magi.query % 10000, 4)

  // ------------------------------------------------------------------ layout
  readonly property real bx: 6
  readonly property real by: 20
  readonly property real bw: width - 12
  readonly property real bh: height - by - 6
  readonly property real rcW: Math.round(Math.max(130, Math.min(170, bw * 0.29)))
  readonly property real rcX: bx + bw - rcW
  readonly property real taX: bx
  readonly property real taW: bw - rcW - 8
  readonly property real gap: 26
  readonly property real blkW: Math.floor((taW - gap) / 2)
  readonly property real blkH: Math.round(Math.min(150, bh * 0.37))
  readonly property real balX: taX + Math.round((taW - blkW) / 2)
  readonly property real casX: taX
  readonly property real melX: taX + taW - blkW
  readonly property real lowY: by + bh - blkH
  readonly property real cx: taX + taW / 2
  // bus bars: [x0, y0, x1, y1] in screen coords; drawn under the blocks
  readonly property var buses: [
    [balX + 20, by + blkH - 14, casX + blkW - 20, lowY + 14],
    [balX + blkW - 20, by + blkH - 14, melX + 20, lowY + 14],
    [casX + blkW - 6, lowY + blkH * 0.55, melX + 6, lowY + blkH * 0.55]
  ]

  onWidthChanged: { ground.requestPaint(); honey.requestPaint(); honeyHot.requestPaint() }
  onHeightChanged: { ground.requestPaint(); honey.requestPaint(); honeyHot.requestPaint() }

  // ------------------------------------------------------------------ vsync motion clock
  property real t: 0                       // seconds of visible motion
  // driven by the panel's frame() signal (the wall host's shared vsync clock, or the
  // standalone plugin's own FrameAnimation)
  Connections {
    target: scr.magi
    enabled: scr.magi.live && scr.visible
    function onFrame(frameTime, currentFrame) {
      var dt = Math.min(0.1, frameTime)
      scr.t += dt
      // SYS LOG: drain the scroll offset at a steady ~22 px/s plus a proportional catch-up,
      // which matches the 2.5 rows/s arrival rate so the column creeps instead of jumping.
      if (logBox.shift > 0) logBox.shift = Math.max(0, logBox.shift - (22 + 3 * logBox.shift) * dt)
    }
  }

  function paintHoney(ctx, alpha, col) {
    ctx.reset()
    ctx.strokeStyle = col
    ctx.globalAlpha = alpha
    ctx.lineWidth = 0.75
    var r = 12, dx = Math.sqrt(3) * r, dy = 1.5 * r
    for (var row = 0; row * dy < scr.bh + r; row++)
      for (var col2 = 0; col2 * dx < scr.taW + dx; col2++) {
        Draw.hex(ctx, col2 * dx + (row % 2 ? dx / 2 : 0), row * dy, r - 1)
        ctx.stroke()
      }
  }
  // static bottom: chrome + header readout + faint honeycomb, flattened into one layer
  Item {
    id: bottomLayer
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.ceil(width * scr.pxScale), Math.ceil(height * scr.pxScale))

  // ------------------------------------------------------------------ frame (tactical chrome)
  NervPanel {
    anchors.fill: parent
    title: "MAGI SYSTEM"
    jp: "マギ・システム"
    header: 15
    cut: 12
    fill: Qt.rgba(0.02, 0.014, 0.008, scr.fillAlpha)
  }

  // header readout, right (masks the tick run behind it)
  Rectangle {
    anchors.right: parent.right
    anchors.rightMargin: 16
    y: 1
    width: hdrRow.implicitWidth + 10
    height: 12
    color: Pal.ink
    Row {
      id: hdrRow
      anchors.centerIn: parent
      spacing: 6
      MonoText {
        anchors.verticalCenter: parent.verticalCenter
        text: "QUERY " + scr.queryNo + " // ACCEPT WORKLOAD?"
        font.pixelSize: 8
        opacity: 0.8
      }
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 5; height: 5
        color: scr.resCol
        visible: scr.blinkOn || scr.unanimous
      }
      JpText {
        anchors.verticalCenter: parent.verticalCenter
        text: "審議中"
        color: scr.resCol
        font.pixelSize: 9
      }
    }
  }

  // ------------------------------------------------------------------ ground: hex field + buses
  // faint honeycomb behind the triangle (painted once)
  Canvas {
    id: honey
    x: scr.taX; y: scr.by
    width: scr.taW; height: scr.bh
    onPaint: scr.paintHoney(getContext("2d"), 0.4, Pal.graphite)
  }
  }

  // slow scan shimmer: a brighter copy of the honeycomb seen through a band that sweeps down.
  // Only the band's y (and the copy's counter-offset) change per frame.
  Item {
    id: scan
    readonly property real bandH: 16
    readonly property real period: 7.5
    readonly property real sy: ((scr.t / period) % 1) * (scr.bh + bandH * 3) - bandH
    x: scr.taX
    y: scr.by + Math.max(0, sy)
    width: scr.taW
    height: Math.max(0, Math.min(bandH, scr.bh - Math.max(0, sy), sy + bandH))
    clip: true
    Canvas {
      id: honeyHot
      y: scr.by - scan.y
      width: scr.taW; height: scr.bh
      opacity: 0.55
      onPaint: scr.paintHoney(getContext("2d"), 1, Pal.orange)
    }
    Rectangle {   // hard leading edge of the scan
      y: scan.height - 1
      width: parent.width; height: 1
      color: Pal.orange
      opacity: 0.18
      visible: scan.sy + scan.bandH <= scr.bh
    }
  }
  Canvas {
    id: ground
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()

      // vertical divider between the triangle and the right column, with ticks
      var dxl = scr.rcX - 4.5
      ctx.fillStyle = Pal.orange
      ctx.globalAlpha = 0.45
      ctx.fillRect(dxl, scr.by, 1, scr.bh)
      for (var y = scr.by; y < scr.by + scr.bh; y += 6)
        ctx.fillRect(dxl - ((y - scr.by) % 30 === 0 ? 3 : 1.5), y, (y - scr.by) % 30 === 0 ? 3 : 1.5, 1)
      ctx.globalAlpha = 1

      // MAGI bus bars
      ctx.lineCap = "butt"
      for (var i = 0; i < scr.buses.length; i++) {
        var b = scr.buses[i]
        ctx.strokeStyle = Pal.orange
        ctx.lineWidth = 11
        ctx.beginPath(); ctx.moveTo(b[0], b[1]); ctx.lineTo(b[2], b[3]); ctx.stroke()
        ctx.strokeStyle = Pal.ink
        ctx.lineWidth = 4
        ctx.beginPath(); ctx.moveTo(b[0], b[1]); ctx.lineTo(b[2], b[3]); ctx.stroke()
      }
    }
  }

  // data packets gliding along the buses (time-based, sub-pixel; 3.6 s per run)
  Repeater {
    model: 9
    Rectangle {
      required property int index
      readonly property int bi: Math.floor(index / 3)
      readonly property var bus: scr.buses[bi]
      readonly property real ph: 0.12 + 0.76 * ((scr.t / 3.6 + (index % 3) / 3 + bi * 0.11) % 1)
      readonly property real u: bi === 1 ? 1 - ph : ph
      width: 4; height: 4
      antialiasing: true
      color: Pal.amber
      x: bus[0] + (bus[2] - bus[0]) * u - 2
      y: bus[1] + (bus[3] - bus[1]) * u - 2
    }
  }

  // Everything that only changes on data ticks is flattened into one layer (one textured quad
  // per frame instead of ~150 text/canvas draws); it re-renders only when something inside
  // changes. The per-frame movers (packets, scan band, SYS LOG rows) live outside it.
  Item {
    id: staticLayer
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.ceil(width * scr.pxScale), Math.ceil(height * scr.pxScale))

  // ------------------------------------------------------------------ MAGI centre card
  Item {
    id: centre
    readonly property real gapTop: scr.by + scr.blkH
    x: scr.cx - 60
    y: gapTop - 2
    width: 120; height: 82
    Text {
      textFormat: Text.PlainText
      text: "MAGI"
      color: Pal.orange
      font.family: Pal.serif
      font.pixelSize: 54
      font.weight: 600
      font.bold: true
      style: Text.Outline
      styleColor: Pal.ink
      x: (centre.width - implicitWidth * 0.6) / 2
      y: -8
      transform: Scale { xScale: 0.6; yScale: 1 }
    }
    MonoText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 56
      text: "SUPERCOMPUTER"
      font.pixelSize: 7
      font.letterSpacing: 2
    }
    JpText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 67
      text: "三系統合議制"
      font.pixelSize: 8
      font.weight: Font.Medium
      opacity: 0.85
    }
  }

  // ------------------------------------------------------------------ appeal (top-left)
  Item {
    x: scr.taX + 2
    y: scr.by + 2
    width: scr.balX - scr.taX - 10
    height: scr.blkH - 4
    ChamferBox {
      width: parent.width; height: 20
      cuts: [0, 7, 0, 7]
      fillColor: Pal.ink
      strokeColor: Pal.orange
      lineWidth: 1.5
      Row {
        anchors.verticalCenter: parent.verticalCenter
        x: 6
        spacing: 5
        JpText { text: "提訴"; font.pixelSize: 13; font.weight: Font.Black; anchors.verticalCenter: parent.verticalCenter }
        MonoText { text: "APPEAL"; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.5; anchors.verticalCenter: parent.verticalCenter }
      }
    }
    Column {
      x: 2; y: 26
      spacing: 2
      Repeater {
        model: [
          ["CODE", "473"],
          ["FILE", "MAGI_SYS"],
          ["QUERY", scr.queryNo],
          ["SUBJ", "WORKLOAD"],
          ["PRIOR", "AAA"],
          ["EX_MODE", "OFF"],
          ["QUORUM", scr.nVoters + "/3"]
        ]
        Row {
          required property var modelData
          MonoText { width: 40; text: modelData[0]; font.pixelSize: 7; font.letterSpacing: 0.8; opacity: 0.75 }
          MonoText { text: modelData[1]; font.pixelSize: 7; font.letterSpacing: 0.8; color: Pal.amber }
        }
      }
    }
    JpText {
      anchors.bottom: parent.bottom
      x: 2
      text: "第7世代有機コンピュータ"
      font.pixelSize: 7
      opacity: 0.55
    }
  }

  // ------------------------------------------------------------------ system (top-right)
  Item {
    x: scr.balX + scr.blkW + 8
    y: scr.by + 2
    width: scr.taX + scr.taW - x - 2
    height: scr.blkH - 4
    Column {
      anchors.right: parent.right
      spacing: 0
      Row {
        anchors.right: parent.right
        spacing: 4
        MonoText { text: "UPTIME"; font.pixelSize: 7; opacity: 0.8 }
        JpText { text: "稼働時間"; font.pixelSize: 7; opacity: 0.8 }
      }
      MonoText {
        anchors.right: parent.right
        text: "D+" + Stats.pad(Stats.uptime(scr.magi.uptime).days, 3)
        font.pixelSize: 8
      }
      MonoText {
        anchors.right: parent.right
        text: Stats.uptime(scr.magi.uptime).clock
        font.pixelSize: 15
        font.weight: Font.Bold
        font.letterSpacing: 0
        color: Pal.amber
      }
    }
    Column {
      anchors.right: parent.right
      y: 48
      spacing: 3
      Repeater {
        model: [
          ["CPU TEMP", "温度", isNaN(scr.magi.cpuTemp) ? "--.-°C" : scr.magi.cpuTemp.toFixed(1) + "°C", scr.magi.cpuTemp >= 90],
          ["LOAD AVG", "負荷", scr.magi.loadAvg.join(" "), scr.magi.cores.length > 0 && Number(scr.magi.loadAvg[0]) > scr.magi.cores.length],
          ["TASKS", "処理数", scr.magi.procs || "--", false]
        ]
        Column {
          required property var modelData
          anchors.right: parent.right
          Row {
            anchors.right: parent.right
            spacing: 4
            MonoText { text: modelData[0]; font.pixelSize: 6; opacity: 0.7; font.letterSpacing: 1 }
            JpText { text: modelData[1]; font.pixelSize: 7; opacity: 0.7 }
          }
          MonoText {
            anchors.right: parent.right
            text: modelData[2]
            font.pixelSize: modelData[2].length > 9 ? 8 : 11
            font.weight: Font.Bold
            font.letterSpacing: 0.3
            color: modelData[3] ? Pal.red : Pal.amber
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------ RESOLUTION
  ChamferBox {
    x: scr.rcX; y: scr.by
    width: scr.rcW; height: 20
    cuts: [0, 7, 0, 7]
    fillColor: Pal.ink
    strokeColor: Pal.orange
    lineWidth: 1.5
    Row {
      anchors.verticalCenter: parent.verticalCenter
      x: 7
      spacing: 6
      JpText { text: "決議"; font.pixelSize: 13; font.weight: Font.Black; anchors.verticalCenter: parent.verticalCenter }
      MonoText { text: "RESOLUTION"; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.5; anchors.verticalCenter: parent.verticalCenter }
    }
  }
  ChamferBox {
    id: resBox
    x: scr.rcX; y: scr.by + 25
    width: scr.rcW; height: 82
    readonly property bool solid: scr.unanimous || (scr.nNo > scr.nOk && scr.blinkOn)
    readonly property string ink: solid ? Pal.ink : scr.resCol
    cuts: [0, 0, 14, 0]
    fillColor: solid ? scr.resCol : Pal.ink
    fillAlpha: solid ? 0.92 : 0.85
    strokeColor: scr.resCol
    lineWidth: 2
    JpText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 1
      text: scr.resKanji
      font.pixelSize: scr.resKanji.length > 2 ? 26 : 34
      font.weight: Font.Black
      color: resBox.ink
    }
    MonoText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 48
      text: scr.resText
      font.pixelSize: 7
      font.weight: Font.Bold
      font.letterSpacing: 1
      color: resBox.ink
    }
    Rectangle {
      x: 8; y: 60; width: parent.width - 16; height: 1
      color: resBox.ink
      opacity: 0.6
    }
    MonoText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 65
      text: "DELIBERATION " + scr.nOk + ":" + scr.nNo
      font.pixelSize: 8
      font.weight: Font.Bold
      font.letterSpacing: 1.3
      color: resBox.ink
    }
  }

  // ------------------------------------------------------------------ TALLY
  NervPanel {
    id: tally
    x: scr.rcX; y: scr.by + 113
    width: scr.rcW; height: 124
    title: "TALLY"
    jp: "投票集計"
    header: 13
    cut: 8
    fill: Qt.rgba(0.07, 0.047, 0.024, 0.55)
    Column {
      width: tally.body.width
      spacing: 3
      Repeater {
        model: [["MELCHIOR·1", 0], ["BALTHASAR·2", 1], ["CASPER·3", 2]]
        Column {
          id: trow
          required property var modelData
          readonly property var vv: scr.magi.votes[modelData[1]]
          readonly property var hist: scr.magi.history[modelData[1]]
          width: parent.width
          spacing: 2
          Item {
            width: parent.width; height: 11
            MonoText { anchors.verticalCenter: parent.verticalCenter; text: trow.modelData[0]; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1 }
            ChamferBox {
              anchors.right: parent.right
              width: 26; height: 11
              cuts: [0, 4, 0, 4]
              fillColor: Pal.voteColor(trow.vv)
              JpText {
                anchors.centerIn: parent
                text: trow.vv === true ? "承認" : (trow.vv === false ? "否決" : "待機")
                font.pixelSize: 8
                font.weight: Font.Black
                color: Pal.ink
              }
            }
          }
          Row {
            spacing: 1.5
            Repeater {
              model: scr.magi.histMax
              Rectangle {
                required property int index
                readonly property int k: trow.hist.length - scr.magi.histMax + index
                readonly property var hv: k >= 0 ? trow.hist[k] : undefined
                width: Math.floor((tally.body.width - 1.5 * (scr.magi.histMax - 1)) / scr.magi.histMax * 2) / 2
                height: 6
                color: hv === true ? Pal.green : (hv === false ? Pal.red : Pal.graphite)
                opacity: hv === undefined || hv === null ? 0.5 : 0.9
              }
            }
          }
        }
      }
      Rectangle { width: parent.width; height: 1; color: Pal.orange; opacity: 0.4 }
      Item {
        width: parent.width; height: 18
        Row {
          spacing: 4
          Column {
            JpText { text: "承認"; color: Pal.green; font.pixelSize: 8 }
            MonoText { text: "APPROVE"; color: Pal.green; font.pixelSize: 6; font.letterSpacing: 0.6 }
          }
          MonoText { text: Stats.pad(scr.magi.totalOk % 1000, 3); color: Pal.green; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 0 }
        }
        Row {
          anchors.right: parent.right
          spacing: 4
          Column {
            JpText { text: "否決"; color: Pal.red; font.pixelSize: 8 }
            MonoText { text: "REJECT"; color: Pal.red; font.pixelSize: 6; font.letterSpacing: 0.6 }
          }
          MonoText { text: Stats.pad(scr.magi.totalNo % 1000, 3); color: Pal.red; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 0 }
        }
      }
    }
  }

  // ------------------------------------------------------------------ SYS LOG (hex scroll)
  NervPanel {
    id: logPanel
    x: scr.rcX; y: tally.y + tally.height + 6
    width: scr.rcW; height: scr.by + scr.bh - y
    title: "SYS LOG"
    jp: "処理記録"
    header: 13
    cut: 8
    fill: Qt.rgba(0.07, 0.047, 0.024, 0.55)

  }

  }

  // the three MAGI blocks: one layer each, so a meter / hex cell easing after a sample only
  // re-renders its own block, not the whole static layer
  // ------------------------------------------------------------------ BALTHASAR·2 (memory)
  MagiBlock {
    x: scr.balX; y: scr.by
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.ceil(width * scr.pxScale), Math.ceil(height * scr.pxScale))
    width: scr.blkW; height: scr.blkH
    name: "BALTHASAR·2"
    jpName: "バルタザール"
    headTop: true
    headH: 18
    cuts: [6, 6, 24, 24]
    vote: scr.magi.votes[1]
    flash: scr.magi.flips[1]

    Row {
      MonoText { text: "MEMORY"; font.weight: Font.Bold }
      JpText { text: "  記憶"; font.pixelSize: 8 }
    }
    MonoText {
      anchors.right: parent.right
      text: Stats.gib(scr.magi.memTotal) + " GIB"
      opacity: 0.8
    }
    MonoText {
      y: 12
      text: Stats.pct(scr.magi.mem)
      font.pixelSize: 22
      font.weight: Font.Bold
      font.letterSpacing: 1
      color: scr.magi.mem > Pal.HOT ? Pal.red : Pal.amber
    }
    Column {
      anchors.right: parent.right
      y: 16
      MonoText { anchors.right: parent.right; text: "USED " + Stats.gib(scr.magi.memUsed); font.pixelSize: 8 }
      MonoText { anchors.right: parent.right; text: "CACHE " + Stats.gib(scr.magi.memCache); font.pixelSize: 8; opacity: 0.75 }
    }
    SegMeter {
      y: 44
      width: parent.width; height: 14
      count: 24
      value: scr.magi.mem
    }
    Row {
      y: 63
      spacing: 6
      MonoText { text: "SWAP"; font.pixelSize: 8; opacity: 0.85 }
      MonoText { text: Stats.gib(scr.magi.swapUsed) + "/" + Stats.gib(scr.magi.swapTotal) + " GIB"; font.pixelSize: 8 }
    }
    SegMeter {
      y: 76
      width: parent.width; height: 5
      count: 24
      value: scr.magi.swapTotal > 0 ? scr.magi.swapUsed / scr.magi.swapTotal : 0
      onColor: Pal.ash
    }
    MonoText {
      x: 22
      y: 88
      text: "LOAD " + Stats.pct(scr.magi.mem) + "  " + (scr.magi.votes[1] === true ? "APPROVE" : (scr.magi.votes[1] === false ? "REJECT" : "STANDBY"))
      font.pixelSize: 7
      opacity: 0.6
    }
  }

  // ------------------------------------------------------------------ CASPER·3 (GPU)
  MagiBlock {
    id: casper
    x: scr.casX; y: scr.lowY
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.ceil(width * scr.pxScale), Math.ceil(height * scr.pxScale))
    width: scr.blkW; height: scr.blkH
    name: "CASPER·3"
    jpName: "カスパー"
    headTop: false
    headH: 18
    cuts: [6, 24, 6, 6]
    vote: scr.magi.votes[2]
    flash: scr.magi.flips[2]

    readonly property var g: scr.magi.gpu
    readonly property bool live: g.src === "nvidia" || g.src === "amdgpu"

    Row {
      MonoText { text: "GRAPHICS"; font.weight: Font.Bold }
      JpText { text: "  画像演算"; font.pixelSize: 8 }
    }
    MonoText {
      y: 12
      width: parent.width - 20
      elide: Text.ElideRight
      text: casper.g.name.replace(/NVIDIA GeForce /i, "").replace(/ GPU$/i, "") || "---"
      font.pixelSize: 7
      opacity: 0.75
    }

    Item {
      y: 27
      width: parent.width; height: 80
      visible: casper.live
      MonoText { y: 0; text: "UTIL"; font.pixelSize: 8 }
      SegMeter { x: 32; y: 1; width: parent.width - 32 - 36; height: 8; count: 14; value: casper.g.util / 100 }
      MonoText { anchors.right: parent.right; y: -2; text: Stats.pad(casper.g.util, 3) + "%"; font.pixelSize: 11; font.weight: Font.Bold; color: Pal.amber; font.letterSpacing: 0.3 }
      MonoText { y: 15; text: "VRAM"; font.pixelSize: 8 }
      SegMeter { x: 32; y: 16; width: parent.width - 32 - 36; height: 8; count: 14; value: casper.g.total > 0 ? casper.g.used / casper.g.total : 0 }
      MonoText { anchors.right: parent.right; y: 15; text: (casper.g.used / 1024).toFixed(1) + "/" + (casper.g.total / 1024).toFixed(0) + "G"; font.pixelSize: 7; font.letterSpacing: 0.3 }
      Row {
        y: 32
        spacing: 10
        Column {
          MonoText { text: "TEMP 温度"; font.pixelSize: 7; opacity: 0.75 }
          MonoText {
            text: isNaN(casper.g.temp) ? "--°C" : casper.g.temp.toFixed(0) + "°C"
            font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 0.3
            color: casper.g.temp >= 85 ? Pal.red : Pal.amber
          }
        }
        Column {
          MonoText { text: "POWER 電力"; font.pixelSize: 7; opacity: 0.75 }
          MonoText {
            text: isNaN(casper.g.power) ? "--W" : casper.g.power.toFixed(1) + "W"
            font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 0.3
            color: Pal.amber
          }
        }
      }
      MonoText {
        y: 66
        text: "LINK " + (casper.g.src === "nvidia" ? "NV-SMI" : "SYSFS") + " · D0 ACTIVE"
        font.pixelSize: 7
        opacity: 0.6
      }
    }

    Column {
      y: 28
      visible: !casper.live
      spacing: 2
      JpText {
        text: casper.g.src === "sleep" ? "休止" : "接続なし"
        font.pixelSize: 26
        font.weight: Font.Black
        color: casper.g.src === "sleep" ? Pal.ash : Pal.red
      }
      MonoText {
        text: casper.g.src === "sleep" ? "DGPU IN D3 · NOT WOKEN" : (casper.g.src === "wait" ? "PROBING UNIT" : "NO LINK · ABSTAINS")
        font.pixelSize: 7
        color: Pal.ash
      }
    }
  }

  // ------------------------------------------------------------------ MELCHIOR·1 (CPU)
  MagiBlock {
    id: mel
    x: scr.melX; y: scr.lowY
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.ceil(width * scr.pxScale), Math.ceil(height * scr.pxScale))
    width: scr.blkW; height: scr.blkH
    name: "MELCHIOR·1"
    jpName: "メルキオール"
    headTop: false
    headH: 18
    cuts: [24, 6, 6, 6]
    vote: scr.magi.votes[0]
    flash: scr.magi.flips[0]

    readonly property int peak: {
      var c = scr.magi.cores, k = 0
      for (var i = 1; i < c.length; i++) if (c[i] > c[k]) k = i
      return k
    }

    Row {
      x: 18
      MonoText { text: "PROCESSOR"; font.weight: Font.Bold }
      JpText { text: "  演算"; font.pixelSize: 8 }
    }
    MonoText {
      anchors.right: parent.right
      text: scr.magi.cores.length + " THR"
      opacity: 0.8
    }
    HexCores {
      // two rows of n/2 cells, radius fitted to the block body
      readonly property int half: Math.max(1, Math.ceil(scr.magi.cores.length / 2))
      r: Math.min(11, (parent.width - 2) / (Math.sqrt(3) * (half + 0.5)))
      x: Math.round((parent.width - width) / 2)
      y: 13
      loads: scr.magi.cores
    }
    SegMeter {
      y: 52
      width: parent.width; height: 6
      count: 24
      value: scr.magi.cpu
    }
    MonoText {
      y: 61
      text: Stats.pct(scr.magi.cpu)
      font.pixelSize: 19
      font.weight: Font.Bold
      font.letterSpacing: 1
      color: scr.magi.cpu > Pal.HOT ? Pal.red : Pal.amber
    }
    Column {
      anchors.right: parent.right
      y: 63
      MonoText {
        anchors.right: parent.right
        text: "TEMP " + (isNaN(scr.magi.cpuTemp) ? "--" : scr.magi.cpuTemp.toFixed(0)) + "°C"
        font.pixelSize: 8
        font.weight: Font.Bold
        color: scr.magi.cpuTemp >= 90 ? Pal.red : Pal.orange
      }
      MonoText {
        anchors.right: parent.right
        text: "LOAD " + scr.magi.loadAvg[0]
        font.pixelSize: 7
        opacity: 0.75
      }
    }
    MonoText {
      y: 88
      text: scr.magi.cores.length > 0
        ? "PEAK T" + Stats.pad(mel.peak, 2) + " " + Stats.pct(scr.magi.cores[mel.peak])
        : "PEAK ---"
      font.pixelSize: 7
      opacity: 0.6
    }
  }

  // ------------------------------------------------------------------ SYS LOG rows (sub-pixel scroll)
    Item {
      id: logBox
      x: logPanel.x + logPanel.body.x
      y: logPanel.y + logPanel.body.y
      width: logPanel.body.width
      height: logPanel.body.height
      clip: true
      readonly property real rowH: 10
      readonly property int rows: scr.magi.logMax
      // scroll offset: jumps down by one row per pushed row (so the text rebind is invisible),
      // then the frame clock drains it — the column glides up sub-pixel instead of jumping.
      property real shift: 0
      property int seenSeq: 0
      Component.onCompleted: seenSeq = scr.magi.logSeq
      Connections {
        target: scr.magi
        function onLogSeqChanged() {
          var d = scr.magi.logSeq - logBox.seenSeq
          logBox.seenSeq = scr.magi.logSeq
          logBox.shift = (scr.magi.live && scr.visible) ? Math.min(logBox.shift + d * logBox.rowH, logBox.rowH * 6) : 0
        }
      }
      Item {
        id: rowsClip
        width: logBox.width
        height: logBox.height - 12
        clip: true
      Item {
        // the rows are one layer that only re-renders when their text changes (2.5 Hz);
        // per frame just this quad moves
        y: logBox.shift
        width: logBox.width
        height: rowsClip.height
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(Math.ceil(width * scr.pxScale), Math.ceil(height * scr.pxScale))
      // fixed pool of rows, newest at the bottom; only their text/colour rebinds per tick
      Repeater {
        model: logBox.rows
        MonoText {
          required property int index
          readonly property var e: {
            var L = scr.magi.logRows, k = L.length - logBox.rows + index
            return k >= 0 ? L[k] : null
          }
          y: rowsClip.height - (logBox.rows - index) * logBox.rowH
          width: logBox.width
          renderType: Text.QtRendering
          visible: e !== null && y > -2 * logBox.rowH
          text: e ? e.t : ""
          font.pixelSize: 7
          font.weight: Font.Medium
          font.letterSpacing: 0.4
          color: !e ? Pal.orange : (e.k === "ok" ? Pal.green : (e.k === "no" ? Pal.red : (e.k === "sys" ? Pal.amber : Pal.orange)))
          opacity: e && e.k === "hex" ? 0.3 + 0.6 * (index / logBox.rows) : 1
        }
      }
      }
      }
      MonoText {
        id: prompt
        x: 0; y: logBox.height - 11
        text: "MAGI>"
        font.pixelSize: 7
        opacity: 0.7
      }
      Rectangle {
        x: prompt.implicitWidth + 3; y: logBox.height - 10
        width: 5; height: 8
        color: Pal.orange
        visible: scr.blinkOn
      }
    }
  // ------------------------------------------------------------------ CRT scanlines (painted once)
  Canvas {
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = "rgba(0,0,0,0.22)"
      for (var y = 0; y < height; y += 2) ctx.fillRect(0, y + 1, width, 0.6)
    }
  }
}
