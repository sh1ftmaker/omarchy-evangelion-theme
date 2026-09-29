import QtQuick

// The speaker's voice print: a live oscilloscope whose envelope is the member's CPU history
// (oldest left, newest right) over a faint graticule. The history (sampled every ~2 s) is
// written into a 64x1 envelope texture only when it changes; the trace itself is synthesised
// per pixel on the GPU (shaders/voice.frag) from `time`, so it animates at display rate with
// no Canvas repaint. `prog` (0..1, time since the last sample / sample interval) slides the
// envelope one slot left between samples so the newest reading scrolls in from the right.
// Rebuild the shader after editing voice.frag:
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o voice.frag.qsb voice.frag
Item {
  id: v
  property var hist: []
  property real time: 0
  property real prog: 1

  // graticule (painted on resize only)
  Canvas {
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var g = getContext("2d")
      g.reset()
      var W = width, H = height, mid = H / 2
      g.fillStyle = "rgba(106,0,0,0.5)"
      for (var gx = 0; gx <= W; gx += W / 8) g.fillRect(Math.round(gx), 0, 1, H)
      g.fillRect(0, Math.round(mid), W, 1)
      g.fillStyle = "rgba(255,26,26,0.35)"
      g.fillRect(0, 0, 3, 1); g.fillRect(0, H - 1, 3, 1); g.fillRect(W - 3, 0, 3, 1); g.fillRect(W - 3, H - 1, 3, 1)
    }
  }

  // envelope texture: texel 63 = newest sample, red = sqrt(cpu/100)
  Canvas {
    id: envCanvas
    width: 64; height: 1
    canvasSize: Qt.size(64, 1)
    onPaint: {
      var g = getContext("2d")
      g.reset()
      g.fillStyle = "#000000"
      g.fillRect(0, 0, 64, 1)
      var h = v.hist, n = h.length
      for (var j = 0; j < n && j < 64; j++) {
        var e = Math.max(0, Math.min(1, Math.sqrt(Math.max(0, h[n - 1 - j]) / 100)))
        g.fillStyle = Qt.rgba(e, 0, 0, 1)
        g.fillRect(63 - j, 0, 1, 1)
      }
    }
  }
  onHistChanged: envCanvas.requestPaint()

  ShaderEffectSource {
    id: envTex
    sourceItem: envCanvas
    hideSource: true
    textureSize: Qt.size(64, 1)
    smooth: true
    width: 0; height: 0
  }

  ShaderEffect {
    anchors.fill: parent
    property variant env: envTex
    property real time: v.time
    property real prog: v.prog
    property real w: width
    property real h: height
    fragmentShader: Qt.resolvedUrl("shaders/voice.frag.qsb")
  }
}
