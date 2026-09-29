import QtQuick

// The NERV status wall: a 3-row grid of mini instruments under the radar.
//   row 1  STORAGE 記憶装置 (segmented disk meters)   | THERMAL 温度 (temps, red warnings)
//   row 2  UPTIME 稼働時間 (7-segment) + power         | MAGI 演算 (cpu/mem + hex filler)
//   row 3  LOCAL TIME 現地時刻: TOKYO-3 title card, 7-seg clock, hazard band, system ticker
Item {
  id: wall

  required property var hud

  // width comes from the parent; the height is the wall's natural height (the radar takes the rest)
  width: 360
  height: 354
  // column split (206 | 148 at the 360 px design width)
  readonly property real lw: Math.round((width - 6) * 206 / 354)
  readonly property real rw: width - 6 - lw
  readonly property color fill: hud.panelFill

  readonly property color cOrange: "#FF7A00"
  readonly property color cAmber: "#FFB000"
  readonly property color cRed: "#FF1A1A"
  readonly property color cBone: "#FFE9C8"
  readonly property color cAsh: "#9C6A2E"
  readonly property color cInk: "#050403"

  function two(v) { return (v < 10 ? "0" : "") + v }
  function mountName(m) {
    if (m === "/") return "ROOT /"
    var parts = m.split("/")
    return parts[parts.length - 1].toUpperCase()
  }
  function fmtSize(b) {
    if (b >= 1e12) return (b / 1e12).toFixed(1) + "T"
    return Math.round(b / 1e9) + "G"
  }

  // Static layer: storage / uptime / clock flattened into one texture, re-rendered only when a
  // sample, a 1 Hz tick or a blink changes something inside. The per-frame movers (hazard drift, ticker tape) sit above.
  Item {
    id: still
    anchors.fill: parent
    layer.enabled: true

    // ================================================================ row 1
    NervPanel {
      id: storage
      x: 0; y: 0; width: wall.lw; height: 104
      title: "STORAGE"; jp: "記憶装置"
      fill: wall.fill
      alarm: wall.hud.diskHot && wall.hud.blinkOn

      Column {
        width: parent.width
        spacing: 4
        Repeater {
          model: wall.hud.disks.slice(0, 4)
          delegate: Column {
            id: drow
            required property var modelData
            readonly property bool hot: modelData.pct >= 90
            width: storage.body.width
            spacing: 1
            Item {
              width: parent.width; height: 9
              Mono { text: wall.mountName(drow.modelData.mnt); font.pixelSize: 7; color: drow.hot ? wall.cRed : wall.cOrange }
              Mono {
                x: 70
                text: drow.modelData.fs.toUpperCase() + " " + wall.fmtSize(drow.modelData.size)
                font.pixelSize: 7; opacity: 0.6; font.letterSpacing: 0.6
              }
              Mono {
                anchors.right: parent.right
                text: drow.modelData.pct.toFixed(1) + "%"
                font.pixelSize: 8; font.weight: Font.Bold
                color: drow.hot ? wall.cRed : wall.cAmber
              }
            }
            SegMeter {
              width: parent.width; height: 5; segments: 30
              value: drow.modelData.pct / 100; hotFrom: 0.85
            }
          }
        }
      }
    }

    Item {
      x: 6; y: 88; width: wall.lw - 12; height: 10
      Mono {
        text: "VOLUMES " + wall.hud.disks.length + "  //  " + (wall.hud.diskHot ? "CAPACITY CRITICAL" : "CAPACITY NOMINAL")
        font.pixelSize: 7; opacity: 0.6; font.letterSpacing: 0.8
        color: wall.hud.diskHot ? wall.cRed : wall.cOrange
      }
      Jp { anchors.right: parent.right; y: -1; text: wall.hud.diskHot ? "容量警告" : "正常"; font.pixelSize: 7; opacity: 0.7 }
    }


    // ================================================================ row 2
    NervPanel {
      id: uptime
      x: 0; y: 110; width: wall.lw; height: 98
      title: "UPTIME"; jp: "稼働時間"
      fill: wall.fill

      readonly property int up: Math.floor(wall.hud.uptime)
      Row {
        spacing: 6
        Column {
          spacing: 1
          Mono { text: "DAY"; font.pixelSize: 7; opacity: 0.8 }
          SevenSeg {
            text: { var d = Math.floor(uptime.up / 86400); return (d < 10 ? "00" : d < 100 ? "0" : "") + d }
            digitHeight: 14; color: wall.cOrange
          }
        }
        Column {
          spacing: 1
          Mono { text: "HRS : MIN : SEC"; font.pixelSize: 7; opacity: 0.8 }
          SevenSeg {
            text: wall.two(Math.floor(uptime.up % 86400 / 3600)) + ":" + wall.two(Math.floor(uptime.up % 3600 / 60)) + ":" + wall.two(uptime.up % 60)
            digitHeight: 26; color: wall.cAmber
          }
        }
      }
      // power: external (AC) or internal (battery) with activity limit
      Item {
        y: 44; width: parent.width; height: 30
        readonly property bool ac: wall.hud.power.ac !== false
        Rectangle {
          id: pwrTag
          width: 44; height: 12
          color: parent.ac ? wall.cOrange : (wall.hud.power.bat < 20 && wall.hud.blinkOn ? wall.cRed : wall.cAmber)
          Mono { anchors.centerIn: parent; text: parent.parent.ac ? "EXT" : "INT"; color: wall.cInk; font.weight: Font.Bold; font.pixelSize: 8 }
        }
        Column {
          x: 50; y: -1; spacing: 0
          Jp { text: parent.parent.ac ? "外部電源" : "内部電源"; font.pixelSize: 8 }
          Mono { text: parent.parent.ac ? "EXTERNAL POWER" : "INTERNAL POWER"; font.pixelSize: 7; opacity: 0.8 }
        }
        Column {
          anchors.right: parent.right; y: -1; spacing: 0
          Jp { anchors.right: parent.right; text: "活動限界"; font.pixelSize: 7; opacity: 0.8 }
          Mono {
            anchors.right: parent.right
            text: wall.hud.power.bat === undefined || wall.hud.power.bat === null ? "∞" : wall.hud.power.bat + "%"
            font.pixelSize: 8; font.weight: Font.Bold; color: wall.cAmber
          }
        }
        SegMeter {
          y: 24; width: parent.width; height: 4; segments: 40
          value: wall.hud.power.bat === undefined || wall.hud.power.bat === null ? 1 : wall.hud.power.bat / 100
          color: wall.cOrange; hot: wall.cOrange; hotFrom: 2
        }
      }
    }


    // ================================================================ row 3
    NervPanel {
      id: clock
      x: 0; y: 214; width: wall.width; height: 140
      title: "LOCAL TIME"; jp: "第3新東京市 現地時刻"
      fill: wall.fill

      // TOKYO-3 title card (condensed serif)
      Item {
        width: 150; height: 52
        Text {
          id: card
          text: "TOKYO-3"
          color: wall.cBone
          font.family: "Cormorant Garamond"
          font.weight: Font.DemiBold
          font.pixelSize: 44
          style: Text.Outline; styleColor: wall.cBone
          transform: Scale { xScale: 0.6; yScale: 1 }
          y: -8
        }
        Text {
          x: 2; y: 36
          text: "第3新東京市"
          color: wall.cOrange
          font.family: "Noto Serif CJK JP"; font.weight: Font.Black; font.pixelSize: 11
        }
      }
      Column {
        x: 118; y: 2; spacing: 3
        SevenSeg {
          text: wall.two(wall.hud.now.getHours()) + ":" + wall.two(wall.hud.now.getMinutes()) + ":" + wall.two(wall.hud.now.getSeconds())
          digitHeight: 30; color: wall.cAmber
        }
        Row {
          spacing: 6
          Mono { text: "TOKYO-3 LOCAL TIME"; font.pixelSize: 7; opacity: 0.85 }
          Mono { text: wall.hud.tzName; font.pixelSize: 7; opacity: 0.55 }
        }
      }
      Column {
        anchors.right: parent.right; y: 2; spacing: 1
        Mono {
          anchors.right: parent.right
          text: Qt.formatDate(wall.hud.now, "yyyy.MM.dd")
          font.pixelSize: 8; font.weight: Font.Bold; color: wall.cAmber
        }
        Jp {
          anchors.right: parent.right
          text: ["日", "月", "火", "水", "木", "金", "土"][wall.hud.now.getDay()] + "曜日"
          font.pixelSize: 8
        }
        Mono {
          anchors.right: parent.right
          text: Qt.formatDate(wall.hud.now, "ddd").toUpperCase()
          font.pixelSize: 7; opacity: 0.7
        }
      }


      // scrolling ticker
      Item {
        id: tick
        y: 82; width: parent.width; height: 30
        Rectangle {
          width: 34; height: 13
          color: wall.cOrange
          Jp { anchors.centerIn: parent; text: "記録"; color: wall.cInk; font.weight: Font.Black; font.pixelSize: 8 }
        }
        Rectangle { x: 36; width: parent.width - 36; height: 13; color: Qt.rgba(0, 0, 0, 0.55); border.color: Qt.rgba(1, 0.48, 0, 0.35); border.width: 1 }
        Mono {
          y: 17
          text: "KERNEL " + (wall.hud.kmsg.length ? "EVENTS " + wall.hud.kmsg.length : "QUIET")
            + "  //  HEAD " + wall.hud.hex(99, wall.hud.sec, 8) + "  //  MAGI SYSTEM NOMINAL  承認"
          font.pixelSize: 7; opacity: 0.55; font.letterSpacing: 0.8
        }
      }
    }
  }

  // ================================================================ per-frame movers
  // Panels whose values ease after each sample get their own small layers, so easing
  // re-renders only them (for ~1 s per sample) and they are a single texture otherwise.
  NervPanel {
    id: thermal
    layer.enabled: true   // own small layer: re-renders only while its values ease
    x: wall.lw + 6; y: 0; width: wall.rw; height: 104
    title: "THERMAL"; jp: "温度"
    fill: wall.fill
    alarm: wall.hud.anyHot && wall.hud.blinkOn

    Column {
      width: parent.width
      spacing: 3
      Repeater {
        model: [
          { k: "cpu", en: "CPU", jp: "中央", max: 100, warn: 90 },
          { k: "igpu", en: "iGPU", jp: "内蔵", max: 100, warn: 90 },
          { k: "dgpu", en: "dGPU", jp: "独立", max: 100, warn: 85 },
          { k: "nvme", en: "NVMe", jp: "記憶", max: 90, warn: 70 }
        ]
        delegate: Item {
          id: trow
          required property var modelData
          readonly property var raw: wall.hud.temps[modelData.k]
          readonly property bool has: raw !== undefined && raw !== null
          readonly property bool hot: has && raw >= modelData.warn
          readonly property real v: modelData.k === "cpu" ? wall.hud.tCpuS : modelData.k === "igpu" ? wall.hud.tIgpuS
                                  : modelData.k === "dgpu" ? wall.hud.tDgpuS : wall.hud.tNvmeS
          width: thermal.body.width; height: 16
          Mono { y: 0; text: trow.modelData.en; font.pixelSize: 7; color: trow.hot ? wall.cRed : wall.cOrange }
          Jp { x: 30; y: -1; text: trow.modelData.jp; font.pixelSize: 7; opacity: 0.7 }
          Mono {
            anchors.right: parent.right
            text: trow.has ? trow.v.toFixed(0) + "°C"
                : (trow.modelData.k === "dgpu" && wall.hud.dgpu !== "none" ? "STANDBY" : "----")
            font.pixelSize: 8; font.weight: Font.Bold
            color: trow.hot ? (wall.hud.blinkOn ? wall.cRed : wall.cBone) : (trow.has ? wall.cAmber : wall.cAsh)
          }
          Mono {
            visible: trow.hot
            x: 52; text: "警告"; font.family: "Noto Sans CJK JP"; font.pixelSize: 7
            color: wall.hud.blinkOn ? wall.cRed : "transparent"
          }
          SegMeter {
            y: 10; width: parent.width; height: 4; segments: 24
            value: trow.has ? trow.v / trow.modelData.max : 0
            hotFrom: trow.modelData.warn / trow.modelData.max
          }
        }
      }
    }
  }

  NervPanel {
    id: magi
    layer.enabled: true   // own small layer: re-renders only while its values ease
    x: wall.lw + 6; y: 110; width: wall.rw; height: 98
    title: "MAGI"; jp: "演算"
    fill: wall.fill
    Column {
      width: parent.width
      spacing: 2
      Repeater {
        model: ["CPU", "MEM"]
        delegate: Item {
          id: mrow
          required property int index
          // static model (no delegate rebuilds); values are the eased copies
          readonly property var modelData: ({ en: index === 0 ? "CPU" : "MEM" })
          readonly property real v: index === 0 ? wall.hud.cpuS : wall.hud.memS
          width: magi.body.width; height: 8
          Mono { text: mrow.modelData.en; font.pixelSize: 7 }
          SegMeter { x: 22; y: 2; width: parent.width - 52; height: 5; segments: 16; value: mrow.v / 100; hotFrom: 0.85 }
          Mono { anchors.right: parent.right; text: mrow.v.toFixed(0) + "%"; font.pixelSize: 7; font.weight: Font.Bold; color: wall.cAmber }
        }
      }
      Mono {
        text: "LOAD " + wall.hud.load.join(" ") + "  P" + wall.hud.procs
        font.pixelSize: 7; opacity: 0.75; font.letterSpacing: 0.5
      }
      // hex data filler (1 Hz)
      Row {
        spacing: 6
        Repeater {
          model: 3
          delegate: Column {
            id: hcol
            required property int index
            Repeater {
              model: 4
              delegate: Text {
                required property int index
                readonly property bool hi: (wall.hud.sec + hcol.index * 3) % 4 === index
                text: wall.hud.hex(hcol.index * 17 + index, wall.hud.sec + index, 6)
                color: hi ? wall.cAmber : wall.cOrange
                opacity: hi ? 1 : 0.4
                font.family: "IBM Plex Mono"; font.pixelSize: 7; font.letterSpacing: 0.4
              }
            }
          }
        }
      }
    }
  }

  // top-process strip (eased CPU %)
  Item {
    x: clock.x + clock.body.x; y: clock.y + clock.body.y + 68; width: clock.body.width; height: 10
      Mono { text: "TOP"; font.pixelSize: 7; opacity: 0.75 }
      Jp { x: 20; y: -1; text: "最大負荷"; font.pixelSize: 7; opacity: 0.75 }
      Mono {
        x: 62; width: parent.width - 62 - 60; elide: Text.ElideRight
        text: (wall.hud.topProc.name || "IDLE").toUpperCase() + (wall.hud.topProc.pid ? "  PID " + wall.hud.topProc.pid : "")
        font.pixelSize: 8; font.weight: Font.Bold; color: wall.cAmber
      }
      Mono {
        anchors.right: parent.right
        text: wall.hud.topPctS.toFixed(1) + "% CPU"
        font.pixelSize: 8; font.weight: Font.Bold; color: (wall.hud.topProc.pct || 0) > 90 ? wall.cRed : wall.cAmber
      }
    }

  // hazard band: painted once (one 10 px period wider than the band) and drifted sub-pixel
  // inside a clip by the vsync clock; repaints only on colour/width change.
  Item {
    x: clock.x + clock.body.x; y: clock.y + clock.body.y + 58; width: clock.body.width; height: 6
    clip: true
    Canvas {
      id: hazard
      x: -wall.hud.hazardPx
      width: parent.width + 10; height: 6
      readonly property bool red: wall.hud.anyHot || wall.hud.angelHot
      onRedChanged: requestPaint()
      onWidthChanged: requestPaint()
      onPaint: {
        var c = getContext("2d")
        c.reset()
        c.clearRect(0, 0, width, height)
        c.fillStyle = red ? "#FF1A1A" : "rgba(255,122,0,0.55)"
        for (var x = -height - 10; x < width + height; x += 10) {
          c.beginPath(); c.moveTo(x, height); c.lineTo(x + height, 0); c.lineTo(x + height + 5, 0); c.lineTo(x + 5, height); c.closePath(); c.fill()
        }
      }
    }
  }

  // scrolling ticker tape (sub-pixel, time-based)
  Item {
    x: clock.x + clock.body.x + 40; y: clock.y + clock.body.y + 82
    width: clock.body.width - 44; height: 13
    clip: true
    Row {
      id: tape
      readonly property real span: tapeText.implicitWidth
      x: -(wall.hud.tickerPx % Math.max(1, span))
      y: 2
      Mono { id: tapeText; text: wall.hud.tickerText; font.pixelSize: 8; color: wall.cOrange }
      Mono { text: wall.hud.tickerText; font.pixelSize: 8; color: wall.cOrange }
    }
  }
}
