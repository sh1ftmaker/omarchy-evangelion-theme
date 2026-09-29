import QtQuick

// Diagonal hazard stripes (hazard() in _eva.ts). `phase` scrolls them in px.
// Desk variant: the stripes are painted once onto a canvas one period wider on each side,
// and scrolling just moves that canvas inside a clip — no repaint per step.
Item {
  id: root

  property color color: "#FF1A1A"
  property real stripe: 7
  property real phase: 0

  clip: true

  Canvas {
    id: cv
    readonly property real period: root.stripe * 2
    x: -period + ((root.phase % period) + period) % period
    width: root.width + period * 2
    height: root.height
    antialiasing: true
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections {
      target: root
      function onColorChanged() { cv.requestPaint() }
      function onStripeChanged() { cv.requestPaint() }
    }
    onPaint: {
      var c = getContext("2d")
      c.reset()
      var w = width, h = height, s = root.stripe
      c.fillStyle = String(root.color)
      for (var x = -h - s * 2; x < w + s; x += s * 2) {
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
}
