import QtQuick

// Chamfered (45°) rectangle with per-corner cuts [tl, tr, br, bl], solid fill and/or outline.
// `slash` draws the diagonal "cut" stroke used for severed / dead indicators.
Canvas {
  id: root

  property var cuts: [0, 8, 0, 8]
  property color fill: "transparent"
  property color stroke: "#FF7A00"
  property real lineWidth: 1.5
  property bool slash: false
  property color slashColor: stroke

  antialiasing: true
  onFillChanged: requestPaint()
  onStrokeChanged: requestPaint()
  onSlashChanged: requestPaint()
  onSlashColorChanged: requestPaint()
  onCutsChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var c = getContext("2d")
    c.reset()
    var o = lineWidth / 2, w = width, h = height
    var a = cuts[0], b = cuts[1], d = cuts[2], e = cuts[3]
    c.beginPath()
    c.moveTo(o + a, o); c.lineTo(w - o - b, o); c.lineTo(w - o, o + b)
    c.lineTo(w - o, h - o - d); c.lineTo(w - o - d, h - o); c.lineTo(o + e, h - o)
    c.lineTo(o, h - o - e); c.lineTo(o, o + a); c.closePath()
    if (fill.a > 0) { c.fillStyle = String(fill); c.fill() }
    if (stroke.a > 0 && lineWidth > 0) { c.strokeStyle = String(stroke); c.lineWidth = lineWidth; c.stroke() }
    if (slash) {
      c.strokeStyle = String(slashColor)
      c.lineWidth = 2.5
      c.beginPath(); c.moveTo(6, h - 6); c.lineTo(w - 6, 6); c.stroke()
    }
  }
}
