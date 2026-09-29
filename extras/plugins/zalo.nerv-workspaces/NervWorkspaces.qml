import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// NERV workspace switcher. Same Hyprland data + dispatch as omarchy.workspaces,
// drawn as chamfered cells:
//   focused  = solid orange, number knocked out in black
//   occupied = orange outline, orange number
//   urgent   = blinking red
//   empty    = dim graphite
// Click switches, wheel cycles (e-1 / e+1), tooltip shows 第N作業区 + kanji numeral.
BarWidget {
  id: root
  moduleName: "zalo.nerv-workspaces"

  readonly property color cInk: "#050403"
  readonly property color cGraphite: "#4A3218"
  readonly property color cAsh: "#9C6A2E"
  readonly property color cOrange: "#FF7A00"
  readonly property color cAmber: "#FFB000"
  readonly property color cRed: "#FF1A1A"
  readonly property var kanji: ["零", "壱", "弐", "参", "肆", "伍", "陸", "漆", "捌", "玖", "拾"]

  readonly property string numerals: String(root.setting("numerals", "seg"))
  readonly property int minWorkspaces: Math.max(1, Math.min(10, parseInt(root.setting("minWorkspaces", 5)) || 5))

  // Urgent blink (only ticks while something is urgent).
  property bool blinkOn: true
  readonly property bool anyUrgent: {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) if (values[i].urgent === true) return true
    return false
  }
  Timer {
    interval: 225
    repeat: true
    running: root.anyUrgent
    onTriggered: root.blinkOn = !root.blinkOn
    onRunningChanged: if (!running) root.blinkOn = true
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = []
    for (var n = 1; n <= root.minWorkspaces; n++) ids.push(n)
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Touchpads send small deltas; step once per notch (120) worth of scroll.
  property real wheelAccum: 0
  function scrollBy(delta) {
    wheelAccum += delta
    if (Math.abs(wheelAccum) < 120) return
    var dir = wheelAccum > 0 ? "e-1" : "e+1"
    wheelAccum = 0
    focusWorkspace(dir)
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property real cellH: Math.max(12, Math.round(root.barSize * 0.64))
  readonly property real cellW: Math.round(cellH * 1.3)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: cell
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property bool urgent: workspace !== null && workspace.urgent === true && !focused
        readonly property bool elsewhere: workspace !== null && workspace.active === true && !focused
        readonly property bool hot: urgent && root.blinkOn

        readonly property color fill: focused ? root.cOrange : (hot ? root.cRed : "transparent")
        readonly property color edge: focused ? root.cOrange
          : urgent ? root.cRed
          : elsewhere ? root.cAmber
          : occupied ? root.cOrange
          : root.cGraphite
        readonly property color digit: focused || hot ? root.cInk
          : urgent ? root.cRed
          : elsewhere ? root.cAmber
          : occupied ? root.cOrange
          : Qt.rgba(0.61, 0.42, 0.18, 0.75)
        readonly property string numText: modelData === 10 ? "0" : String(modelData)

        bar: root.bar
        text: " "
        labelVisible: false
        tooltipText: "WORKSPACE " + (modelData < 10 ? "0" : "") + modelData + "  第" + root.kanji[modelData] + "作業区"
          + (urgent ? "  // 警告 URGENT" : focused ? "  // 稼働中 ACTIVE" : occupied ? "" : "  // 空 EMPTY")
        fixedWidth: root.vertical ? root.barSize : root.cellW + Style.space(3)
        fixedHeight: root.vertical ? root.cellH + Style.space(4) : root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
        onWheelMoved: function(delta) { root.scrollBy(delta) }

        NervCell {
          id: shape
          anchors.centerIn: parent
          width: root.cellW
          height: root.cellH
          cuts: [root.cellH * 0.34, 0, root.cellH * 0.34, 0]
          fillColor: cell.fill
          strokeColor: cell.edge
          strokeWidth: cell.focused || cell.hot ? 0 : Math.max(1, Style.spaceReal(1))
        }

        NervSeg {
          visible: root.numerals === "seg"
          anchors.centerIn: shape
          anchors.horizontalCenterOffset: 0.5
          text: cell.numText
          digitHeight: Math.round(root.cellH * 0.72)
          thickness: Math.max(1.5, digitHeight * 0.15)
          widthRatio: 0.6
          skew: 0.08
          color: cell.digit
          showDim: false
        }

        Text {
          visible: root.numerals !== "seg"
          anchors.centerIn: shape
          textFormat: Text.PlainText
          text: root.numerals === "kanji" ? root.kanji[cell.modelData] : cell.numText
          color: cell.digit
          font.family: root.numerals === "kanji" ? "Noto Sans CJK JP" : "IBM Plex Mono"
          font.weight: Font.Bold
          font.pixelSize: Math.round(root.cellH * (root.numerals === "kanji" ? 0.62 : 0.72))
        }
      }
    }
  }
}
