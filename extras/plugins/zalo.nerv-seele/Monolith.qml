import QtQuick

// One SEELE member: a tall black slab seen in shallow perspective (outer edge nearer, so taller),
// red member number, SOUND ONLY, the process name running up the face, and a segmented voice
// meter. `level` (0..1) drives the red text, the edge glow and the meter.
//
// Smooth motion without repaints: every Canvas here is painted once per size (glow, slab,
// speaker slab, outline, lit meter, brackets) and all motion is GPU-side: `ls` eases toward each
// new 2 s sample (Behavior/NumberAnimation on the animation driver, vsync-locked), and drives
// only opacities and the meter's clip height. The speaker state cross-fades (`sp`), the
// speaker's edge glow breathes, and a seat change fades the old name out and the new one in.
Item {
  id: m

  property int member: 1
  property real s: 1              // perspective scale
  property real lean: 0           // -1 (left of centre) .. +1 (right); outer edge taller
  property real level: 0
  property string name: ""
  property int pid: 0
  property real cpu: 0
  property bool speaker: false
  property bool live: false
  property bool animate: true

  readonly property real pad: 5    // canvas margin for glow + speaker brackets
  readonly property real taper: Math.abs(lean) * height * 0.07
  readonly property real lt: lean > 0 ? taper : 0
  readonly property real rt: lean < 0 ? taper : 0

  // eased level (0..1)
  property real ls: live ? level : 0
  Behavior on ls { enabled: m.animate; NumberAnimation { duration: 1900; easing.type: Easing.OutCubic } }
  readonly property real ink: 0.38 + 0.62 * ls

  // speaker cross-fade (0..1)
  property real sp: speaker ? 1 : 0
  Behavior on sp { enabled: m.animate; NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }

  // slow breathing on the speaker's edge glow
  property real breath: 1
  SequentialAnimation on breath {
    running: m.speaker && m.animate
    loops: Animation.Infinite
    NumberAnimation { from: 1; to: 0.35; duration: 1500; easing.type: Easing.InOutSine }
    NumberAnimation { from: 0.35; to: 1; duration: 1500; easing.type: Easing.InOutSine }
  }

  // seat change: fade the old name out, swap, fade the new one in
  property string shownName: name
  property bool shownLive: live
  property real nameA: 1
  onPidChanged: {
    if (!m.animate) { shownName = name; shownLive = live; nameA = 1; return }
    swap.restart()
  }
  onNameChanged: if (!swap.running) shownName = name
  onLiveChanged: if (!swap.running) shownLive = live
  SequentialAnimation {
    id: swap
    NumberAnimation { target: m; property: "nameA"; to: 0; duration: 300; easing.type: Easing.InQuad }
    ScriptAction { script: { m.shownName = m.name; m.shownLive = m.live } }
    NumberAnimation { target: m; property: "nameA"; to: 1; duration: 450; easing.type: Easing.OutQuad }
  }

  function body(c, P) {
    var w = m.width, h = m.height
    c.beginPath()
    c.moveTo(P + 0.5, P + m.lt + 0.5); c.lineTo(P + w - 0.5, P + m.rt + 0.5)
    c.lineTo(P + w - 0.5, P + h - m.rt - 0.5); c.lineTo(P + 0.5, P + h - m.lt - 0.5)
    c.closePath()
  }
  // meter geometry (slab coords)
  readonly property real mx: 2.5
  readonly property real mw: Math.max(3, width - 15)
  readonly property real my1: height - Math.max(lt, rt) - 5
  readonly property real mh: height * 0.40
  function segs(c, P, lit) {
    var n = 10, sh = (m.mh - (n - 1)) / n
    for (var i = 0; i < n; i++) {
      c.fillStyle = lit ? (i >= 8 ? "#FF1A1A" : "rgba(255,26,26,0.8)") : "rgba(106,0,0,0.45)"
      c.fillRect(P + m.mx, P + m.my1 - (i + 1) * sh - i, m.mw, sh)
    }
  }

  // --- edge glow: painted at full strength, shown by opacity
  readonly property real glowMax: 0.18 * 2.3
  Canvas {
    id: glow
    x: -m.pad; y: -m.pad
    width: m.width + m.pad * 2; height: m.height + m.pad * 2
    opacity: (0.05 + 0.13 * m.ls) * (1 + m.sp * (0.5 + 0.8 * m.breath)) / m.glowMax
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      m.body(c, m.pad)
      for (var g = 3; g >= 1; g--) {
        c.lineWidth = 1 + g * 1.6
        c.strokeStyle = "rgba(255,26,26," + m.glowMax / g + ")"
        c.stroke()
      }
    }
  }

  // --- slab (normal) and slab (speaker, dark red) with the unlit meter; cross-faded
  Canvas {
    id: slab
    x: -m.pad; y: -m.pad
    width: glow.width; height: glow.height
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      m.body(c, m.pad)
      c.fillStyle = "rgba(4,2,2,0.97)"
      c.fill()
      m.segs(c, m.pad, false)
    }
  }
  Canvas {
    id: slabHot
    x: -m.pad; y: -m.pad
    width: glow.width; height: glow.height
    opacity: m.sp
    visible: opacity > 0.001
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      m.body(c, m.pad)
      c.fillStyle = "rgb(40,0,0)"
      c.fill()
      m.segs(c, m.pad, false)
    }
  }

  // --- outline
  Canvas {
    id: outline
    x: -m.pad; y: -m.pad
    width: glow.width; height: glow.height
    opacity: (0.25 + 0.65 * m.ls) * (1 - m.sp) + m.sp
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      m.body(c, m.pad)
      c.lineWidth = 1
      c.strokeStyle = "#FF1A1A"
      c.stroke()
    }
  }

  // number rule
  Rectangle {
    x: 3; y: m.lt * 0.5 + m.height * 0.255
    width: m.width - 6; height: 1
    color: "#FF1A1A"
    opacity: 0.3 + 0.6 * m.ls
  }

  // --- lit meter: pre-painted, revealed bottom-up by a clip whose height eases with ls
  Item {
    id: meterClip
    x: 0; width: m.width
    readonly property real full: m.mh + 1
    height: full * m.ls
    y: m.my1 - height
    clip: true
    opacity: 0.7 + 0.3 * m.ls
    Canvas {
      x: -m.pad
      y: -m.pad - meterClip.y
      width: glow.width; height: glow.height
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var c = getContext("2d")
        c.reset()
        m.segs(c, m.pad, true)
      }
    }
  }

  // --- speaker brackets outside the slab
  Canvas {
    x: -m.pad; y: -m.pad
    width: glow.width; height: glow.height
    opacity: m.sp
    visible: opacity > 0.001
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      c.strokeStyle = "#FF1A1A"
      c.lineWidth = 1
      var k = 4, x0 = 0.5, y0 = 0.5, x1 = width - 0.5, y1 = height - 0.5
      c.beginPath()
      c.moveTo(x0, y0 + k); c.lineTo(x0, y0); c.lineTo(x0 + k, y0)
      c.moveTo(x1 - k, y0); c.lineTo(x1, y0); c.lineTo(x1, y0 + k)
      c.moveTo(x1, y1 - k); c.lineTo(x1, y1); c.lineTo(x1 - k, y1)
      c.moveTo(x0 + k, y1); c.lineTo(x0, y1); c.lineTo(x0, y1 - k)
      c.stroke()
    }
  }

  // member number (condensed serif)
  Text {
    id: num
    anchors.horizontalCenter: parent.horizontalCenter
    y: m.height * 0.035 + (m.lean !== 0 ? m.taper * 0.5 : 0)
    text: (m.member < 10 ? "0" : "") + m.member
    color: "#FF1A1A"
    opacity: m.ink + (1 - m.ink) * m.sp
    font.family: "Cormorant Garamond"
    font.weight: Font.Bold
    font.pixelSize: Math.round(19 * m.s)
    transform: Scale { origin.x: num.width / 2; xScale: 0.78 }
  }

  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    y: m.height * 0.27 + 1
    spacing: -1
    opacity: m.ink * 0.9 + (1 - m.ink * 0.9) * m.sp
    Repeater {
      model: ["SOUND", "ONLY"]
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: modelData
        color: "#FF1A1A"
        font.family: "IBM Plex Mono"
        font.weight: Font.Bold
        font.pixelSize: 5
        font.letterSpacing: 0.2
      }
    }
  }

  // process name, running up the face beside the meter (red, cross-faded to bone for the speaker)
  Item {
    id: nmBox
    readonly property real run: m.height * 0.56
    width: run
    height: nmRed.implicitHeight
    x: m.width - 3 - height / 2 - run / 2
    y: m.height - 5 - Math.abs(m.taper) - run / 2 - height / 2
    rotation: -90
    opacity: m.nameA
    readonly property string label: m.shownLive ? m.shownName.toUpperCase() : "— VACANT —"
    Text {
      id: nmRed
      width: parent.width
      text: nmBox.label
      elide: Text.ElideRight
      color: "#FF1A1A"
      opacity: (0.3 + 0.7 * m.ls) * (1 - m.sp)
      visible: opacity > 0.001
      font.family: "IBM Plex Mono"
      font.weight: Font.DemiBold
      font.pixelSize: 6
      font.letterSpacing: 0.6
    }
    Text {
      width: parent.width
      text: nmBox.label
      elide: Text.ElideRight
      color: "#FFE9C8"
      opacity: 0.95 * m.sp
      visible: opacity > 0.001
      font: nmRed.font
    }
  }

  // live reading under the slab (the floor): digits tick per sample (stepped), brightness eases
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: m.height + 3
    text: m.live ? (m.cpu >= 100 ? Math.round(m.cpu) : m.cpu.toFixed(1)) : "--"
    color: "#FF1A1A"
    opacity: ((0.35 + 0.5 * m.ls) * (1 - m.sp) + m.sp) * m.nameA
    font.family: "IBM Plex Mono"
    font.weight: Font.Bold
    font.pixelSize: 6
  }
}
