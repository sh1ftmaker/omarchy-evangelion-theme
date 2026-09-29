import QtQuick

// Diagonal hazard stripes. The stripe canvas is painted once; `phase` (px)
// only moves it, so scrolling costs nothing but a translate.
Item {
  id: r
  property color color: "#FF1A1A"
  property real stripe: 14
  property real phase: 0
  clip: true

  Canvas {
    id: c
    readonly property real period: r.stripe * 2
    x: -(((r.phase % period) + period) % period) - period
    y: 0
    width: r.width + period * 3 + r.height
    height: r.height
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections {
      target: r
      function onColorChanged() { c.requestPaint() }
      function onStripeChanged() { c.requestPaint() }
    }
    onPaint: {
      var g = getContext("2d")
      g.reset()
      g.fillStyle = r.color
      var h = height, s = r.stripe
      for (var sx = -h; sx < width + s; sx += s * 2) {
        g.beginPath()
        g.moveTo(sx, h); g.lineTo(sx + h, 0); g.lineTo(sx + h + s, 0); g.lineTo(sx + s, h)
        g.closePath(); g.fill()
      }
    }
  }
}
