import QtQuick
import Quickshell
import Quickshell.Wayland
import "Model.js" as Model

// The ACTIVITY LIMIT panel. A full-screen transparent layer-shell surface (like the shell's
// KeyboardPanel) with the bar strip masked out so other bar icons still take clicks; clicking
// anywhere else, or Escape, closes it. Only exists while open (Loader in Widget.qml).
PanelWindow {
  id: win

  required property var host
  required property Item anchorItem

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: host.bar ? host.bar.position : "top"
  readonly property real barThick: anchorWindow ? ((barPos === "left" || barPos === "right") ? anchorWindow.width : anchorWindow.height) : 26
  readonly property int gap: 6
  readonly property int cardW: 480

  // palette shortcuts
  readonly property color ink: host.cInk
  readonly property color orange: host.cOrange
  readonly property color amber: host.cAmber
  readonly property color red: host.cRed
  readonly property color green: host.cGreen
  readonly property color bone: host.cBone
  function a(c, x) { return host.alpha(c, x) }

  // State-derived colours: amber/orange HUD, green on the umbilical, red when low.
  readonly property color hud: host.external ? green : (host.low ? red : orange)
  readonly property color digits: host.depleted ? (host.blinkOn ? red : a(red, 0.2))
                                : host.critical ? (host.blinkOn ? red : a(red, 0.45))
                                : host.digitColor

  screen: anchorWindow ? anchorWindow.screen : null
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "nerv-power-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  anchors { top: true; bottom: true; left: true; right: true }

  mask: Region {
    x: 0; y: 0; width: win.width; height: win.height
    Region {
      intersection: Intersection.Subtract
      x: win.barPos === "right" ? win.width - win.barThick : 0
      y: win.barPos === "bottom" ? win.height - win.barThick : 0
      width: (win.barPos === "left" || win.barPos === "right") ? win.barThick : win.width
      height: (win.barPos === "top" || win.barPos === "bottom") ? win.barThick : win.height
    }
  }

  // Card placement: centred under the widget, clamped to the screen.
  property point origin: Qt.point(0, 0)
  function place() {
    if (!anchorItem || !anchorWindow) return
    var p = anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
    var sw = win.width, sh = win.height, ch = card.height, m = 6
    var x, y
    if (barPos === "left") { x = barThick + gap; y = p.y + anchorItem.height / 2 - ch / 2 }
    else if (barPos === "right") { x = sw - barThick - cardW - gap; y = p.y + anchorItem.height / 2 - ch / 2 }
    else if (barPos === "bottom") { x = p.x + anchorItem.width / 2 - cardW / 2; y = sh - barThick - ch - gap }
    else { x = p.x + anchorItem.width / 2 - cardW / 2; y = barThick + gap }
    origin = Qt.point(Math.round(Math.max(m, Math.min(x, sw - cardW - m))), Math.round(Math.max(m, Math.min(y, sh - ch - m))))
  }
  onWidthChanged: place()
  onHeightChanged: place()
  Component.onCompleted: { place(); powerOn.start() }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: win.host.close()
  }

  // ------------------------------------------------------------------------------------------------
  Item {
    id: card
    x: win.origin.x
    y: win.origin.y
    width: win.cardW
    height: col.implicitHeight + 24
    onHeightChanged: win.place()
    focus: true
    Keys.onEscapePressed: win.host.close()

    // hard, stepped CRT power-on
    SequentialAnimation {
      id: powerOn
      PropertyAction { target: card; property: "opacity"; value: 0.0 }
      PauseAnimation { duration: 30 }
      PropertyAction { target: card; property: "opacity"; value: 1.0 }
      PauseAnimation { duration: 40 }
      PropertyAction { target: card; property: "opacity"; value: 0.25 }
      PauseAnimation { duration: 40 }
      PropertyAction { target: card; property: "opacity"; value: 1.0 }
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Chamfer {
      anchors.fill: parent
      cuts: [0, 18, 0, 18]
      fill: win.a(win.ink, 0.97)
      stroke: win.a(win.hud, 0.55)
      lineWidth: 1.5
    }

    // CRT scanlines over the whole card (painted once)
    Canvas {
      anchors.fill: parent
      z: 50
      enabled: false
      onPaint: {
        var c = getContext("2d")
        c.reset()
        c.fillStyle = "rgba(0,0,0,0.22)"
        for (var y = 0; y < height; y += 3) c.fillRect(0, y, width, 1)
      }
    }

    Column {
      id: col
      x: 12; y: 12
      width: parent.width - 24
      spacing: 8

      // ---- title card -------------------------------------------------------------------
      Item {
        width: parent.width
        height: 50

        Chamfer {
          id: unitTab
          width: 36; height: 36
          cuts: [0, 10, 0, 0]
          fill: win.hud
          stroke: "transparent"
          Text {
            anchors.centerIn: parent
            text: "01"
            color: win.ink
            font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 17
          }
        }

        Text {
          id: bigTitle
          x: unitTab.width + 10
          y: -8
          text: "INTERNAL BATTERY"
          color: win.bone
          font.family: "Cormorant Garamond"; font.weight: Font.DemiBold; font.pixelSize: 38
          transform: Scale { xScale: 0.6 }
        }
        Text {
          x: bigTitle.x + bigTitle.implicitWidth * 0.6 + 10
          y: 7
          text: "内部電源  活動限界"
          color: win.hud
          font.family: "Noto Sans CJK JP"; font.weight: Font.Black; font.pixelSize: 14
        }
        Text {
          x: bigTitle.x
          y: 31
          text: "EVA UNIT-01 // UMBILICAL CABLE MONITOR // S² ENGINE N/A"
          color: win.a(win.hud, 0.7)
          font.family: "IBM Plex Mono"; font.weight: Font.Medium; font.pixelSize: 9; font.letterSpacing: 1.6
        }

        // visual-test marker, top right
        Text {
          visible: win.host.simulated
          anchors.right: parent.right
          y: -9
          text: "SIM: " + win.host.simMode.toUpperCase()
          color: win.red
          font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 9; font.letterSpacing: 1.2
        }

        // rule with ticks
        Rectangle { y: 44; width: parent.width; height: 2; color: win.hud }
        Repeater {
          model: Math.floor(col.width / 12) + 1
          Rectangle {
            required property int index
            x: index * 12; y: 46
            width: 1; height: index % 5 === 0 ? 5 : 3
            color: win.a(win.hud, 0.6)
          }
        }
      }

      // ---- ACTIVITY LIMIT timer -----------------------------------------------------------------
      Item {
        width: parent.width
        height: timerPanel.height + (win.host.low ? 16 : 0)

        Hazard {
          visible: win.host.low
          width: parent.width; height: 5
          color: win.a(win.red, 0.9)
          stripe: 6
          phase: Math.floor(win.host.nowMs / 120) * 3
        }

        NervPanel {
          id: timerPanel
          y: win.host.low ? 8 : 0
          width: parent.width
          title: "Activity limit"
          jp: "活動限界"
          color: win.host.depleted ? win.red : win.hud
          status: win.host.depleted ? "STATUS : ACTIVITY STOPPED"
                : win.host.external ? (win.host.charging ? "STATUS : EXT / CHARGING" : "STATUS : EXTERNAL SUPPLY")
                : win.host.critical ? "STATUS : CRITICAL"
                : "STATUS : INTERNAL SUPPLY"
          statusColor: win.host.low ? win.red : win.a(win.hud, 0.85)
          cut: 16

          Item {
            width: timerPanel.contentWidth
            height: 180

            Column {
              spacing: 1
              Text {
                text: win.host.external ? (win.host.charging ? "充電完了まで" : "外部電源 供給中") : "活動限界まで"
                color: win.host.depleted ? win.red : win.hud
                font.family: "Noto Serif CJK JP"; font.weight: Font.Black; font.pixelSize: 26
              }
              Text {
                text: win.host.external ? (win.host.charging ? "CHARGE COMPLETE IN" : "UMBILICAL // NO LIMIT") : "ACTIVE TIME REMAINING"
                color: win.a(win.hud, 0.85)
                font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 10; font.letterSpacing: 2.4
              }
              Text {
                text: "エヴァンゲリオン初号機  内部電源残量"
                color: win.a(win.hud, 0.6)
                font.family: "Noto Sans CJK JP"; font.weight: Font.Medium; font.pixelSize: 9
              }
            }

            // INTERNAL / EXTERNAL chips
            Row {
              anchors.right: parent.right
              y: 2
              spacing: 6
              PowerChip {
                en: "INTERNAL"; jpText: "内部電源"
                mode: win.host.depleted ? "dead" : (win.host.external ? "off" : "on")
                sub: win.host.depleted ? "0%" : (win.host.external ? "STBY" : "ON")
              }
              PowerChip {
                en: "EXTERNAL"; jpText: "外部電源"
                mode: win.host.external ? "link" : "cut"
                sub: win.host.external ? "接続" : "切断"
              }
            }

            // HUGE countdown
            SevenSeg {
              id: bigSeg
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.horizontalCenterOffset: -4
              y: 70
              digitHeight: 66
              thick: 7.4
              skew: 0.08
              text: win.host.holding ? "--:--:--:--" : Model.clock(win.host.remain)
              color: win.digits
              dim: win.a(win.host.external ? win.green : (win.host.low ? win.red : win.amber), 0.075)
            }
            Repeater {
              model: ["HR", "MIN", "SEC", "1/100"]
              Text {
                required property int index
                required property string modelData
                readonly property real gw: 2 * (bigSeg.digitHeight * 0.52 + bigSeg.thick * 1.2)
                readonly property real cw: bigSeg.thick * 2.6
                x: bigSeg.x + index * (gw + cw) + gw / 2 - width / 2
                y: bigSeg.y + bigSeg.height + 4
                text: modelData
                color: win.a(win.hud, 0.7)
                font.family: "IBM Plex Mono"; font.weight: Font.DemiBold; font.pixelSize: 9; font.letterSpacing: 2.4
              }
            }

            // drain bar
            Row {
              y: parent.height - 8
              width: parent.width
              spacing: 2
              Repeater {
                id: drainRep
                model: 60
                Rectangle {
                  required property int index
                  readonly property bool lit: index < Math.ceil(win.host.pct * 60 - 0.001)
                  width: (timerPanel.contentWidth - 2 * 59) / 60
                  height: 8
                  color: lit ? (index < 9 ? win.red : (win.host.low ? win.red : (win.host.external ? win.green : win.amber)))
                             : win.a(win.hud, 0.1)
                  opacity: lit && win.host.low && index === Math.ceil(win.host.pct * 60) - 1 && !win.host.blinkOn ? 0.3 : 1
                }
              }
            }
          }
        }

        Hazard {
          visible: win.host.low
          y: parent.height - 5
          width: parent.width; height: 5
          color: win.a(win.red, 0.9)
          stripe: 6
          phase: -Math.floor(win.host.nowMs / 120) * 3
        }
      }

      // ---- WARNING box (low battery on internal power) ----------------------------------------
      Item {
        visible: win.host.low
        width: parent.width
        height: 92

        Chamfer {
          anchors.fill: parent
          cuts: [12, 12, 12, 12]
          fill: Qt.rgba(40 / 255, 0, 0, win.host.blinkOn ? 0.9 : 0.6)
          stroke: win.red
          lineWidth: 2.5
        }
        Hazard {
          x: 8; y: 8; width: parent.width - 16; height: 11
          color: win.red; stripe: 9
          phase: Math.floor(win.host.nowMs / 120) * 4
        }
        Hazard {
          x: 8; y: parent.height - 19; width: parent.width - 16; height: 11
          color: win.red; stripe: 9
          phase: -Math.floor(win.host.nowMs / 120) * 4
        }
        Text {
          id: warnWord
          x: 18
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -2
          text: win.host.depleted ? "LIMIT" : (win.host.critical ? "EMERGENCY" : "WARNING")
          color: win.red
          opacity: win.host.blinkOn ? 1 : 0.4
          font.family: "Cormorant Garamond"; font.weight: Font.Bold; font.pixelSize: 58
          transform: Scale { xScale: 0.58; origin.x: 0 }
        }
        Column {
          anchors.right: parent.right
          anchors.rightMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1
          Text {
            anchors.right: parent.right
            text: win.host.depleted ? "活動限界  活動停止" : (win.host.critical ? "緊急  活動限界 接近" : "警告  内部電源 残量低下")
            color: win.red
            font.family: "Noto Sans CJK JP"; font.weight: Font.Black; font.pixelSize: 14
          }
          Text {
            anchors.right: parent.right
            text: win.host.depleted ? "BATTERY DEPLETED" : (win.host.critical ? "ACTIVITY LIMIT IMMINENT" : "CONNECT UMBILICAL CABLE")
            color: win.a(win.red, 0.85)
            font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 9; font.letterSpacing: 1.8
          }
        }
      }

      // ---- CELLS / OUTPUT ---------------------------------------------------------------------
      Row {
        width: parent.width
        spacing: 8

        NervPanel {
          id: cellsPanel
          width: (parent.width - 8) * 0.44
          height: outputPanel.height
          title: "Cells"
          jp: "電池残量"
          color: win.hud

          Item {
            width: cellsPanel.contentWidth
            height: 100

            // battery-cell icon meter (batteryCell() in battery-kit.ts)
            Item {
              id: cell
              width: 34; height: 96
              Rectangle { x: 10; y: 0; width: 14; height: 4; color: win.hud }
              Chamfer {
                id: cellCase
                y: 5; width: parent.width; height: parent.height - 5
                cuts: [0, 6, 0, 6]
                stroke: win.hud
                lineWidth: 1.5
              }
              Column {
                x: 4; y: cellCase.y + 4
                spacing: 2
                Repeater {
                  model: 10
                  Rectangle {
                    required property int index
                    readonly property int slot: 9 - index
                    readonly property real litv: Math.max(0, Math.min(1, win.host.pct * 10 - slot))
                    width: cellCase.width - 8
                    height: (cellCase.height - 8 - 18) / 10
                    color: litv > 0 ? (win.host.pct < 0.25 && !win.host.external ? win.red : win.hud) : win.a(win.hud, 0.1)
                    opacity: litv > 0 ? 0.35 + 0.65 * litv : 1
                  }
                }
              }
            }

            Column {
              x: cell.width + 10
              spacing: 3
              Row {
                spacing: 3
                SevenSeg {
                  text: Model.pct3(win.host.pct)
                  digitHeight: 30
                  thick: 3.6
                  color: win.host.low ? win.red : win.amber
                  dim: win.a(win.amber, 0.07)
                }
                Text {
                  anchors.bottom: parent.bottom
                  text: "%"
                  color: win.a(win.hud, 0.8)
                  font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 11
                }
              }
              DataRow { label: "ENERGY"; jpText: "残量"; value: Model.fixed(win.host.energyWh, 1) + " Wh"; w: cellsPanel.contentWidth - cell.width - 10 }
              DataRow { label: "FULL"; jpText: "満充電"; value: Model.fixed(win.host.capacityWh, 1) + " Wh"; w: cellsPanel.contentWidth - cell.width - 10 }
              DataRow {
                label: "STATE"; jpText: ""
                w: cellsPanel.contentWidth - cell.width - 10
                value: win.host.external ? (win.host.charging ? "充電中 CHG" : "保持 HOLD") : "放電中 DSCH"
                valueColor: win.host.external ? win.green : (win.host.low ? win.red : win.amber)
              }
            }
          }
        }

        NervPanel {
          id: outputPanel
          width: (parent.width - 8) * 0.56
          title: "Output"
          jp: "出力"
          color: win.hud

          Column {
            width: outputPanel.contentWidth
            spacing: 3

            Item {
              width: parent.width
              height: 34
              Column {
                Text {
                  text: win.host.external ? "CHARGE RATE" : "DRAIN RATE"
                  color: win.a(win.hud, 0.85)
                  font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 9; font.letterSpacing: 1.8
                }
                Text {
                  text: win.host.external ? "充電率" : "放電率"
                  color: win.a(win.hud, 0.6)
                  font.family: "Noto Sans CJK JP"; font.weight: Font.Medium; font.pixelSize: 9
                }
              }
              Row {
                anchors.right: parent.right
                spacing: 4
                SevenSeg {
                  text: (win.host.rateW < 10 ? "0" : "") + Model.fixed(win.host.rateW, 1)
                  digitHeight: 28
                  thick: 3.4
                  color: win.host.rateW > 25 ? win.red : win.amber
                  dim: win.a(win.amber, 0.07)
                }
                Text {
                  anchors.bottom: parent.bottom
                  text: "W"
                  color: win.a(win.hud, 0.8)
                  font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 11
                }
              }
            }
            Rectangle { width: parent.width; height: 1; color: win.a(win.hud, 0.3) }
            DataRow { label: "HEALTH"; jpText: "健全性"; value: win.host.healthPct > 0 ? Model.fixed(win.host.healthPct, 1) + " %" : "N/A"; w: outputPanel.contentWidth }
            // health meter
            Row {
              spacing: 2
              Repeater {
                model: 30
                Rectangle {
                  required property int index
                  width: (outputPanel.contentWidth - 2 * 29) / 30
                  height: 5
                  color: index < Math.round(win.host.healthPct / 100 * 30)
                    ? (index < 6 ? win.red : win.hud) : win.a(win.hud, 0.1)
                }
              }
            }
            DataRow { label: "DESIGN"; jpText: "設計容量"; value: win.host.designWh > 0 ? Model.fixed(win.host.designWh, 1) + " Wh" : "N/A"; w: outputPanel.contentWidth }
            DataRow { label: "CYCLES"; jpText: "充放電回数"; value: win.host.simulated ? "217" : (win.host.cycles || "N/A"); w: outputPanel.contentWidth }
          }
        }
      }

      // ---- power profile ----------------------------------------------------------------------
      NervPanel {
        id: profilePanel
        width: parent.width
        title: "Operation mode"
        jp: "動作モード"
        status: (win.host.external ? "AC PROFILE  外部" : "BATTERY PROFILE  内部")
        statusColor: win.a(win.hud, 0.8)
        color: win.hud
        visible: win.host.profiles.length > 0

        Row {
          id: profRow
          width: profilePanel.contentWidth
          spacing: 8
          Repeater {
            model: win.host.profiles
            Item {
              id: pbtn
              required property string modelData
              readonly property bool active: win.host.activeProfile === modelData
              readonly property var lbl: Model.profileLabel(modelData)
              readonly property color k: modelData === "power-saver" ? win.green : (modelData === "performance" ? win.amber : win.orange)
              width: (profRow.width - profRow.spacing * (win.host.profiles.length - 1)) / Math.max(1, win.host.profiles.length)
              height: 30
              Chamfer {
                anchors.fill: parent
                cuts: [0, 8, 0, 8]
                fill: pbtn.active ? pbtn.k : (pma.containsMouse ? win.a(pbtn.k, 0.15) : Qt.rgba(0, 0, 0, 0.5))
                stroke: pbtn.active ? pbtn.k : win.a(pbtn.k, pma.containsMouse ? 0.9 : 0.4)
              }
              Text {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: pbtn.lbl.en
                color: pbtn.active ? win.ink : win.a(pbtn.k, 0.7)
                font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 11; font.letterSpacing: 2
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: pbtn.lbl.jp
                color: pbtn.active ? win.ink : win.a(pbtn.k, 0.7)
                font.family: "Noto Sans CJK JP"; font.weight: Font.Black; font.pixelSize: 11
              }
              MouseArea {
                id: pma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: win.host.setProfile(pbtn.modelData)
              }
            }
          }
        }
      }

      // ---- footer: NERV HQ tab + ticker ---------------------------------------------------------
      Item {
        width: parent.width
        height: 18
        Chamfer {
          id: hqTab
          width: 150; height: 18
          cuts: [0, 0, 8, 0]
          fill: win.hud
          stroke: "transparent"
          Text {
            x: 7
            anchors.verticalCenter: parent.verticalCenter
            text: "NERV HQ  中央作戦室"
            color: win.ink
            font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 10; font.letterSpacing: 1.4
          }
        }
        Item {
          x: hqTab.width + 8
          width: parent.width - x
          height: parent.height
          clip: true
          Text {
            id: tick
            readonly property string msg: (win.host.external
              ? "UMBILICAL CABLE CONNECTED // アンビリカルケーブル 接続 // EXTERNAL POWER SUPPLY NOMINAL // 外部電源 正常 // "
              : win.host.depleted
                ? "ACTIVITY LIMIT REACHED // 活動限界 // INTERNAL BATTERY DEPLETED // 内部電源 残量ゼロ // "
                : "UMBILICAL CABLE PURGED // アンビリカルケーブル 切断 // INTERNAL POWER ACTIVE // 内部電源に切り替え // ACTIVITY LIMIT IMMINENT // 活動限界まで // ")
            text: msg + msg
            anchors.verticalCenter: parent.verticalCenter
            x: -((win.host.nowMs / 1000 * 40) % (implicitWidth / 2))
            color: win.a(win.hud, 0.62)
            font.family: "IBM Plex Mono"; font.weight: Font.Medium; font.pixelSize: 9; font.letterSpacing: 1.6
          }
        }
      }
    }
  }

  // ---- components ---------------------------------------------------------------------------------
  component PowerChip: Item {
    id: chip
    property string en: ""
    property string jpText: ""
    property string sub: ""
    property string mode: "off"   // on | off | link | cut | dead
    readonly property color k: mode === "on" ? win.amber : mode === "link" ? win.green : (mode === "cut" || mode === "dead") ? win.red : win.orange
    readonly property bool solid: mode === "on" || mode === "link" || (mode === "dead" && win.host.blinkOn)
    readonly property color tc: solid ? win.ink : win.a(k, mode === "off" ? 0.45 : 1)
    width: 104; height: 46
    Chamfer {
      anchors.fill: parent
      cuts: [0, 10, 0, 10]
      fill: chip.solid ? chip.k : Qt.rgba(0, 0, 0, 0.55)
      stroke: win.a(chip.k, chip.mode === "off" ? 0.45 : 1)
      lineWidth: 2
      slash: chip.mode === "cut" || chip.mode === "dead"
      slashColor: chip.solid ? win.ink : win.red
    }
    Text {
      x: 9; y: 5
      text: chip.en
      color: chip.tc
      font.family: "IBM Plex Mono"; font.weight: Font.Bold; font.pixelSize: 11; font.letterSpacing: 2
    }
    Text {
      x: 9; y: 22
      text: chip.jpText
      color: chip.tc
      font.family: "Noto Sans CJK JP"; font.weight: Font.Black; font.pixelSize: 13
    }
    Text {
      anchors.right: parent.right; anchors.rightMargin: 8
      y: 25
      text: chip.sub
      color: chip.tc
      font.family: chip.sub.charCodeAt(0) > 255 ? "Noto Sans CJK JP" : "IBM Plex Mono"
      font.weight: Font.Black; font.pixelSize: 10
    }
  }

  component DataRow: Item {
    id: dr
    property string label: ""
    property string jpText: ""
    property string value: ""
    property real w: 100
    property color valueColor: win.amber
    width: w
    height: 15
    Text {
      id: drl
      anchors.verticalCenter: parent.verticalCenter
      text: dr.label
      color: win.a(win.hud, 0.85)
      font.family: "IBM Plex Mono"; font.weight: Font.DemiBold; font.pixelSize: 10; font.letterSpacing: 1.4
    }
    Text {
      x: drl.implicitWidth + 5
      anchors.verticalCenter: parent.verticalCenter
      text: dr.jpText
      color: win.a(win.hud, 0.5)
      font.family: "Noto Sans CJK JP"; font.weight: Font.Medium; font.pixelSize: 9
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: dr.value
      color: dr.valueColor
      font.family: dr.value.charCodeAt(0) > 255 ? "Noto Sans CJK JP" : "IBM Plex Mono"
      font.weight: Font.Bold; font.pixelSize: 10; font.letterSpacing: 1
    }
  }
}
