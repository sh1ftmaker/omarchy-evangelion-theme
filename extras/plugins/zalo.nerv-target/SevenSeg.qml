import QtQuick

// 7-segment readout (the battery-countdown voice). Repaints only when text/colours change.
Canvas {
  id: s

  function css(c) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(3) + ")" }

  property string text: "00:00"
  property real digitHeight: 20
  property color color: "#FFB000"
  property color dim: Qt.rgba(1, 0.48, 0, 0.06)
  property real skew: 0.1
  readonly property real thick: Math.max(1.6, digitHeight * 0.12)
  readonly property real digitW: digitHeight * 0.52

  function measure(t) {
    var w = 0
    for (var i = 0; i < t.length; i++) {
      var ch = t[i]
      w += (ch === ":" || ch === ".") ? thick * 2.6 : digitW + thick * 1.2
    }
    return w + digitHeight * skew
  }

  implicitWidth: Math.ceil(measure(text))
  implicitHeight: Math.ceil(digitHeight)
  width: implicitWidth
  height: implicitHeight

  onTextChanged: requestPaint()
  onColorChanged: requestPaint()
  onDimChanged: requestPaint()
  onWidthChanged: requestPaint()

  readonly property var segs: ({
    "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg",
    "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": "", "A": "abcefg", "E": "adefg",
    "F": "aefg", "H": "bcefg", "L": "def", "P": "abefg", "r": "eg", "o": "cdeg", "U": "bcdef",
    "n": "ceg", "t": "defg", "d": "bcdeg", "b": "cdefg", "C": "adef", "S": "acdfg"
  })

  onPaint: {
    var c = getContext("2d")
    c.reset()
    c.clearRect(0, 0, width, height)
    var h = digitHeight, w = digitW, t = thick, sk = skew, gap = t * 0.18
    var cx = 0
    function seg(on, pts) {
      c.fillStyle = on ? css(s.color) : css(s.dim)
      c.beginPath()
      for (var i = 0; i < pts.length; i++) {
        var X = cx + pts[i][0] + (h - pts[i][1]) * sk, Y = pts[i][1]
        if (i) c.lineTo(X, Y); else c.moveTo(X, Y)
      }
      c.closePath(); c.fill()
    }
    var m = h / 2, hw = t / 2
    function hz(yy) { return [[gap + hw, yy], [gap + t, yy - hw], [w - gap - t, yy - hw], [w - gap - hw, yy], [w - gap - t, yy + hw], [gap + t, yy + hw]] }
    function vt(xx, y0, y1) { return [[xx, y0 + gap + hw], [xx + hw, y0 + gap + t], [xx + hw, y1 - gap - t], [xx, y1 - gap - hw], [xx - hw, y1 - gap - t], [xx - hw, y0 + gap + t]] }
    for (var i = 0; i < text.length; i++) {
      var ch = text[i]
      if (ch === ":" || ch === ".") {
        c.fillStyle = css(s.color)
        if (ch === ":") {
          c.fillRect(cx + t * 0.6 + h * 0.66 * sk, h * 0.28, t, t)
          c.fillRect(cx + t * 0.6 + h * 0.3 * sk, h * 0.64, t, t)
        } else c.fillRect(cx + t * 0.4, h - t, t, t)
        cx += t * 2.6
        continue
      }
      var on = segs[ch] !== undefined ? segs[ch] : ""
      seg(on.indexOf("a") >= 0, hz(hw)); seg(on.indexOf("g") >= 0, hz(m)); seg(on.indexOf("d") >= 0, hz(h - hw))
      seg(on.indexOf("f") >= 0, vt(hw, 0, m)); seg(on.indexOf("b") >= 0, vt(w - hw, 0, m))
      seg(on.indexOf("e") >= 0, vt(hw, m, h)); seg(on.indexOf("c") >= 0, vt(w - hw, m, h))
      cx += w + t * 1.2
    }
  }
}
