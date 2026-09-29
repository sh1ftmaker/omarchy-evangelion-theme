import QtQuick
import "Palette.js" as Pal
import "Draw.js" as Draw

// The bar face: three chamfered MAGI blocks (M·1 / B·2 / C·3), each a hard-stepped
// level meter of its unit's load, joined by short bus bars. Vertical bars stack them.
Canvas {
  id: glyph

  property var loads: [0, 0, 0]       // -1 = unit offline
  property bool vertical: false
  readonly property var labels: vertical ? ["M1", "B2", "C3"] : ["M·1", "B·2", "C·3"]

  readonly property int bw: vertical ? 22 : 30
  readonly property int bh: vertical ? 14 : 16
  readonly property int gap: vertical ? 5 : 6
  readonly property int segs: 8

  implicitWidth: vertical ? bw : bw * 3 + gap * 2
  implicitHeight: vertical ? bh * 3 + gap * 2 : bh
  width: implicitWidth
  height: implicitHeight

  onLoadsChanged: requestPaint()
  onVerticalChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.lineJoin = "miter"
    var fontPx = vertical ? 7.5 : 8.5
    ctx.font = "bold " + fontPx + "px \"" + Pal.mono + "\""
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"

    // bus bars between blocks
    ctx.fillStyle = Pal.orange
    for (var k = 0; k < 2; k++) {
      if (vertical) ctx.fillRect(bw / 2 - 2, (k + 1) * bh + k * gap, 4, gap)
      else ctx.fillRect((k + 1) * bw + k * gap, bh / 2 - 1.5, gap, 3)
    }

    for (var i = 0; i < 3; i++) {
      var x = vertical ? 0 : i * (bw + gap)
      var y = vertical ? i * (bh + gap) : 0
      var load = loads && loads.length > i ? loads[i] : 0
      var col = Pal.stateColor(load)
      var cut = [4, 0, 4, 0]

      // body
      Draw.chamfer(ctx, x + 0.5, y + 0.5, bw - 1, bh - 1, cut)
      ctx.fillStyle = Pal.ink
      ctx.fill()

      // stepped segment fill, left to right
      var lit = load > 0 ? Math.min(segs, Math.ceil(load * segs - 1e-6)) : 0
      var ix = x + 2, iy = y + 2, iw = bw - 4, ih = bh - 4
      var sw = iw / segs
      ctx.save()
      Draw.chamfer(ctx, x + 0.5, y + 0.5, bw - 1, bh - 1, cut)
      ctx.clip()
      for (var s = 0; s < segs; s++) {
        ctx.fillStyle = s < lit ? col : Pal.graphite
        ctx.globalAlpha = s < lit ? 1 : 0.35
        ctx.fillRect(ix + s * sw, iy, Math.max(1, sw - 1), ih)
      }
      ctx.globalAlpha = 1
      ctx.restore()
      // label: bone with an ink knock-out outline so it reads over lit segments
      ctx.lineWidth = 2.5
      ctx.strokeStyle = Pal.ink
      ctx.strokeText(labels[i], x + bw / 2, y + bh / 2 + 0.5)
      ctx.fillStyle = load < 0 ? Pal.ash : Pal.bone
      ctx.fillText(labels[i], x + bw / 2, y + bh / 2 + 0.5)

      // frame
      Draw.chamfer(ctx, x + 0.5, y + 0.5, bw - 1, bh - 1, cut)
      ctx.strokeStyle = col
      ctx.lineWidth = 1
      ctx.stroke()
    }
  }
}
