import QtQuick
import QtQuick.Shapes

// 7-segment readout drawn with vector Shapes (crisp at any scale / DPR).
// Supports 0-9, - : . space and a few letters.
Item {
  id: s
  property string text: "0"
  property real digitHeight: 48
  property color color: "#FF7A00"
  property color dimColor: Qt.rgba(1, 0.48, 0, 0.08)
  property bool showDim: true
  property real skew: 0.1
  property real thickness: digitHeight * 0.11
  property real widthRatio: 0.52

  readonly property real dw: digitHeight * widthRatio
  readonly property real th: thickness
  readonly property var segs: ({
    "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg",
    "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": "", "A": "abcefg", "E": "adefg",
    "F": "aefg", "H": "bcefg", "L": "def", "P": "abefg", "r": "eg", "o": "cdeg", "U": "bcdef",
    "n": "ceg", "t": "defg", "d": "bcdeg", "b": "cdefg", "C": "adef", "S": "acdfg"
  })

  function advance(ch) { return (ch === ":" || ch === ".") ? th * 2.6 : dw + th * 1.2 }
  function totalWidth(txt) {
    var w = 0
    for (var i = 0; i < txt.length; i++) w += advance(txt.charAt(i))
    return Math.max(0, w - th * 1.2)
  }

  function segPts(seg) {
    var h = digitHeight, w = dw, t = th, sk = skew, gap = t * 0.18, m = h / 2, hw = t / 2
    var raw
    if (seg === "a" || seg === "g" || seg === "d") {
      var yy = seg === "a" ? hw : seg === "g" ? m : h - hw
      raw = [[gap + hw, yy], [gap + t, yy - hw], [w - gap - t, yy - hw], [w - gap - hw, yy], [w - gap - t, yy + hw], [gap + t, yy + hw]]
    } else {
      var xx = (seg === "f" || seg === "e") ? hw : w - hw
      var y0 = (seg === "f" || seg === "b") ? 0 : m
      var y1 = y0 === 0 ? m : h
      raw = [[xx, y0 + gap + hw], [xx + hw, y0 + gap + t], [xx + hw, y1 - gap - t], [xx, y1 - gap - hw], [xx - hw, y1 - gap - t], [xx - hw, y0 + gap + t]]
    }
    var out = []
    for (var i = 0; i < raw.length; i++) out.push(Qt.point(raw[i][0] + (h - raw[i][1]) * sk, raw[i][1]))
    out.push(out[0])
    return out
  }

  implicitWidth: totalWidth(text) + digitHeight * skew
  implicitHeight: digitHeight
  width: implicitWidth
  height: implicitHeight

  Row {
    spacing: 0
    Repeater {
      model: s.text.split("")
      Item {
        id: digit
        required property string modelData
        readonly property bool isDot: modelData === ":" || modelData === "."
        readonly property string lit: s.segs[modelData] !== undefined ? s.segs[modelData] : ""
        width: s.advance(modelData)
        height: s.digitHeight

        Repeater {
          model: digit.isDot ? [] : ["a", "b", "c", "d", "e", "f", "g"]
          Shape {
            id: segShape
            required property string modelData
            readonly property bool on: digit.lit.indexOf(modelData) >= 0
            visible: on || s.showDim
            width: s.dw + s.digitHeight * s.skew
            height: s.digitHeight
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              strokeColor: "transparent"
              strokeWidth: 0
              fillColor: segShape.on ? s.color : s.dimColor
              PathPolyline { path: s.segPts(segShape.modelData) }
            }
          }
        }
        Rectangle {
          visible: digit.isDot
          color: s.color
          width: s.th; height: s.th
          x: s.th * 0.6 + s.digitHeight * (digit.modelData === ":" ? 0.66 : 0) * s.skew
          y: digit.modelData === ":" ? s.digitHeight * 0.3 : s.digitHeight - s.th
        }
        Rectangle {
          visible: digit.modelData === ":"
          color: s.color
          width: s.th; height: s.th
          x: s.th * 0.6 + s.digitHeight * 0.3 * s.skew
          y: s.digitHeight * 0.66
        }
      }
    }
  }
}
