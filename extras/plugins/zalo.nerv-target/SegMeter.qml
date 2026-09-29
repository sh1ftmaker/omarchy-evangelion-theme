import QtQuick

// Segmented level meter: n blocks filled to value (0..1); blocks past hotFrom turn `hot`.
// Two canvases painted once (dim track, fully lit row); the lit one sits in a clip whose width
// follows `value`, so a continuously changing value costs one property change, not a repaint.
Item {
  id: m

  function css(c) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(3) + ")" }

  property int segments: 20
  property real value: 0
  property real hotFrom: 0.8
  property color color: "#FF7A00"
  property color hot: "#FF1A1A"
  property color dim: Qt.rgba(1, 0.48, 0, 0.11)
  property real gap: 1
  property bool vertical: false

  function paintRow(c, lit) {
    c.reset()
    c.clearRect(0, 0, width, height)
    var n = segments
    for (var i = 0; i < n; i++) {
      c.fillStyle = css(lit ? (i / n >= hotFrom ? hot : color) : dim)
      if (vertical) {
        var bh = (height - gap * (n - 1)) / n
        c.fillRect(0, height - (i + 1) * bh - i * gap, width, bh)
      } else {
        var bw = (width - gap * (n - 1)) / n
        c.fillRect(i * (bw + gap), 0, bw, height)
      }
    }
  }

  readonly property real v: Math.max(0, Math.min(1, value))

  onColorChanged: { track.requestPaint(); litRow.requestPaint() }
  onHotChanged: litRow.requestPaint()
  onDimChanged: track.requestPaint()

  Canvas {
    id: track
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: m.paintRow(getContext("2d"), false)
  }
  Item {
    x: 0
    y: m.vertical ? m.height * (1 - m.v) : 0
    width: m.vertical ? m.width : m.width * m.v
    height: m.vertical ? m.height * m.v : m.height
    clip: true
    Canvas {
      id: litRow
      y: m.vertical ? -parent.y : 0
      width: m.width; height: m.height
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: m.paintRow(getContext("2d"), true)
    }
  }
}
