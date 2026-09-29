import QtQuick
import "Pal.js" as Pal

// A NERV panel in the wall's shared chrome (same geometry as zalo.nerv-tactical's NervPanel):
// chamfered frame (top-right + bottom-left cut at 45°), dark translucent fill, a solid header
// tab with a slanted right edge and the title knocked out in ink (tracked mono caps + JP),
// a tick run along the top, a thin inner rule under the header and a bottom-right corner
// tick. Extras kept from the psychograph: a small code tag after the tab and a status
// readout at the right end of the header. Painted once per resize / recolour.
Item {
  id: frame

  property string title: ""
  property string jpTitle: ""
  property color accent: Pal.orange
  property string status: ""
  property string statusJp: ""
  property color statusColor: Pal.green
  property bool statusLit: true
  property string code: ""          // small tag after the tab (e.g. "CH-06")
  property real fillAlpha: 0.66
  // shared wall chrome metrics (NervPanel: header 14, cut 14 for a tile, 1 px line)
  readonly property int headerH: 14
  readonly property int cut: 14
  readonly property real lineWidth: 1

  readonly property real tabW: Math.min(width * 0.78, titleRow.implicitWidth + 18)
  readonly property real codeEnd: code !== "" ? codeText.x + codeText.implicitWidth : tabW + headerH * 0.6
  readonly property real statusStart: status !== "" ? statusRow.x : width - cut

  function css(c) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(3) + ")" }

  onAccentChanged: bg.requestPaint()
  onFillAlphaChanged: bg.requestPaint()
  onTabWChanged: bg.requestPaint()
  onCodeEndChanged: bg.requestPaint()
  onStatusStartChanged: bg.requestPaint()
  onWidthChanged: bg.requestPaint()
  onHeightChanged: bg.requestPaint()

  Canvas {
    id: bg
    anchors.fill: parent
    onPaint: {
      var c = getContext("2d")
      var w = width, h = height, k = frame.cut, hh = frame.headerH
      var ac = frame.css(frame.accent)
      c.reset()
      c.clearRect(0, 0, width, height)
      c.lineJoin = "miter"
      // body
      c.beginPath()
      c.moveTo(0.5, 0.5); c.lineTo(w - k, 0.5); c.lineTo(w - 0.5, k)
      c.lineTo(w - 0.5, h - 0.5); c.lineTo(k, h - 0.5); c.lineTo(0.5, h - k)
      c.closePath()
      c.fillStyle = "rgba(5,4,2," + frame.fillAlpha + ")"
      c.fill()
      c.strokeStyle = ac
      c.lineWidth = frame.lineWidth
      c.stroke()
      if (frame.title.length > 0) {
        // header tab (slanted right edge)
        var tw = frame.tabW
        c.beginPath()
        c.moveTo(0, 0); c.lineTo(tw, 0); c.lineTo(tw + hh * 0.6, hh); c.lineTo(0, hh); c.closePath()
        c.fillStyle = ac
        c.fill()
        // tick run between the code tag and the status readout
        c.fillStyle = ac
        c.globalAlpha = 0.55
        var x1 = Math.min(w - k - 4, frame.statusStart - 8)
        for (var x = frame.codeEnd + 8; x < x1; x += 4) c.fillRect(Math.round(x), 3, 1, Math.round(x) % 20 < 4 ? 6 : 3)
        // inner rule
        c.globalAlpha = 0.45
        c.fillRect(4, hh + 2, w - 8, 1)
        c.globalAlpha = 1
      }
      // corner tick bottom-right
      c.fillStyle = ac
      c.fillRect(w - 7, h - 3, 5, 1)
      c.fillRect(w - 3, h - 7, 1, 5)
    }
  }

  Row {
    id: titleRow
    visible: frame.title.length > 0
    x: 6
    height: frame.headerH
    spacing: 5
    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 0.5
      text: frame.title.toUpperCase()
      color: Pal.ink
      font.family: Pal.mono
      font.weight: Font.Bold
      font.pixelSize: 9
      font.letterSpacing: 1.4
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: frame.jpTitle.length > 0
      text: frame.jpTitle
      color: Pal.ink
      font.family: Pal.jp
      font.weight: Font.Black
      font.pixelSize: 9
    }
  }

  Text {
    id: codeText
    x: frame.tabW + frame.headerH * 0.6 + 6
    anchors.verticalCenter: parent.top
    anchors.verticalCenterOffset: frame.headerH / 2
    visible: frame.code !== ""
    text: frame.code
    color: frame.accent
    opacity: 0.8
    font.family: Pal.mono
    font.weight: Font.DemiBold
    font.pixelSize: 8
    font.letterSpacing: 1.2
  }

  Row {
    id: statusRow
    x: frame.width - frame.cut - 4 - implicitWidth
    anchors.verticalCenter: parent.top
    anchors.verticalCenterOffset: frame.headerH / 2
    visible: frame.status !== ""
    spacing: 5
    opacity: frame.statusLit ? 1 : 0.18

    Rectangle {
      width: 6; height: 6
      anchors.verticalCenter: parent.verticalCenter
      color: frame.statusColor
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 0.5
      text: frame.status
      color: frame.statusColor
      font.family: Pal.mono
      font.weight: Font.Bold
      font.pixelSize: 9
      font.letterSpacing: 1.4
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: frame.statusJp
      color: frame.statusColor
      font.family: Pal.jp
      font.weight: Font.Bold
      font.pixelSize: 9
    }
  }
}
