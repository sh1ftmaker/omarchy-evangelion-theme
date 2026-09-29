import QtQuick

// NERV panel (panel() in _eva.ts): chamfered 45° outline (top-right + bottom-left cut), dark
// fill, a solid header tab with the title knocked out in black, a thin rule under the header,
// and an optional status caption on the right. Children go into the content area.
Item {
  id: root

  property string title: ""
  property string jp: ""
  property string status: ""
  property color color: "#FF7A00"
  property color fill: Qt.rgba(18 / 255, 12 / 255, 6 / 255, 0.94)
  property color statusColor: color
  property real cut: 12
  property real headerHeight: title !== "" ? 20 : 0
  property real pad: 10
  property real lineWidth: 1.5
  default property alias content: body.data
  readonly property real contentWidth: width - pad * 2

  implicitHeight: headerHeight + body.childrenRect.height + pad * 2 + (title !== "" ? 6 : 0)

  onColorChanged: frame.requestPaint()
  onFillChanged: frame.requestPaint()

  Canvas {
    id: frame
    anchors.fill: parent
    antialiasing: true
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      var w = width, h = height, k = root.cut, lw = root.lineWidth, o = lw / 2
      c.beginPath()
      c.moveTo(o, o)
      c.lineTo(w - k, o)
      c.lineTo(w - o, k)
      c.lineTo(w - o, h - o)
      c.lineTo(k, h - o)
      c.lineTo(o, h - k)
      c.closePath()
      c.fillStyle = String(root.fill)
      c.fill()
      c.strokeStyle = String(root.color)
      c.lineWidth = lw
      c.stroke()
      if (root.headerHeight > 0) {
        var hh = root.headerHeight, tw = tab.width
        c.fillStyle = String(root.color)
        c.beginPath()
        c.moveTo(0, 0)
        c.lineTo(tw, 0)
        c.lineTo(tw + hh * 0.6, 0)
        c.lineTo(tw, hh)
        c.lineTo(0, hh)
        c.closePath()
        c.fill()
        c.globalAlpha = 0.5
        c.fillRect(5, hh + 3, w - 10, 1)
      }
    }
  }

  Row {
    id: tab
    visible: root.title !== ""
    x: 0
    height: root.headerHeight
    leftPadding: 8
    rightPadding: 6
    spacing: 7
    onWidthChanged: frame.requestPaint()

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.title.toUpperCase()
      color: "#050403"
      font.family: "IBM Plex Mono"
      font.weight: Font.Bold
      font.pixelSize: 11
      font.letterSpacing: 1.6
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.jp !== ""
      text: root.jp
      color: "#050403"
      font.family: "Noto Sans CJK JP"
      font.weight: Font.Black
      font.pixelSize: 11
    }
  }

  Text {
    visible: root.status !== ""
    anchors.right: parent.right
    anchors.rightMargin: root.cut + 4
    y: (root.headerHeight - height) / 2
    width: Math.max(0, root.width - tab.width - root.headerHeight - root.cut - 12)
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
    text: root.status
    color: root.statusColor
    font.family: "IBM Plex Mono"
    font.weight: Font.DemiBold
    font.pixelSize: 10
    font.letterSpacing: 1.5
  }

  Item {
    id: body
    x: root.pad
    y: root.headerHeight + root.pad + (root.title !== "" ? 6 : 0)
    width: root.contentWidth
    height: childrenRect.height
  }
}
