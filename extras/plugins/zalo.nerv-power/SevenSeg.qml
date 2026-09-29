import QtQuick

// Real 7-segment readout drawn as hexagonal segment polygons (port of sevenSeg() in the
// evangelion plate kit, _eva.ts). Unlit segments paint in `dim` so the "88:88" ghost shows,
// like an LCD. Height = digit height; width follows the text.
Canvas {
  id: root

  property string text: "00:00"
  property color color: "#FF7A00"
  property color dim: Qt.rgba(1, 0.478, 0, 0.09)
  property real digitHeight: height
  property real thick: digitHeight * 0.11
  property real skew: 0.1
  property bool colonOn: true

  readonly property var segMap: ({
    "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg",
    "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": "",
    "A": "abcefg", "E": "adefg", "F": "aefg", "H": "bcefg", "L": "def", "P": "abefg",
    "r": "eg", "o": "cdeg", "U": "bcdef", "n": "ceg", "t": "defg", "d": "bcdeg",
    "b": "cdefg", "C": "adef", "S": "acdfg"
  })

  function textWidth(s, h, t) {
    var w = 0
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i)
      w += (ch === ":" || ch === ".") ? t * 2.6 : h * 0.52 + t * 1.2
    }
    return w - t * 1.2 * 0.5 + h * root.skew
  }

  implicitHeight: digitHeight
  implicitWidth: Math.ceil(textWidth(text, digitHeight, thick))
  antialiasing: true
  renderStrategy: Canvas.Cooperative

  onTextChanged: requestPaint()
  onColorChanged: requestPaint()
  onDimChanged: requestPaint()
  onColonOnChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var c = getContext("2d")
    c.reset()
    var h = digitHeight, t = thick, sk = skew
    var w = h * 0.52, gap = t * 0.18, m = h / 2, hw = t / 2
    var cx = 0
    var on = String(color), off = String(dim)

    function poly(pts, lit) {
      c.fillStyle = lit ? on : off
      c.beginPath()
      for (var i = 0; i < pts.length; i++) {
        var X = cx + pts[i][0] + (h - pts[i][1]) * sk, Y = pts[i][1]
        if (i === 0) c.moveTo(X, Y); else c.lineTo(X, Y)
      }
      c.closePath()
      c.fill()
    }
    function hz(yy) {
      return [[gap + hw, yy], [gap + t, yy - hw], [w - gap - t, yy - hw], [w - gap - hw, yy], [w - gap - t, yy + hw], [gap + t, yy + hw]]
    }
    function vt(xx, y0, y1) {
      return [[xx, y0 + gap + hw], [xx + hw, y0 + gap + t], [xx + hw, y1 - gap - t], [xx, y1 - gap - hw], [xx - hw, y1 - gap - t], [xx - hw, y0 + gap + t]]
    }

    for (var i = 0; i < text.length; i++) {
      var ch = text.charAt(i)
      if (ch === ":" || ch === ".") {
        c.fillStyle = (ch === ":" && !colonOn) ? off : on
        if (ch === ":") {
          c.fillRect(cx + t * 0.6 + h * 0.66 * sk, h * 0.3, t, t)
          c.fillRect(cx + t * 0.6 + h * 0.3 * sk, h * 0.66, t, t)
        } else {
          c.fillRect(cx + t * 0.4, h - t, t, t)
        }
        cx += t * 2.6
        continue
      }
      var s = segMap[ch] !== undefined ? segMap[ch] : ""
      poly(hz(hw), s.indexOf("a") >= 0)
      poly(hz(m), s.indexOf("g") >= 0)
      poly(hz(h - hw), s.indexOf("d") >= 0)
      poly(vt(hw, 0, m), s.indexOf("f") >= 0)
      poly(vt(w - hw, 0, m), s.indexOf("b") >= 0)
      poly(vt(hw, m, h), s.indexOf("e") >= 0)
      poly(vt(w - hw, m, h), s.indexOf("c") >= 0)
      cx += w + t * 1.2
    }
  }
}
