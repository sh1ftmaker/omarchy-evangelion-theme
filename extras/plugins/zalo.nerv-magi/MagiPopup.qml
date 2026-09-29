import QtQuick
import "Palette.js" as Pal
import "Draw.js" as Draw
import "Stats.js" as Stats

// The MAGI deliberation screen. Fixed 760x500 layout; all live values come from
// `magi` (the bar widget, which owns polling). Everything steps, nothing tweens.
Item {
  id: pop
  required property var magi
  width: 760
  height: 500

  readonly property int nOk: (magi.votes[0] === true ? 1 : 0) + (magi.votes[1] === true ? 1 : 0) + (magi.votes[2] === true ? 1 : 0)
  readonly property int nNo: (magi.votes[0] === false ? 1 : 0) + (magi.votes[1] === false ? 1 : 0) + (magi.votes[2] === false ? 1 : 0)
  readonly property int nVoters: nOk + nNo
  readonly property bool unanimous: nVoters > 0 && (nOk === nVoters || nNo === nVoters) && nVoters === 3
  readonly property string resKanji: nOk === 3 ? "可決" : (nNo === 3 ? "否決" : (nOk > nNo ? "承認" : (nNo > nOk ? "否決" : "審議中")))
  readonly property string resText: nOk === 3 ? "PASSED · UNANIMOUS" : (nNo === 3 ? "REJECTED · UNANIMOUS"
    : (nOk > nNo ? "APPROVED " + nOk + "/" + nVoters : (nNo > nOk ? "REJECTED " + nNo + "/" + nVoters : "DELIBERATING")))
  readonly property string resCol: nOk > nNo ? Pal.green : (nNo > nOk ? Pal.red : Pal.orange)
  readonly property bool blinkOn: magi.tick % 2 === 0
  readonly property string queryNo: Stats.pad(magi.query % 10000, 4)

  // The host card is a themed rounded rectangle; the MAGI frame draws its own
  // chamfered chrome, so make the card itself invisible.
  Component.onCompleted: {
    var card = parent
    for (var i = 0; card && i < 6; i++) {
      if (card.borderSpec !== undefined && card.radius !== undefined) {
        card.color = "transparent"
        card.radius = 0
        break
      }
      card = card.parent
    }
  }

  // ------------------------------------------------------------------ ground
  Canvas {
    id: ground
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var W = width, H = height
      Draw.chamfer(ctx, 0.75, 0.75, W - 1.5, H - 1.5, [0, 18, 0, 18])
      ctx.fillStyle = Pal.ink
      ctx.fill()
      ctx.strokeStyle = Pal.orange
      ctx.lineWidth = 1.5
      ctx.stroke()

      // faint hex ground behind the diagram
      ctx.save()
      ctx.beginPath(); ctx.rect(140, 52, 476, 406); ctx.clip()
      ctx.strokeStyle = Pal.graphite
      ctx.globalAlpha = 0.45
      ctx.lineWidth = 0.75
      var r = 13, dx = Math.sqrt(3) * r, dy = 1.5 * r
      for (var row = 0; row * dy < 420; row++) {
        for (var col = 0; col * dx < 500; col++) {
          Draw.hex(ctx, 140 + col * dx + (row % 2 ? dx / 2 : 0), 52 + row * dy, r - 1)
          ctx.stroke()
        }
      }
      ctx.restore()
      ctx.globalAlpha = 1

      // header rule with ticks
      ctx.fillStyle = Pal.orange
      ctx.fillRect(10, 45, W - 20, 1.5)
      ctx.globalAlpha = 0.6
      for (var x = 10; x <= W - 10; x += 12) ctx.fillRect(x, 46.5, 1, (x - 10) % 60 === 0 ? 5 : 2.5)
      ctx.globalAlpha = 1
      // footer rule
      ctx.fillRect(10, 466, W - 20, 1)

      // MAGI bus bars (under the blocks)
      var bars = [[300, 190, 330, 316], [456, 190, 426, 316], [340, 382, 416, 382]]
      ctx.lineCap = "butt"
      for (var i = 0; i < bars.length; i++) {
        var b = bars[i]
        ctx.strokeStyle = Pal.orange
        ctx.lineWidth = 11
        ctx.beginPath(); ctx.moveTo(b[0], b[1]); ctx.lineTo(b[2], b[3]); ctx.stroke()
        ctx.strokeStyle = Pal.ink
        ctx.lineWidth = 4
        ctx.beginPath(); ctx.moveTo(b[0], b[1]); ctx.lineTo(b[2], b[3]); ctx.stroke()
      }
    }
  }

  // data packets stepping along the bus bars, one step per scroll tick
  Repeater {
    model: 9
    Rectangle {
      required property int index
      readonly property var bus: [[300, 204, 330, 306], [456, 204, 426, 306], [352, 382, 404, 382]][Math.floor(index / 3)]
      readonly property real ph: (((pop.magi.tick + (index % 3) * 3) % 9) / 9)
      readonly property real dir: Math.floor(index / 3) === 1 ? 1 - ph : ph
      width: 4; height: 4
      color: Pal.amber
      x: Math.round(bus[0] + (bus[2] - bus[0]) * dir - 2)
      y: Math.round(bus[1] + (bus[3] - bus[1]) * dir - 2)
    }
  }

  // ------------------------------------------------------------------ header
  ChamferBox {
    x: 10; y: 7; width: 40; height: 32
    cuts: [0, 10, 0, 0]
    fillColor: Pal.orange
    MonoText {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: -3
      text: "02"
      color: Pal.ink
      font.pixelSize: 18
      font.weight: Font.Bold
      font.letterSpacing: 0
    }
  }
  Row {
    x: 60; y: 5
    spacing: 10
    MonoText {
      text: "MAGI SYSTEM"
      font.pixelSize: 15
      font.weight: Font.Bold
      font.letterSpacing: 4
    }
    JpText {
      anchors.baseline: parent.children[0].baseline
      text: "マギ・システム  審議中"
      font.pixelSize: 13
    }
  }
  Row {
    x: 60; y: 27
    spacing: 8
    opacity: 0.75
    MonoText {
      text: "SUPERCOMPUTER DELIBERATION // 3 UNITS ONLINE // QUERY " + pop.queryNo + " //"
      font.pixelSize: 8
      font.letterSpacing: 1.6
    }
    JpText { text: "第7世代有機コンピュータ"; font.pixelSize: 8 }
  }

  // uptime (right)
  Column {
    anchors.right: parent.right
    anchors.rightMargin: 24
    y: 5
    spacing: 0
    Row {
      anchors.right: parent.right
      spacing: 6
      MonoText { text: "UPTIME"; font.pixelSize: 8; opacity: 0.8 }
      JpText { text: "稼働時間"; font.pixelSize: 8; opacity: 0.8 }
    }
    Row {
      anchors.right: parent.right
      spacing: 6
      MonoText {
        anchors.baseline: upClock.baseline
        text: "D+" + Stats.pad(Stats.uptime(pop.magi.uptime).days, 3)
        font.pixelSize: 10
        color: Pal.orange
      }
      MonoText {
        id: upClock
        text: Stats.uptime(pop.magi.uptime).clock
        font.pixelSize: 21
        font.weight: Font.Bold
        font.letterSpacing: 1
        color: Pal.amber
      }
    }
  }

  // ------------------------------------------------------------ system log
  NervPanel {
    x: 10; y: 54; width: 122; height: 402
    title: "SYS LOG"
    jp: "処理記録"
    cut: 12
    Column {
      anchors.fill: parent
      clip: true
      spacing: 0
      Repeater {
        model: pop.magi.logRows
        MonoText {
          required property var modelData
          required property int index
          width: parent.width
          height: 11.4
          text: modelData.t
          font.pixelSize: 8
          font.weight: Font.Medium
          font.letterSpacing: 0.4
          elide: Text.ElideNone
          color: modelData.k === "ok" ? Pal.green : (modelData.k === "no" ? Pal.red : (modelData.k === "sys" ? Pal.amber : Pal.orange))
          opacity: modelData.k === "hex" ? 0.3 + 0.6 * (index / Math.max(1, pop.magi.logRows.length)) : 1
        }
      }
      Rectangle {
        width: 6; height: 9
        color: Pal.orange
        visible: pop.blinkOn
      }
    }
  }

  // ------------------------------------------------------------- appeal box
  ChamferBox {
    x: 142; y: 56; width: 124; height: 26
    cuts: [0, 8, 0, 8]
    fillColor: Pal.ink
    strokeColor: Pal.orange
    lineWidth: 1.5
    Row {
      anchors.verticalCenter: parent.verticalCenter
      x: 8
      spacing: 8
      JpText { text: "提訴"; font.pixelSize: 16; font.weight: Font.Black; anchors.verticalCenter: parent.verticalCenter }
      MonoText { text: "APPEAL"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 2.5; anchors.verticalCenter: parent.verticalCenter }
    }
  }
  Column {
    x: 146; y: 92
    spacing: 2
    Repeater {
      model: [
        ["CODE", "473"],
        ["FILE", "MAGI_SYS"],
        ["QUERY", pop.queryNo],
        ["SUBJECT", "WORKLOAD"],
        ["PRIORITY", "AAA"],
        ["EX_MODE", "OFF"],
        ["QUORUM", pop.nVoters + "/3"]
      ]
      Row {
        required property var modelData
        MonoText { width: 58; text: modelData[0]; font.pixelSize: 8; font.letterSpacing: 1.2; opacity: 0.85 }
        MonoText { text: ": " + modelData[1]; font.pixelSize: 8; font.letterSpacing: 1.2 }
      }
    }
  }

  // --------------------------------------------------------- resolution box
  ChamferBox {
    x: 490; y: 56; width: 124; height: 26
    cuts: [0, 8, 0, 8]
    fillColor: Pal.ink
    strokeColor: Pal.orange
    lineWidth: 1.5
    Row {
      anchors.verticalCenter: parent.verticalCenter
      x: 8
      spacing: 6
      JpText { text: "決議"; font.pixelSize: 16; font.weight: Font.Black; anchors.verticalCenter: parent.verticalCenter }
      MonoText { text: "RESOLUTION"; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.2; anchors.verticalCenter: parent.verticalCenter }
    }
  }
  ChamferBox {
    id: resBox
    x: 490; y: 90; width: 124; height: 110
    readonly property bool solid: pop.unanimous || (pop.nNo > pop.nOk && pop.blinkOn)
    cuts: [0, 0, 16, 0]
    fillColor: solid ? pop.resCol : Pal.ink
    fillAlpha: solid ? 0.92 : 0.85
    strokeColor: pop.resCol
    lineWidth: 2
    JpText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 6
      text: pop.resKanji
      font.pixelSize: pop.resKanji.length > 2 ? 30 : 40
      font.weight: Font.Black
      color: resBox.solid ? Pal.ink : pop.resCol
    }
    MonoText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 62
      text: pop.resText
      font.pixelSize: 8
      font.weight: Font.Bold
      font.letterSpacing: 1.2
      color: resBox.solid ? Pal.ink : pop.resCol
    }
    Rectangle {
      x: 8; y: 77; width: parent.width - 16; height: 1
      color: resBox.solid ? Pal.ink : pop.resCol
      opacity: 0.6
    }
    MonoText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 83
      text: "DELIBERATION " + pop.nOk + ":" + pop.nNo
      font.pixelSize: 8
      font.weight: Font.Bold
      font.letterSpacing: 1.4
      color: resBox.solid ? Pal.ink : pop.resCol
    }
  }

  // ----------------------------------------------------------- MAGI centre
  Item {
    id: centre
    x: 318; y: 222; width: 120; height: 80
    Text {
      id: magiTitle
      textFormat: Text.PlainText
      text: "MAGI"
      color: Pal.orange
      font.family: Pal.serif
      font.pixelSize: 58
      font.weight: 600
      font.bold: true
      x: (centre.width - implicitWidth * 0.6) / 2
      y: -8
      transform: Scale { xScale: 0.6; yScale: 1 }
    }
    MonoText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 54
      text: "SUPERCOMPUTER"
      font.pixelSize: 7
      font.letterSpacing: 2
    }
    JpText {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 65
      text: "三系統合議制"
      font.pixelSize: 8
      font.weight: Font.Medium
      opacity: 0.85
    }
  }

  // ------------------------------------------------- BALTHASAR·2 (memory)
  MagiBlock {
    x: 274; y: 56; width: 208; height: 146
    name: "BALTHASAR·2"
    jpName: "バルタザール"
    headTop: true
    cuts: [6, 6, 26, 26]
    vote: pop.magi.votes[1]
    flash: pop.magi.flips[1]

    Row {
      width: parent.width
      MonoText { text: "MEMORY"; font.weight: Font.Bold }
      JpText { text: "  記憶"; font.pixelSize: 8 }
    }
    MonoText {
      anchors.right: parent.right
      text: Stats.gib(pop.magi.memTotal) + " GIB"
      opacity: 0.8
    }
    MonoText {
      y: 13
      text: Stats.pct(pop.magi.mem)
      font.pixelSize: 22
      font.weight: Font.Bold
      font.letterSpacing: 1
      color: pop.magi.mem > Pal.HOT ? Pal.red : Pal.amber
    }
    Column {
      anchors.right: parent.right
      y: 17
      MonoText { anchors.right: parent.right; text: "USED " + Stats.gib(pop.magi.memUsed); font.pixelSize: 8 }
      MonoText { anchors.right: parent.right; text: "CACHE " + Stats.gib(pop.magi.memCache); font.pixelSize: 8; opacity: 0.75 }
    }
    SegMeter {
      y: 46
      width: parent.width; height: 16
      count: 24
      value: pop.magi.mem
      onColor: Pal.orange
    }
    Row {
      y: 70
      spacing: 6
      MonoText { text: "SWAP"; font.pixelSize: 8; opacity: 0.85 }
      MonoText {
        text: Stats.gib(pop.magi.swapUsed) + "/" + Stats.gib(pop.magi.swapTotal) + " GIB"
        font.pixelSize: 8
      }
    }
    SegMeter {
      y: 84
      width: parent.width; height: 5
      count: 24
      value: pop.magi.swapTotal > 0 ? pop.magi.swapUsed / pop.magi.swapTotal : 0
      onColor: Pal.ash
    }
    MonoText {
      x: 20
      y: 94
      text: "LOAD " + Stats.pct(pop.magi.mem) + "  " + (pop.magi.votes[1] === true ? "APPROVE" : "REJECT")
      font.pixelSize: 8
      opacity: 0.6
    }
  }

  // ------------------------------------------------------- CASPER·3 (GPU)
  MagiBlock {
    x: 142; y: 306; width: 208; height: 150
    id: casper
    name: "CASPER·3"
    jpName: "カスパー"
    headTop: false
    cuts: [6, 26, 6, 6]
    vote: pop.magi.votes[2]
    flash: pop.magi.flips[2]

    readonly property var g: pop.magi.gpu
    readonly property bool live: g.src === "nvidia" || g.src === "amdgpu"

    Row {
      MonoText { text: "GRAPHICS"; font.weight: Font.Bold }
      JpText { text: "  画像演算"; font.pixelSize: 8 }
    }
    MonoText {
      y: 12
      width: 150
      elide: Text.ElideRight
      text: casper.g.name.replace(/NVIDIA GeForce /i, "").replace(/ GPU$/i, "") || "---"
      font.pixelSize: 8
      opacity: 0.75
    }

    // live readouts
    Item {
      y: 26
      width: parent.width; height: 80
      visible: casper.live
            MonoText { y: 0; text: "UTIL"; font.pixelSize: 8 }
      SegMeter { x: 34; y: 1; width: 110; height: 9; count: 16; value: casper.g.util / 100 }
      MonoText { anchors.right: parent.right; y: -3; text: Stats.pad(casper.g.util, 3) + "%"; font.pixelSize: 12; font.weight: Font.Bold; color: Pal.amber; font.letterSpacing: 0.5 }
      MonoText { y: 18; text: "VRAM"; font.pixelSize: 8 }
      SegMeter { x: 34; y: 19; width: 110; height: 9; count: 16; value: casper.g.total > 0 ? casper.g.used / casper.g.total : 0 }
      MonoText { anchors.right: parent.right; y: 18; text: (casper.g.used / 1024).toFixed(1) + "/" + (casper.g.total / 1024).toFixed(0) + "G"; font.pixelSize: 8; font.letterSpacing: 0.5 }
      Row {
        y: 38
        spacing: 16
        Column {
          MonoText { text: "TEMP 温度"; font.pixelSize: 8; opacity: 0.75 }
          MonoText {
            text: isNaN(casper.g.temp) ? "--°C" : casper.g.temp.toFixed(0) + "°C"
            font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 0.5
            color: casper.g.temp >= 85 ? Pal.red : Pal.amber
          }
        }
        Column {
          MonoText { text: "POWER 電力"; font.pixelSize: 8; opacity: 0.75 }
          MonoText {
            text: isNaN(casper.g.power) ? "--W" : casper.g.power.toFixed(1) + "W"
            font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 0.5
            color: Pal.amber
          }
        }
        Column {
          MonoText { text: "LINK"; font.pixelSize: 8; opacity: 0.75 }
          MonoText {
            text: casper.g.src === "nvidia" ? "NV-SMI" : "SYSFS"
            font.pixelSize: 9; font.weight: Font.Bold
            topPadding: 3
          }
        }
      }
    }

    // offline / asleep
    Column {
      y: 30
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
        font.pixelSize: 8
        color: Pal.ash
      }
    }
  }

  // ----------------------------------------------------- MELCHIOR·1 (CPU)
  MagiBlock {
    x: 406; y: 306; width: 208; height: 150
    name: "MELCHIOR·1"
    jpName: "メルキオール"
    headTop: false
    cuts: [26, 6, 6, 6]
    vote: pop.magi.votes[0]
    flash: pop.magi.flips[0]

    Row {
      x: 18
      MonoText { text: "PROCESSOR"; font.weight: Font.Bold }
      JpText { text: "  演算"; font.pixelSize: 8 }
    }
    MonoText {
      anchors.right: parent.right
      text: pop.magi.cores.length + " THR"
      opacity: 0.8
    }
    HexCores {
      x: Math.round((parent.width - width) / 2)
      y: 14
      loads: pop.magi.cores
    }
    SegMeter {
      y: 62
      width: parent.width; height: 7
      count: 24
      value: pop.magi.cpu
    }
    MonoText {
      y: 72
      text: Stats.pct(pop.magi.cpu)
      font.pixelSize: 20
      font.weight: Font.Bold
      font.letterSpacing: 1
      color: pop.magi.cpu > Pal.HOT ? Pal.red : Pal.amber
    }
    Column {
      anchors.right: parent.right
      y: 74
      MonoText {
        anchors.right: parent.right
        text: "TEMP " + (isNaN(pop.magi.cpuTemp) ? "--" : pop.magi.cpuTemp.toFixed(1)) + "°C"
        font.pixelSize: 9
        font.weight: Font.Bold
        color: pop.magi.cpuTemp >= 90 ? Pal.red : Pal.orange
      }
      MonoText {
        anchors.right: parent.right
        text: "LOAD " + pop.magi.loadAvg[0]
        font.pixelSize: 8
        opacity: 0.75
      }
    }
  }

  // ------------------------------------------------------------ vote tally
  NervPanel {
    x: 626; y: 54; width: 124; height: 194
    title: "TALLY"
    jp: "投票集計"
    cut: 12
    Column {
      width: parent.width
      spacing: 5
      Repeater {
        model: [["MELCHIOR·1", 0], ["BALTHASAR·2", 1], ["CASPER·3", 2]]
        Column {
          required property var modelData
          readonly property var v: pop.magi.votes[modelData[1]]
          width: parent.width
          spacing: 3
          Item {
            width: parent.width; height: 12
            MonoText { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1 }
            ChamferBox {
              anchors.right: parent.right
              width: 28; height: 12
              cuts: [0, 4, 0, 4]
              fillColor: Pal.voteColor(parent.parent.v)
              JpText {
                anchors.centerIn: parent
                text: parent.parent.parent.v === true ? "承認" : (parent.parent.parent.v === false ? "否決" : "待機")
                font.pixelSize: 8
                font.weight: Font.Black
                color: Pal.ink
              }
            }
          }
          Row {
            spacing: 2
            Repeater {
              model: 12
              Rectangle {
                required property int index
                readonly property var hist: pop.magi.history[modelData[1]]
                readonly property int k: hist.length - 12 + index
                readonly property var hv: k >= 0 ? hist[k] : undefined
                width: 7.5; height: 7.5
                color: hv === true ? Pal.green : (hv === false ? Pal.red : Pal.graphite)
                opacity: hv === undefined || hv === null ? 0.5 : 0.9
              }
            }
          }
        }
      }
      Rectangle { width: parent.width; height: 1; color: Pal.orange; opacity: 0.4 }
      Row {
        spacing: 6
        Column {
          JpText { text: "承認"; color: Pal.green; font.pixelSize: 9 }
          MonoText { text: "APPROVE"; color: Pal.green; font.pixelSize: 7; font.letterSpacing: 1 }
        }
        MonoText { text: Stats.pad(pop.magi.totalOk % 1000, 3); color: Pal.green; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 0 }
      }
      Row {
        spacing: 6
        Column {
          JpText { text: "否決"; color: Pal.red; font.pixelSize: 9 }
          MonoText { text: "REJECT"; color: Pal.red; font.pixelSize: 7; font.letterSpacing: 1 }
        }
        MonoText { text: Stats.pad(pop.magi.totalNo % 1000, 3); color: Pal.red; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 0 }
      }
    }
  }

  // ---------------------------------------------------------------- system
  NervPanel {
    x: 626; y: 256; width: 124; height: 200
    title: "SYSTEM"
    jp: "系統"
    cut: 12
    Column {
      width: parent.width
      spacing: 5
      Repeater {
        model: [
          ["CPU TEMP", "中央温度", isNaN(pop.magi.cpuTemp) ? "--.-°C" : pop.magi.cpuTemp.toFixed(1) + "°C", pop.magi.cpuTemp >= 90],
          ["LOAD AVG", "負荷平均", pop.magi.loadAvg.join(" "), pop.magi.loadAvg[0] > pop.magi.cores.length],
          ["TASKS", "処理数", pop.magi.procs || "--", false],
          ["UPTIME", "稼働", Stats.uptime(pop.magi.uptime).days + "D " + Stats.uptime(pop.magi.uptime).clock.slice(0, 5), false]
        ]
        Column {
          required property var modelData
          width: parent.width
          Row {
            spacing: 5
            MonoText { text: modelData[0]; font.pixelSize: 7; opacity: 0.75 }
            JpText { text: modelData[1]; font.pixelSize: 7; opacity: 0.75 }
          }
          MonoText {
            text: modelData[2]
            font.pixelSize: modelData[2].length > 10 ? 10 : 13
            font.weight: Font.Bold
            font.letterSpacing: 0.5
            color: modelData[3] ? Pal.red : Pal.amber
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- footer
  ChamferBox {
    x: 10; y: 472; width: 146; height: 20
    cuts: [0, 0, 8, 0]
    fillColor: Pal.orange
    Row {
      x: 7
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6
      MonoText { text: "NERV HQ"; color: Pal.ink; font.weight: Font.Bold; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
      JpText { text: "中央作戦室"; color: Pal.ink; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
    }
  }
  Item {
    id: tickerBox
    x: 166; y: 472; width: 580; height: 20
    clip: true
    readonly property string msg: "MAGI DELIBERATION IN PROGRESS // MELCHIOR·1 CPU " + Stats.pct(pop.magi.cpu)
      + "  BALTHASAR·2 MEM " + Stats.pct(pop.magi.mem)
      + "  CASPER·3 GPU " + Stats.pct(pop.magi.gpuLoad)
      + " // QUERY " + pop.queryNo + ": ACCEPT NEW WORKLOAD // 審議中 // PRIORITY AAA // GEHIRN LEGACY CODE 473 // "
    MonoText {
      id: tickerText
      anchors.verticalCenter: parent.verticalCenter
      text: tickerBox.msg + tickerBox.msg + tickerBox.msg
      font.pixelSize: 9
      opacity: 0.7
      readonly property real adv: implicitWidth / Math.max(1, text.length)
      x: -((pop.magi.tick * 2) % Math.max(1, tickerBox.msg.length)) * adv
    }
  }

  // ------------------------------------------------------------- scanlines
  Canvas {
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = "#000000"
      ctx.globalAlpha = 0.16
      for (var y = 0; y < height; y += 3) ctx.fillRect(0, y, width, 1)
    }
  }
}
