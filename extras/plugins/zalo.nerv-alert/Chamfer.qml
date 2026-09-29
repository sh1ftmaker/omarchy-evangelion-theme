import QtQuick
import QtQuick.Shapes

// Rectangle with 45-degree cut corners (never rounded). cuts = [tl, tr, br, bl].
Shape {
  id: s
  property real cut: 12
  property var cuts: [cut, cut, cut, cut]
  property color fillColor: "transparent"
  property color strokeColor: "transparent"
  property real strokeWidth: 0

  readonly property real i: strokeWidth / 2
  readonly property var pts: {
    var w = width, h = height, o = i
    var a = cuts[0], b = cuts[1], d = cuts[2], e = cuts[3]
    return [
      Qt.point(o + a, o), Qt.point(w - o - b, o), Qt.point(w - o, o + b),
      Qt.point(w - o, h - o - d), Qt.point(w - o - d, h - o), Qt.point(o + e, h - o),
      Qt.point(o, h - o - e), Qt.point(o, o + a), Qt.point(o + a, o)
    ]
  }

  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    fillColor: s.fillColor
    strokeColor: s.strokeWidth > 0 ? s.strokeColor : "transparent"
    strokeWidth: s.strokeWidth
    joinStyle: ShapePath.MiterJoin
    capStyle: ShapePath.SquareCap
    PathPolyline { path: s.pts }
  }
}
