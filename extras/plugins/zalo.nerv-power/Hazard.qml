import QtQuick

// Diagonal hazard stripes (hazard() in _eva.ts). `phase` scrolls them in px; step it from a
// timer for the hard, terminal-like crawl.
Canvas {
  id: root

  property color color: "#FF1A1A"
  property color back: "transparent"
  property real stripe: 7
  property real phase: 0

  antialiasing: true
  onPhaseChanged: requestPaint()
  onColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var c = getContext("2d")
    c.reset()
    var w = width, h = height, s = stripe
    if (back.a > 0) { c.fillStyle = String(back); c.fillRect(0, 0, w, h) }
    c.fillStyle = String(color)
    var p = ((phase % (s * 2)) + s * 2) % (s * 2)
    for (var x = -h - s * 2 + p; x < w + s; x += s * 2) {
      c.beginPath()
      c.moveTo(x, h)
      c.lineTo(x + h, 0)
      c.lineTo(x + h + s, 0)
      c.lineTo(x + s, h)
      c.closePath()
      c.fill()
    }
  }
}
