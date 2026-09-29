import QtQuick
import "Model.js" as Model

// The ACTIVITY LIMIT desktop panel face, laid out on the wall's reference rect (368x240) and
// scaled by the window. All state lives on `host` (PowerDesk.qml).
Item {
  id: face

  required property var host
  property real pxScale: 2        // device px per reference px (for crisp layers)
  readonly property var h: host
  function a(c, x) { return host.alpha(c, x) }

  readonly property color hud: h.hud
  readonly property string statusText: h.simulated ? "SIM : " + h.simMode.toUpperCase()
    : h.depleted ? "ACTIVITY STOPPED"
    : h.external ? (h.charging ? "EXT / CHARGING" : "EXTERNAL SUPPLY")
    : h.critical ? "CRITICAL"
    : "INTERNAL SUPPLY"

  NervPanel {
    id: panel
    anchors.fill: parent
    title: "Activity limit"
    jp: "活動限界"
    accent: face.hud
    alarm: face.h.low && !face.h.blinkOn
    fill: Qt.rgba(0.02, 0.014, 0.008, face.h.fillAlpha)
    status: face.statusText
    statusColor: face.h.simulated || face.h.low ? face.h.cRed : face.a(face.hud, 0.85)

    // ================================================================ row 1: caption + chips
    // Static groups below are flattened into layers (one quad each per vsync frame, re-rendered
    // only when their content changes); the per-frame movers — hundredths, ticker, hazard
    // stripes — stay outside them.
    Item {
      width: parent.width; height: 32
      layer.enabled: true; layer.smooth: true
      layer.textureSize: Qt.size(Math.ceil(width * face.pxScale), Math.ceil(height * face.pxScale))

    Column {
      x: 2; y: 0
      spacing: -4
      Text {
        text: face.h.external ? (face.h.charging ? "充電完了まで" : "外部電源 供給中") : "活動限界まで"
        color: face.h.depleted ? face.h.cRed : face.hud
        font.family: "Noto Serif CJK JP"; font.weight: Font.Black; font.pixelSize: 17
        renderType: Text.QtRendering
      }
      Mono {
        text: face.h.external ? (face.h.charging ? "CHARGE COMPLETE IN" : "UMBILICAL // NO LIMIT") : "ACTIVE TIME REMAINING"
        color: face.a(face.hud, 0.8)
        font.pixelSize: 7; font.letterSpacing: 1.8
      }
    }

    Row {
      anchors.right: parent.right
      y: 0
      spacing: 4
      PowerChip {
        en: "INTERNAL"; jpText: "内部電源"
        mode: face.h.depleted ? "dead" : (face.h.external ? "off" : "on")
        sub: face.h.depleted ? "0%" : (face.h.external ? "STBY" : "ON")
      }
      PowerChip {
        en: "EXTERNAL"; jpText: "外部電源"
        mode: face.h.external ? "link" : "cut"
        sub: face.h.external ? "接続" : "切断"
      }
    }
    }

    // ================================================================ big countdown
    Hazard {
      visible: face.h.low
      y: 34; width: parent.width; height: 3
      color: face.a(face.h.cRed, 0.9); stripe: 5
      phase: face.h.low ? face.h.nowMs * 0.025 : 0
    }

    Item {
      id: segBox
      readonly property real dh: 52
      readonly property real th: 5.8
      readonly property real dw: dh * 0.52 + th * 1.2     // one digit advance
      readonly property real cw: th * 2.6                 // one colon advance
      readonly property string full: face.h.holding ? "--:--:--:--" : Model.clock(face.h.remain)
      readonly property color dimC: face.a(face.h.digitBase, 0.075)
      width: 8 * dw + 3 * cw - th * 0.6 + dh * 0.08
      height: dh
      x: Math.round((parent.width - width) / 2)
      y: 40

      // HH:MM:SS: repaints once a second; the hundredths are pre-rendered glyph stacks
      // (10 canvases per position, painted once per colour) whose visibility flips at vsync,
      // so the per-frame cost is a scene-graph update, not a Canvas repaint.
      Item {
      anchors.fill: parent
      opacity: face.h.digitOpacity
      SevenSeg {
        text: segBox.full.substring(0, 9)
        digitHeight: segBox.dh; thick: segBox.th; skew: 0.08
        color: face.h.digits; dim: segBox.dimC
        colonOn: face.h.holding || !face.h.counting || face.h.colonOn
      }
      Repeater {
        model: 2
        Item {
          id: stack
          required property int index
          readonly property string ch: segBox.full.charAt(9 + index)
          x: (6 + index) * segBox.dw + 3 * segBox.cw
          width: segBox.dw + segBox.dh * 0.08
          height: segBox.dh
          Repeater {
            model: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-"]
            SevenSeg {
              required property string modelData
              visible: stack.ch === modelData
              text: modelData
              digitHeight: segBox.dh; thick: segBox.th; skew: 0.08
              color: face.h.digits; dim: segBox.dimC
            }
          }
        }
      }
      }
      Repeater {
        model: ["HR", "MIN", "SEC", "1/100"]
        Mono {
          required property int index
          required property string modelData
          x: index * (2 * segBox.dw + segBox.cw) + segBox.dw - width / 2
          y: segBox.dh + 3
          text: modelData
          color: face.a(face.hud, 0.7)
          font.pixelSize: 7; font.letterSpacing: 2
        }
      }
    }

    Hazard {
      visible: face.h.low
      y: 104; width: parent.width; height: 3
      color: face.a(face.h.cRed, 0.9); stripe: 5
      phase: face.h.low ? -face.h.nowMs * 0.025 : 0
    }

    // ================================================================ stats row
    Row {
      id: stats
      y: 111
      width: parent.width
      height: 26
      layer.enabled: true; layer.smooth: true
      layer.textureSize: Qt.size(Math.ceil(width * face.pxScale), Math.ceil(height * face.pxScale))

      readonly property real cellW: (width - 3 * 7) / 4
      spacing: 0

      StatCell {
        label: "LEVEL"; jpText: "残量"
        SevenSeg {
          text: Model.pct3(face.h.pctE)
          digitHeight: 14; thick: 2.2; skew: 0.08
          color: face.h.low ? face.h.cRed : face.h.cAmber
          dim: face.a(face.h.cAmber, 0.045)
        }
        Mono { text: "%"; font.pixelSize: 8; font.weight: Font.Bold; color: face.a(face.hud, 0.8); anchors.bottom: parent.bottom }
      }
      Rule {}
      StatCell {
        label: face.h.external ? "CHARGE" : "DRAIN"; jpText: face.h.external ? "充電率" : "放電率"
        SevenSeg {
          text: (face.h.rateE < 9.95 ? "0" : "") + Model.fixed(face.h.rateE, 1)
          digitHeight: 14; thick: 2.2; skew: 0.08
          color: face.h.rateW > 25 ? face.h.cRed : face.h.cAmber
          dim: face.a(face.h.cAmber, 0.045)
        }
        Mono { text: "W"; font.pixelSize: 8; font.weight: Font.Bold; color: face.a(face.hud, 0.8); anchors.bottom: parent.bottom }
      }
      Rule {}
      StatCell {
        label: "HEALTH"; jpText: "健全性"
        SevenSeg {
          text: face.h.healthPct > 0 ? Model.fixed(face.h.healthPct, 1) : "--.-"
          digitHeight: 14; thick: 2.2; skew: 0.08
          color: face.h.healthPct > 0 && face.h.healthPct < 50 ? face.h.cRed : face.h.cAmber
          dim: face.a(face.h.cAmber, 0.045)
        }
        Mono { text: "%"; font.pixelSize: 8; font.weight: Font.Bold; color: face.a(face.hud, 0.8); anchors.bottom: parent.bottom }
      }
      Rule {}
      StatCell {
        id: modeCell
        label: "MODE"; jpText: "動作モード"
        readonly property var lbl: Model.profileLabel(face.h.activeProfile)
        readonly property color k: face.h.activeProfile === "power-saver" ? face.h.cGreen
                                 : face.h.activeProfile === "performance" ? face.h.cAmber : face.h.cOrange
        Item {
          width: stats.cellW - 4; height: 14
          Chamfer {
            anchors.fill: parent
            cuts: [0, 5, 0, 5]
            lineWidth: 1
            fill: face.h.activeProfile !== "" ? modeCell.k : "transparent"
            stroke: modeCell.k
          }
          Mono {
            x: 5; anchors.verticalCenter: parent.verticalCenter
            text: face.h.activeProfile !== "" ? modeCell.lbl.en : "N/A"
            color: face.h.activeProfile !== "" ? face.h.cInk : modeCell.k
            font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.2
          }
          Jp {
            anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
            text: modeCell.lbl.jp
            color: face.h.cInk
            font.pixelSize: 8; font.weight: Font.Black
          }
        }
      }
    }

    // ================================================================ drain bar
    Item {
      y: 143
      width: parent.width
      height: 25
      layer.enabled: true; layer.smooth: true
      layer.textureSize: Qt.size(Math.ceil(width * face.pxScale), Math.ceil(height * face.pxScale))

    Item {
      y: 0
      width: parent.width
      height: 9
      Mono {
        text: face.h.external ? "UMBILICAL CHARGE" : "INTERNAL CHARGE"
        color: face.a(face.hud, 0.85); font.pixelSize: 7; font.letterSpacing: 1.4
      }
      Jp {
        x: 96; y: -1
        text: face.h.external ? "外部電源 充電" : "内部電源 残量"
        color: face.a(face.hud, 0.55); font.pixelSize: 7
      }
      Mono {
        anchors.right: parent.right
        text: Model.fixed(face.h.energyWh, 1) + " / " + Model.fixed(face.h.capacityWh, 1) + " Wh"
        color: face.h.cAmber; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1
      }
    }
    // dim track + lit row in a clip whose width eases with pctE: the fill glides between
    // samples with one property change per frame (segment bindings only re-run on real changes)
    Row {
      y: 11
      width: parent.width
      spacing: 2
      Repeater {
        model: 50
        Rectangle {
          width: (panel.body.width - 2 * 49) / 50
          height: 7
          color: face.a(face.hud, 0.1)
        }
      }
    }
    Item {
      y: 11
      width: panel.body.width * Math.max(0, Math.min(1, face.h.pctE))
      height: 7
      clip: true
      Row {
        width: panel.body.width
        spacing: 2
        Repeater {
          model: 50
          Rectangle {
            required property int index
            readonly property int litN: Math.ceil(face.h.pct * 50 - 0.001)
            width: (panel.body.width - 2 * 49) / 50
            height: 7
            color: index < 7 || face.h.low ? face.h.cRed : (face.h.external ? face.h.cGreen : face.h.cAmber)
            opacity: face.h.low && index === litN - 1 && !face.h.blinkOn ? 0.3 : 1
          }
        }
      }
    }
    // tick scale under the bar (10 % steps)
    Repeater {
      model: 11
      Rectangle {
        required property int index
        x: Math.min(panel.body.width - 1, index * panel.body.width / 10)
        y: 20
        width: 1; height: index % 5 === 0 ? 4 : 2
        color: face.a(face.hud, 0.5)
      }
    }
    }

    // ================================================================ status band / warning box
    Item {
      id: band
      y: 171
      width: parent.width
      height: panel.body.height - y

      // ---- normal: supply tab + message + ticker
      Item {
        anchors.fill: parent
        visible: !face.h.low

        Item {
        anchors.fill: parent
        layer.enabled: true; layer.smooth: true
      layer.textureSize: Qt.size(Math.ceil(width * face.pxScale), Math.ceil(height * face.pxScale))

        Chamfer {
          anchors.fill: parent
          cuts: [0, 8, 0, 8]
          fill: Qt.rgba(0, 0, 0, 0.35)
          stroke: face.a(face.hud, 0.45)
          lineWidth: 1
        }
        Chamfer {
          id: supplyTab
          x: 0; y: 0
          width: supplyJp.implicitWidth + 16; height: 17
          cuts: [0, 0, 6, 0]
          fill: face.hud
          stroke: "transparent"
          Jp {
            id: supplyJp
            x: 7; anchors.verticalCenter: parent.verticalCenter
            text: face.h.external ? "外部電源" : "内部電源"
            color: face.h.cInk; font.pixelSize: 11; font.weight: Font.Black
          }
        }
        Text {
          x: supplyTab.width + 8
          y: -5
          text: face.h.external ? (face.h.charging ? "UMBILICAL · CHARGING" : "UMBILICAL · HOLDING") : "INTERNAL POWER"
          color: face.h.cBone
          font.family: "Cormorant Garamond"; font.weight: Font.Bold; font.pixelSize: 24
          transform: Scale { xScale: 0.6 }
          renderType: Text.QtRendering
        }
        Mono {
          anchors.right: parent.right; anchors.rightMargin: 12
          y: 4
          text: "EVA-01 // S² N/A"
          color: face.a(face.hud, 0.55); font.pixelSize: 7
        }
        }
        Item {
          x: 6; y: parent.height - 14
          width: parent.width - 16
          height: 11
          clip: true
          Mono {
            id: tick
            readonly property string msg: face.h.external
              ? "UMBILICAL CABLE CONNECTED // アンビリカルケーブル 接続 // EXTERNAL POWER SUPPLY NOMINAL // 外部電源 正常 // "
              : "UMBILICAL CABLE PURGED // アンビリカルケーブル 切断 // INTERNAL POWER ACTIVE // 内部電源に切り替え // ACTIVITY LIMIT COUNTDOWN // 活動限界まで // "
            text: msg + msg
            anchors.verticalCenter: parent.verticalCenter
            x: -((face.h.nowMs / 1000 * 30) % Math.max(1, implicitWidth / 2))
            color: face.a(face.hud, 0.62)
            font.pixelSize: 7; font.letterSpacing: 1.4
          }
        }
      }

      // ---- low / critical / depleted: WARNING box
      Item {
        anchors.fill: parent
        visible: face.h.low

        Chamfer {
          anchors.fill: parent
          cuts: [8, 8, 8, 8]
          fill: Qt.rgba(40 / 255, 0, 0, 0.6)
          stroke: face.h.cRed
          lineWidth: 2
        }
        Chamfer {   // blink layer: toggled, never repainted
          anchors.fill: parent
          visible: face.h.blinkOn
          cuts: [8, 8, 8, 8]
          fill: Qt.rgba(40 / 255, 0, 0, 0.75)
          stroke: "transparent"
        }
        Hazard {
          x: 6; y: 4; width: parent.width - 12; height: 6
          color: face.h.cRed; stripe: 6
          phase: face.h.low ? face.h.nowMs / 30 : 0
        }
        Hazard {
          x: 6; y: parent.height - 10; width: parent.width - 12; height: 6
          color: face.h.cRed; stripe: 6
          phase: face.h.low ? -face.h.nowMs / 30 : 0
        }
        Text {
          x: 10
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -1
          text: face.h.depleted ? "LIMIT" : (face.h.critical ? "EMERGENCY" : "WARNING")
          color: face.h.cRed
          opacity: face.h.blinkOn ? 1 : 0.4
          font.family: "Cormorant Garamond"; font.weight: Font.Bold; font.pixelSize: 30
          transform: Scale { xScale: 0.58; origin.x: 0 }
          renderType: Text.QtRendering
        }
        Column {
          anchors.right: parent.right; anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0
          Jp {
            anchors.right: parent.right
            text: face.h.depleted ? "活動限界  活動停止" : (face.h.critical ? "緊急  活動限界 接近" : "警告  内部電源 残量低下")
            color: face.h.cRed; font.pixelSize: 11; font.weight: Font.Black
          }
          Mono {
            anchors.right: parent.right
            text: face.h.depleted ? "BATTERY DEPLETED" : (face.h.critical ? "ACTIVITY LIMIT IMMINENT" : "CONNECT UMBILICAL CABLE")
            color: face.a(face.h.cRed, 0.85); font.pixelSize: 7; font.letterSpacing: 1.6
          }
        }
      }
    }
  }

  // CRT scanlines over everything (painted once per resize)
  Canvas {
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      c.fillStyle = "rgba(0,0,0,0.26)"
      for (var y = 0; y < height; y += 2) c.fillRect(0, y + 1, width, 0.7)
    }
  }

  // ---- components -----------------------------------------------------------------------------------
  component Rule: Item {
    width: 7; height: 26
    Rectangle { x: 3; y: 2; width: 1; height: 22; color: face.a(face.hud, 0.3) }
  }

  component StatCell: Item {
    id: cell
    property string label: ""
    property string jpText: ""
    default property alias value: valueRow.data
    width: stats.cellW
    height: 26
    Mono {
      text: cell.label
      color: face.a(face.hud, 0.85); font.pixelSize: 7; font.letterSpacing: 1.4
    }
    Jp {
      anchors.right: parent.right; anchors.rightMargin: 2
      y: -1
      text: cell.jpText
      color: face.a(face.hud, 0.55); font.pixelSize: 7
    }
    Row {
      id: valueRow
      y: 11
      spacing: 3
    }
  }

  component PowerChip: Item {
    id: chip
    property string en: ""
    property string jpText: ""
    property string sub: ""
    property string mode: "off"   // on | off | link | cut | dead
    readonly property color k: mode === "on" ? face.h.cAmber : mode === "link" ? face.h.cGreen
                             : (mode === "cut" || mode === "dead") ? face.h.cRed : face.h.cOrange
    readonly property bool solid: mode === "on" || mode === "link" || (mode === "dead" && face.h.blinkOn)
    readonly property color tc: solid ? face.h.cInk : face.a(k, mode === "off" ? 0.45 : 1)
    width: 80; height: 30
    Chamfer {
      anchors.fill: parent
      cuts: [0, 7, 0, 7]
      fill: chip.solid ? chip.k : Qt.rgba(0, 0, 0, 0.55)
      stroke: face.a(chip.k, chip.mode === "off" ? 0.45 : 1)
      lineWidth: 1.5
      slash: chip.mode === "cut" || chip.mode === "dead"
      slashColor: chip.solid ? face.h.cInk : face.h.cRed
    }
    Mono {
      x: 6; y: 3
      text: chip.en
      color: chip.tc; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.4
    }
    Jp {
      x: 6; y: 13
      text: chip.jpText
      color: chip.tc; font.pixelSize: 10; font.weight: Font.Black
    }
    Text {
      anchors.right: parent.right; anchors.rightMargin: 6
      y: 15
      text: chip.sub
      color: chip.tc
      font.family: chip.sub.charCodeAt(0) > 255 ? "Noto Sans CJK JP" : "IBM Plex Mono"
      font.weight: Font.Black; font.pixelSize: 8
      renderType: Text.QtRendering
    }
  }
}
