import QtQuick

// Segmented level meter: n blocks filled to value (0..1); blocks past hotFrom turn `hot`.
// Two canvases are painted once (unlit track + fully-lit bar); `value` only moves a clip
// edge, so easing the value every frame costs a geometry change, not a repaint.
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
  readonly property real level: Math.max(0, Math.min(1, value))

  function paintBlocks(cv, lit) {
    var c = cv.getContext("2d")
    c.reset()
    c.clearRect(0, 0, cv.width, cv.height)
    var n = segments, W = m.width, H = m.height
    for (var i = 0; i < n; i++) {
      c.fillStyle = css(lit ? (i / n >= hotFrom ? hot : color) : dim)
      if (vertical) {
        var bh = (H - gap * (n - 1)) / n
        c.fillRect(0, H - (i + 1) * bh - i * gap, W, bh)
      } else {
        var bw = (W - gap * (n - 1)) / n
        c.fillRect(i * (bw + gap), 0, bw, H)
      }
    }
  }

  Canvas {
    id: track
    anchors.fill: parent
    onPaint: m.paintBlocks(track, false)
  }
  Item {
    id: clipper
    clip: true
    x: 0
    y: m.vertical ? m.height * (1 - m.level) : 0
    width: m.vertical ? m.width : m.width * m.level
    height: m.vertical ? m.height * m.level : m.height
    Canvas {
      id: bar
      x: 0
      y: -clipper.y
      width: m.width
      height: m.height
      onPaint: m.paintBlocks(bar, true)
    }
  }

  function repaint() { track.requestPaint(); bar.requestPaint() }
  onColorChanged: repaint()
  onHotChanged: repaint()
  onDimChanged: repaint()
  onHotFromChanged: repaint()
  onSegmentsChanged: repaint()
  onWidthChanged: repaint()
  onHeightChanged: repaint()
  Component.onCompleted: repaint()
}
