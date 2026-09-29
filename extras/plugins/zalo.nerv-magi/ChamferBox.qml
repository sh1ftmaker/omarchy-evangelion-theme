import QtQuick
import "Draw.js" as Draw

// Static chamfered frame. Repaints only when its inputs change.
Canvas {
  id: box
  property var cuts: [6, 6, 6, 6]
  property string fillColor: ""
  property real fillAlpha: 1
  property string strokeColor: ""
  property real strokeAlpha: 1
  property real lineWidth: 1

  onCutsChanged: requestPaint()
  onFillColorChanged: requestPaint()
  onFillAlphaChanged: requestPaint()
  onStrokeColorChanged: requestPaint()
  onStrokeAlphaChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var lw = strokeColor ? lineWidth : 0
    var h = lw / 2
    Draw.chamfer(ctx, h, h, width - lw, height - lw, cuts)
    if (fillColor) { ctx.globalAlpha = fillAlpha; ctx.fillStyle = fillColor; ctx.fill() }
    if (lw > 0) { ctx.globalAlpha = strokeAlpha; ctx.strokeStyle = strokeColor; ctx.lineWidth = lw; ctx.stroke() }
  }
}
