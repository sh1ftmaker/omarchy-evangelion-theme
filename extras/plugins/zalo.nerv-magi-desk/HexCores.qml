import QtQuick
import QtQuick.Shapes
import "Palette.js" as Pal

// One hex cell per CPU thread in a two-row honeycomb. Each cell's fill level eases toward the
// latest sample (Behavior, only animating for ~0.7 s after a 2 s sample) and carries its load in
// tiny mono digits. The fill is a hexagon clipped at the level line (a Shape polygon: a few
// vertices re-triangulated while easing), so nothing is repainted into a Canvas per frame.
Item {
  id: hexes
  property var loads: []
  property real r: 12.5
  readonly property int n: Math.max(1, loads.length)
  readonly property int cols: Math.ceil(n / 2)
  readonly property real dx: Math.sqrt(3) * r
  readonly property real dy: 1.5 * r
  readonly property real ri: r - 1.6

  implicitWidth: cols * dx + dx / 2 + 2
  implicitHeight: 2 * r + dy + 2

  // pointy-top hexagon (matches Draw.hex), closed
  function hexPts(cx, cy, rr) {
    var p = []
    for (var i = 0; i < 6; i++) {
      var a = Math.PI / 6 + i * Math.PI / 3
      p.push(Qt.point(cx + rr * Math.cos(a), cy + rr * Math.sin(a)))
    }
    p.push(p[0])
    return p
  }
  // the part of a closed convex polygon at or below the line y = top
  function clipBelow(pts, top) {
    var out = []
    for (var i = 0; i < pts.length - 1; i++) {
      var a = pts[i], b = pts[i + 1]
      var ain = a.y >= top, bin = b.y >= top
      if (ain) out.push(a)
      if (ain !== bin) {
        var k = (top - a.y) / (b.y - a.y)
        out.push(Qt.point(a.x + (b.x - a.x) * k, top))
      }
    }
    if (out.length > 0) out.push(out[0])
    return out
  }

  Repeater {
    model: hexes.loads.length
    Item {
      id: cell
      required property int index
      readonly property int row: index < hexes.cols ? 0 : 1
      readonly property int col: row === 0 ? index : index - hexes.cols
      readonly property real cx: 1 + hexes.dx / 2 + col * hexes.dx + (row ? hexes.dx / 2 : 0)
      readonly property real cy: 1 + hexes.r + row * hexes.dy
      readonly property real raw: Math.max(0, Math.min(1, hexes.loads[index] || 0))
      property real v: raw
      Behavior on v { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
      readonly property color colr: raw > Pal.HOT ? Pal.red : (raw > 0.6 ? Pal.amber : Pal.orange)
      readonly property var outline: hexes.hexPts(cx, cy, hexes.ri)
      readonly property var fillPoly: v > 0.004 ? hexes.clipBelow(outline, cy + hexes.ri - v * 2 * hexes.ri) : []

      Shape {
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
          fillColor: Pal.ink
          strokeColor: "transparent"
          PathPolyline { path: cell.outline }
        }
        ShapePath {
          fillColor: cell.colr
          strokeColor: "transparent"
          PathPolyline { path: cell.fillPoly }
        }
        ShapePath {
          fillColor: "transparent"
          strokeColor: cell.raw > 0 ? cell.colr : Pal.graphite
          strokeWidth: 1
          PathPolyline { path: cell.outline }
        }
      }
      Text {
        textFormat: Text.PlainText
        renderType: Text.QtRendering
        x: cell.cx - width / 2
        y: cell.cy + 0.5 - height / 2
        text: {
          var s = String(Math.min(99, Math.round(cell.raw * 100)))
          return s.length < 2 ? "0" + s : s
        }
        color: cell.v >= 0.75 ? Pal.ink : Pal.bone
        font.family: Pal.mono
        font.bold: true
        font.pixelSize: Math.max(6, Math.round(hexes.r * 0.72))
      }
    }
  }
}
