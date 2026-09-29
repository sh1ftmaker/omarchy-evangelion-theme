import QtQuick

// NERV panel chrome in SEELE red (same construction as zalo.nerv-tactical/NervPanel.qml):
// chamfered frame (top-right + bottom-left 45° cuts), translucent ink fill, solid header tab
// with the title knocked out in ink, tick run, inner rule, corner brackets. Painted on resize only.
Item {
  id: p

  property string title: ""
  property string jp: ""
  property string code: ""
  property color accent: "#FF1A1A"
  property real fillAlpha: 0.82
  property real cut: 11
  property real header: 15
  default property alias content: body.data

  readonly property real tabW: titleRow.implicitWidth + 16

  onTabWChanged: frame.requestPaint()
  onFillAlphaChanged: frame.requestPaint()

  Canvas {
    id: frame
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      var w = width, h = height, k = p.cut, hh = p.header
      c.reset()
      c.lineJoin = "miter"
      c.beginPath()
      c.moveTo(0.5, 0.5); c.lineTo(w - k, 0.5); c.lineTo(w - 0.5, k)
      c.lineTo(w - 0.5, h - 0.5); c.lineTo(k, h - 0.5); c.lineTo(0.5, h - k)
      c.closePath()
      c.fillStyle = "rgba(5,4,3," + p.fillAlpha + ")"
      c.fill()
      c.strokeStyle = "rgba(255,26,26,0.85)"
      c.lineWidth = 1
      c.stroke()
      // header tab, slanted right edge
      var tw = p.tabW
      c.beginPath()
      c.moveTo(0, 0); c.lineTo(tw, 0); c.lineTo(tw + hh * 0.6, hh); c.lineTo(0, hh); c.closePath()
      c.fillStyle = "#FF1A1A"
      c.fill()
      // tick run
      c.fillStyle = "#FF1A1A"
      c.globalAlpha = 0.5
      var x0 = tw + hh * 0.6 + 6
      for (var x = x0; x < w - k - 4; x += 4) c.fillRect(Math.round(x), 3, 1, (x - x0) % 20 < 4 ? 6 : 3)
      // inner rule
      c.globalAlpha = 0.4
      c.fillRect(4, hh + 2, w - 8, 1)
      c.globalAlpha = 1
      // corner brackets
      c.strokeStyle = "rgba(255,26,26,0.7)"
      c.beginPath()
      var bx = 3.5, by = hh + 5.5, bw = w - 7, bh = h - hh - 9, L = 6
      c.moveTo(bx, by + L); c.lineTo(bx, by); c.lineTo(bx + L, by)
      c.moveTo(bx + bw - L, by); c.lineTo(bx + bw, by); c.lineTo(bx + bw, by + L)
      c.moveTo(bx + bw, by + bh - L); c.lineTo(bx + bw, by + bh); c.lineTo(bx + bw - L, by + bh)
      c.moveTo(bx + L, by + bh); c.lineTo(bx, by + bh); c.lineTo(bx, by + bh - L)
      c.stroke()
      // corner tick bottom-right
      c.fillStyle = "#FF1A1A"
      c.fillRect(w - 7, h - 3, 5, 1)
      c.fillRect(w - 3, h - 7, 1, 5)
    }
  }

  Row {
    id: titleRow
    x: 6
    height: p.header
    spacing: 5
    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 0.5
      text: p.title.toUpperCase()
      color: "#050403"
      font.family: "IBM Plex Mono"
      font.weight: Font.Bold
      font.pixelSize: 9
      font.letterSpacing: 1.4
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: p.jp
      color: "#050403"
      font.family: "Noto Sans CJK JP"
      font.weight: Font.Black
      font.pixelSize: 9
    }
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: 12
    y: p.header + 4
    visible: p.code !== ""
    text: p.code
    color: "#FF1A1A"
    opacity: 0.55
    font.family: "IBM Plex Mono"
    font.weight: Font.DemiBold
    font.pixelSize: 6
    font.letterSpacing: 1.2
  }

  Item {
    id: body
    anchors.fill: parent
  }
}
