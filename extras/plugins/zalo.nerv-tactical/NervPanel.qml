import QtQuick

// A NERV panel: chamfered frame (top-right + bottom-left cut at 45°), dark translucent fill,
// a solid header tab with the title knocked out in ink, and a thin inner rule.
// Painted once per resize/recolour; children go into the content area below the header.
Item {
  id: p

  function css(c) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(3) + ")" }

  property string title: ""
  property string jp: ""
  property color accent: "#FF7A00"
  property color fill: Qt.rgba(0.02, 0.014, 0.008, 0.66)
  property real cut: 10
  property real header: 14
  property real lineWidth: 1
  property bool alarm: false          // inverts the header tab to red
  default property alias content: body.data
  readonly property alias body: body

  readonly property color tabColor: alarm ? "#FF1A1A" : accent
  readonly property real tabW: Math.min(width * 0.78, titleRow.implicitWidth + 18)

  onTabWChanged: frame.requestPaint()
  onTabColorChanged: frame.requestPaint()
  onAccentChanged: frame.requestPaint()
  onFillChanged: frame.requestPaint()
  onCutChanged: frame.requestPaint()
  onHeaderChanged: frame.requestPaint()

  Canvas {
    id: frame
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      var w = width, h = height, k = p.cut, hh = p.header
      c.reset()
      c.clearRect(0, 0, width, height)
      c.lineJoin = "miter"
      // body
      c.beginPath()
      c.moveTo(0.5, 0.5); c.lineTo(w - k, 0.5); c.lineTo(w - 0.5, k)
      c.lineTo(w - 0.5, h - 0.5); c.lineTo(k, h - 0.5); c.lineTo(0.5, h - k)
      c.closePath()
      c.fillStyle = css(p.fill)
      c.fill()
      c.strokeStyle = css(p.accent)
      c.lineWidth = p.lineWidth
      c.stroke()
      if (p.title.length > 0) {
        // header tab (slanted right edge)
        var tw = p.tabW
        c.beginPath()
        c.moveTo(0, 0); c.lineTo(tw, 0); c.lineTo(tw + hh * 0.6, hh); c.lineTo(0, hh); c.closePath()
        c.fillStyle = css(p.tabColor)
        c.fill()
        // tick run to the right of the tab
        c.fillStyle = css(p.accent)
        c.globalAlpha = 0.55
        for (var x = tw + hh * 0.6 + 6; x < w - k - 4; x += 4) c.fillRect(Math.round(x), 3, 1, x % 20 < 4 ? 6 : 3)
        // inner rule
        c.globalAlpha = 0.45
        c.fillRect(4, hh + 2, w - 8, 1)
        c.globalAlpha = 1
      }
      // corner tick bottom-right
      c.fillStyle = css(p.accent)
      c.fillRect(w - 7, h - 3, 5, 1)
      c.fillRect(w - 3, h - 7, 1, 5)
    }
  }

  Row {
    id: titleRow
    visible: p.title.length > 0
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
      visible: p.jp.length > 0
      text: p.jp
      color: "#050403"
      font.family: "Noto Sans CJK JP"
      font.weight: Font.Black
      font.pixelSize: 9
    }
  }

  Item {
    id: body
    x: 6
    y: p.title.length > 0 ? p.header + 5 : 5
    width: p.width - 12
    height: p.height - y - 5
  }
}
