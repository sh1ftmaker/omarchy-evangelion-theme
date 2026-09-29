import QtQuick
import "Palette.js" as Pal
import "Draw.js" as Draw

// One hex cell per CPU thread in a two-row honeycomb. Each cell fills from the
// bottom in hard quarter steps and carries its load in tiny mono digits.
Canvas {
  id: hexes
  property var loads: []
  property real r: 12.5
  readonly property int n: Math.max(1, loads.length)
  readonly property int cols: Math.ceil(n / 2)
  readonly property real dx: Math.sqrt(3) * r
  readonly property real dy: 1.5 * r

  implicitWidth: cols * dx + dx / 2 + 2
  implicitHeight: 2 * r + dy + 2

  onLoadsChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.font = "bold 7px \"" + Pal.mono + "\""
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    for (var i = 0; i < loads.length; i++) {
      var row = i < cols ? 0 : 1
      var col = row === 0 ? i : i - cols
      var cx = 1 + dx / 2 + col * dx + (row ? dx / 2 : 0)
      var cy = 1 + r + row * dy
      var v = loads[i]
      var q = Draw.step(v, 4)
      var colr = v > Pal.HOT ? Pal.red : (v > 0.6 ? Pal.amber : Pal.orange)
      var ri = r - 1.6

      Draw.hex(ctx, cx, cy, ri)
      ctx.fillStyle = Pal.ink
      ctx.fill()
      if (q > 0) {
        ctx.save()
        Draw.hex(ctx, cx, cy, ri)
        ctx.clip()
        ctx.fillStyle = colr
        var top = cy + ri - q * 2 * ri
        ctx.fillRect(cx - ri, top, ri * 2, cy + ri - top)
        ctx.restore()
      }
      Draw.hex(ctx, cx, cy, ri)
      ctx.lineWidth = 1
      ctx.strokeStyle = q > 0 ? colr : Pal.graphite
      ctx.stroke()

      var label = String(Math.min(99, Math.round(v * 100)))
      if (label.length < 2) label = "0" + label
      ctx.fillStyle = q >= 0.75 ? Pal.ink : Pal.bone
      ctx.fillText(label, cx, cy + 0.5)
    }
  }
}
