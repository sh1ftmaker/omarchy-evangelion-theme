import QtQuick

// TACTICAL / 使徒接近 — top-down radar of live TCP contacts.
// Bearing = hash(remote address), range = RTT (log scale), echo size = log(bytes).
// The busiest remote host is the Angel (PATTERN BLUE); the rest are orange UN blips
// that light as the beam passes. The static scope is painted once; the sweep is a
// pre-rendered phosphor wedge that is only rotated (vsync, time-based); contacts are
// persistent delegates keyed by ip that glide to new ranges.
Item {
  id: radar

  required property var hud

  // sized by the parent (the wall rect); everything below derives from width/height
  width: 360
  height: 398

  // scope area: between the top readouts and the Angel box; the scope keeps a 26 px
  // bezel/label margin and is centred in that area.
  readonly property real areaTop: 29
  readonly property real areaBottom: targetBox.y - 3
  readonly property real cx: Math.round(width / 2)
  readonly property real cy: Math.round((areaTop + areaBottom) / 2)
  readonly property real rs: Math.max(40, Math.floor(Math.min(width / 2 - 34, (areaBottom - areaTop) / 2) - 26))   // scope radius
  readonly property var ringsMs: [5, 20, 60, 200]
  readonly property color cOrange: "#FF7A00"
  readonly property color cAmber: "#FFB000"
  readonly property color cCyan: "#00C8FF"
  readonly property color cRed: "#FF1A1A"
  readonly property color cBone: "#FFE9C8"
  readonly property color cInk: "#050403"

  function rn(rtt) {
    var v = Math.log(1 + Math.max(0, rtt)) / Math.log(1 + 400)
    return 0.07 + 0.9 * Math.max(0, Math.min(1, v))
  }
  function fmtRate(bps) {
    if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/S"
    if (bps >= 1024) return (bps / 1024).toFixed(1) + " KB/S"
    return Math.round(bps) + " B/S"
  }
  function pad3(v) { var s = String(Math.round(v)); while (s.length < 3) s = "0" + s; return s }
  function brgText(b) { var s = b.toFixed(1); while (s.length < 5) s = "0" + s; return s }

  // ---------------------------------------------------------------- static layer
  // Everything that does not move per frame is flattened into one texture (re-rendered only
  // when something inside changes: a sample, a blink), so the 60 Hz frames only draw that
  // texture plus the moving parts above it.
  Item {
    id: still
    anchors.fill: parent
    layer.enabled: true

    NervPanel {
      anchors.fill: parent
      title: "TACTICAL"
      jp: "使徒接近 戦術状況"
      fill: radar.hud.panelFill
      cut: 14
      header: 14
    }

    // ---------------------------------------------------------------- static scope
    Canvas {
      id: scope
      readonly property real half: radar.rs + 26
      x: radar.cx - half
      y: radar.cy - half
      width: half * 2
      height: half * 2
      Component.onCompleted: requestPaint()
      onHalfChanged: requestPaint()
      onPaint: {
        var c = getContext("2d")
        c.reset()
        c.clearRect(0, 0, width, height)
        var C = half, R = radar.rs, TAU = Math.PI * 2
        // scope disk
        c.beginPath(); c.arc(C, C, R, 0, TAU); c.fillStyle = "rgba(3,2,1,0.72)"; c.fill()
        // fine phosphor grid clipped to the scope
        c.save()
        c.beginPath(); c.arc(C, C, R, 0, TAU); c.clip()
        c.fillStyle = "rgba(255,122,0,0.07)"
        for (var gx = C % 12; gx < 2 * C; gx += 12) c.fillRect(Math.round(gx), 0, 1, 2 * C)
        for (var gy = C % 12; gy < 2 * C; gy += 12) c.fillRect(0, Math.round(gy), 2 * C, 1)
        // inner zone (LAN, < 5 ms) hatched
        c.fillStyle = "rgba(255,122,0,0.05)"
        c.beginPath(); c.arc(C, C, R * radar.rn(radar.ringsMs[0]), 0, TAU); c.fill()
        c.restore()
        // radials
        for (var i = 0; i < 12; i++) {
          var b = i * 30 * Math.PI / 180, card = i % 3 === 0
          c.strokeStyle = card ? "rgba(255,122,0,0.42)" : "rgba(255,122,0,0.17)"
          c.lineWidth = 1
          c.beginPath()
          c.moveTo(C + Math.sin(b) * 8, C - Math.cos(b) * 8)
          c.lineTo(C + Math.sin(b) * R, C - Math.cos(b) * R)
          c.stroke()
        }
        // range rings (RTT)
        for (var k = 0; k < radar.ringsMs.length; k++) {
          var rr = R * radar.rn(radar.ringsMs[k])
          c.strokeStyle = k === 1 ? "rgba(255,122,0,0.55)" : "rgba(255,122,0,0.34)"
          c.lineWidth = 1
          if (k === 1) c.setLineDash ? c.setLineDash([3, 3]) : 0
          c.beginPath(); c.arc(C, C, rr, 0, TAU); c.stroke()
          if (c.setLineDash) c.setLineDash([])
        }
        c.strokeStyle = "#FF7A00"; c.lineWidth = 1.6
        c.beginPath(); c.arc(C, C, R, 0, TAU); c.stroke()
        c.lineWidth = 1
        c.beginPath(); c.arc(C, C, R + 3, 0, TAU); c.stroke()
        // bezel ticks
        for (var d = 0; d < 360; d += 5) {
          var bb = d * Math.PI / 180, l = d % 30 === 0 ? 8 : d % 10 === 0 ? 5 : 3
          c.strokeStyle = d % 30 === 0 ? "#FFB000" : "rgba(255,122,0,0.8)"
          c.beginPath()
          c.moveTo(C + Math.sin(bb) * (R + 3), C - Math.cos(bb) * (R + 3))
          c.lineTo(C + Math.sin(bb) * (R + 3 + l), C - Math.cos(bb) * (R + 3 + l))
          c.stroke()
        }
        // bearing labels
        c.textAlign = "center"; c.textBaseline = "middle"
        var kanji = { 0: "北", 90: "東", 180: "南", 270: "西" }
        for (var a = 0; a < 360; a += 30) {
          var ab = a * Math.PI / 180, px = C + Math.sin(ab) * (R + 18), py = C - Math.cos(ab) * (R + 18)
          if (kanji[a] !== undefined) {
            c.font = "bold 9px 'Noto Sans CJK JP'"; c.fillStyle = "#FFB000"
            c.fillText(kanji[a], px, py)
          } else {
            c.font = "bold 7px 'IBM Plex Mono'"; c.fillStyle = "rgba(255,122,0,0.9)"
            c.fillText(radar.pad3(a), px, py)
          }
        }
        // ring labels along bearing 348°
        c.font = "bold 6px 'IBM Plex Mono'"; c.fillStyle = "rgba(255,176,0,0.8)"; c.textAlign = "left"
        var lb = -14 * Math.PI / 180
        for (var q = 0; q < radar.ringsMs.length; q++) {
          var r2 = R * radar.rn(radar.ringsMs[q])
          c.fillText(radar.ringsMs[q] + (q === radar.ringsMs.length - 1 ? "MS" : ""), C + Math.sin(lb) * r2 + 2, C - Math.cos(lb) * r2 + 5)
        }
        // NERV HQ marker
        c.strokeStyle = "#FFB000"; c.lineWidth = 1.2
        c.beginPath(); c.moveTo(C, C - 5); c.lineTo(C + 5, C); c.lineTo(C, C + 5); c.lineTo(C - 5, C); c.closePath(); c.stroke()
        c.strokeStyle = "rgba(255,122,0,0.6)"; c.lineWidth = 1
        c.beginPath()
        for (var h = 0; h <= 6; h++) { var ha = Math.PI / 6 + h * TAU / 6; var hx = C + Math.cos(ha) * 10, hy = C + Math.sin(ha) * 10; if (h) c.lineTo(hx, hy); else c.moveTo(hx, hy) }
        c.stroke()
        c.font = "bold 6px 'IBM Plex Mono'"; c.fillStyle = "rgba(255,122,0,0.85)"; c.textAlign = "left"
        c.fillText("NERV HQ", C + 9, C + 14)
        c.font = "bold 7px 'Noto Sans CJK JP'"
        c.fillText("本部", C + 9, C + 22)
      }
    }

    // ---------------------------------------------------------------- corner readouts
    // top-left: contact count
    Column {
      x: 9; y: 21; spacing: 2
      Row {
        spacing: 4
        Mono { text: "CONTACTS"; font.pixelSize: 7 }
        Jp { text: "探知目標"; font.pixelSize: 7 }
      }
      SevenSeg { text: radar.pad3(radar.hud.total); digitHeight: 17; color: radar.cAmber }
      Mono { text: "HOSTS " + radar.hud.hosts + "  TCP/EST"; font.pixelSize: 7; opacity: 0.8 }
    }


    // bottom-left: interface
    Column {
      x: 9; y: targetBox.y - 58; spacing: 1
      Row { spacing: 4; Mono { text: "LINK"; font.pixelSize: 7 } Jp { text: "回線"; font.pixelSize: 7 } }
      Mono { text: (radar.hud.iface || "OFFLINE").toUpperCase(); color: radar.cAmber; font.pixelSize: 8; font.weight: Font.Bold }
      Mono {
        width: 90; elide: Text.ElideRight
        text: radar.hud.ssid ? "SSID " + radar.hud.ssid : "WIRED"
        font.pixelSize: 7; opacity: 0.85
      }
    }


  }

  // ---------------------------------------------------------------- sweep (pre-rendered, rotated)
  Canvas {
    id: sweep
    readonly property real half: radar.rs + 16
    x: radar.cx - half
    y: radar.cy - half
    width: half * 2
    height: half * 2
    rotation: radar.hud.sweepDeg
    antialiasing: true
    smooth: true
    Component.onCompleted: requestPaint()
    onHalfChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.reset()
      c.clearRect(0, 0, width, height)
      var C = half, R = radar.rs, D = Math.PI / 180
      // phosphor afterglow: 0.5° slices fading counter-clockwise behind the beam (north = beam).
      // Painted once; the per-frame cost is only the item's rotation.
      var N = 300, st = 0.5 * D
      for (var i = 0; i < N; i++) {
        var deg = i * 0.5
        var al = 0.34 * Math.exp(-deg / 26) + 0.05 * Math.exp(-deg / 90)
        var a0 = -Math.PI / 2 - (i + 1) * st, a1 = -Math.PI / 2 - i * st + 0.003
        c.beginPath(); c.moveTo(C, C); c.arc(C, C, R - 1, a0, a1); c.closePath()
        c.fillStyle = "rgba(255," + Math.round(122 + 60 * Math.exp(-deg / 5)) + "," + Math.round(40 * Math.exp(-deg / 3)) + "," + al.toFixed(4) + ")"
        c.fill()
      }
      // phosphor rim: the trail re-lights the scope ring just behind the beam
      c.lineWidth = 2
      for (var j = 0; j < 60; j++) {
        c.strokeStyle = "rgba(255,176,0," + (0.7 * Math.exp(-j / 12)).toFixed(4) + ")"
        c.beginPath(); c.arc(C, C, R, -Math.PI / 2 - (j + 1) * D, -Math.PI / 2 - j * D + 0.003); c.stroke()
      }
      // beam
      c.strokeStyle = "rgba(255,176,0,0.35)"; c.lineWidth = 5
      c.beginPath(); c.moveTo(C, C); c.lineTo(C, C - R); c.stroke()
      c.strokeStyle = "#FFE9C8"; c.lineWidth = 1.4
      c.beginPath(); c.moveTo(C, C); c.lineTo(C, C - R - 12); c.stroke()
      // bezel marker (chevron outside the ring)
      c.fillStyle = "#FFB000"
      c.beginPath(); c.moveTo(C, C - R - 5); c.lineTo(C - 4, C - R - 13); c.lineTo(C + 4, C - R - 13); c.closePath(); c.fill()
    }
  }

  // ---------------------------------------------------------------- angel bearing line
  Item {
    id: angelLine
    readonly property var a: radar.hud.angel
    property real len: a ? Math.max(0, radar.rn(a.rtt) * radar.rs - 12) : 0
    Behavior on len { enabled: radar.hud.animating; NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
    Behavior on rotation { enabled: radar.hud.animating; RotationAnimation { duration: 450; direction: RotationAnimation.Shortest; easing.type: Easing.OutCubic } }
    visible: a !== null
    x: radar.cx
    y: radar.cy
    width: 1
    height: 1
    rotation: a ? a.brg : 0
    Item {
      x: -0.5
      y: -height
      width: 1
      height: angelLine.len
      clip: true
      Column {
        anchors.bottom: parent.bottom
        spacing: 3
        Repeater {
          model: Math.ceil(radar.rs / 6)
          Rectangle { width: 1; height: 3; color: radar.cCyan; opacity: 0.55 }
        }
      }
    }
  }

  // ---------------------------------------------------------------- contacts
  // Each contact is drawn three times into scope-sized containers: a dim echo (plain items),
  // a full-brightness echo + label (`litItems`) and a strike halo (`flashItems`). The last two
  // are textures that one ShaderEffect gates by the angle between each pixel's bearing and the
  // beam, so every blip brightens as the beam crosses it and fades continuously, with zero
  // per-blip work per frame. Positions only change when a sample arrives (then they glide).
  readonly property real scopeHalf: rs + 34
  Item {
    id: dimItems
    x: radar.cx - radar.scopeHalf; y: radar.cy - radar.scopeHalf
    width: radar.scopeHalf * 2; height: width
  }
  Item {
    id: litItems
    x: dimItems.x; y: dimItems.y; width: dimItems.width; height: dimItems.height
    visible: false
  }
  Item {
    id: flashItems
    x: dimItems.x; y: dimItems.y; width: dimItems.width; height: dimItems.height
    visible: false
  }
  ShaderEffect {
    x: dimItems.x; y: dimItems.y; width: dimItems.width; height: dimItems.height
    readonly property real sweep: radar.hud.sweepDeg * Math.PI / 180
    readonly property real decay: 3.4
    readonly property real flashDecay: 9
    property variant lit: ShaderEffectSource { sourceItem: litItems; hideSource: true; smooth: true }
    property variant flash: ShaderEffectSource { sourceItem: flashItems; hideSource: true; smooth: true }
    fragmentShader: Qt.resolvedUrl("blipglow.frag.qsb")
  }

  Repeater {
    model: radar.hud.contacts
    delegate: Item {
      id: blip
      required property string ip
      required property string port
      required property real brg
      required property real rtt
      required property real bytes
      required property bool alive
      readonly property bool angel: radar.hud.angel !== null && radar.hud.angel.ip === ip
      readonly property real b: brg * Math.PI / 180
      // range + echo size glide to each new sample (Behaviors run only while animating)
      property real r: radar.rn(rtt) * radar.rs
      property real sz: 3 + 4 * Math.min(1, Math.log(1 + bytes) / Math.log(1e8))
      Behavior on r { enabled: radar.hud.animating; NumberAnimation { duration: 1200; easing.type: Easing.InOutCubic } }
      Behavior on sz { enabled: radar.hud.animating; NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
      readonly property bool local: /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.|::1$|fe80|fd)/.test(ip)
      // fade in on first contact, fade out when lost
      property real presence: alive ? 1 : 0
      Behavior on presence { enabled: radar.hud.animating; NumberAnimation { duration: 700 } }
      // position inside the scope-sized containers
      readonly property real px: radar.scopeHalf + Math.sin(b) * r
      readonly property real py: radar.scopeHalf - Math.cos(b) * r
      readonly property real side: sz * 1.6

      // dim echo (always visible)
      Rectangle {
        parent: dimItems
        visible: !blip.angel
        x: blip.px - width / 2; y: blip.py - height / 2
        width: blip.side; height: width
        rotation: blip.local ? 0 : 45
        radius: blip.local ? width / 2 : 0
        color: Qt.rgba(1, 0.48, 0, 0.12)
        border.color: radar.cOrange; border.width: 1
        opacity: 0.4 * blip.presence
      }
      // beam-lit echo + callsign (gated by the shader)
      Item {
        parent: litItems
        visible: !blip.angel
        x: blip.px; y: blip.py
        opacity: blip.presence
        Rectangle {
          x: -width / 2; y: -height / 2
          width: blip.side; height: width
          rotation: blip.local ? 0 : 45
          radius: blip.local ? width / 2 : 0
          color: Qt.rgba(1, 0.68, 0, 0.87)
          border.color: radar.cBone; border.width: 1
        }
        Mono {
          x: blip.brg < 180 ? 6 : -width - 6
          y: -12
          text: "UN-" + (Math.round(blip.brg * 7) % 97 + 1) + " :" + blip.port
          font.pixelSize: 7
          font.letterSpacing: 0.6
          color: radar.cAmber
        }
      }
      // beam-strike halo (gated by the shader, fades fast)
      Item {
        parent: flashItems
        visible: !blip.angel
        x: blip.px; y: blip.py
        opacity: blip.presence
        Rectangle {
          x: -width / 2; y: -height / 2
          width: blip.side + 9; height: width
          rotation: blip.local ? 0 : 45
          radius: blip.local ? width / 2 : 0
          color: Qt.rgba(1, 0.69, 0, 0.18)
          border.color: radar.cBone; border.width: 1
        }
        Rectangle {
          x: -width / 2; y: -height / 2
          width: blip.side + 20; height: width
          rotation: blip.local ? 0 : 45
          radius: blip.local ? width / 2 : 0
          color: "transparent"
          border.color: radar.cAmber; border.width: 0.6
          opacity: 0.6
        }
      }
      // the Angel: one contact, drawn directly (its ping ring expands as the beam passes)
      Loader {
        parent: dimItems
        active: blip.angel
        x: blip.px; y: blip.py
        z: 5
        opacity: blip.presence
        sourceComponent: angelEcho
      }

      Component {
        id: angelEcho
        Item {
          readonly property real glow: Math.exp(-((((radar.hud.sweepDeg - blip.brg) % 360) + 360) % 360) / 360 * 3.4)
          // ping ring when the beam passes
          Rectangle {
            anchors.centerIn: parent
            width: 14; height: width; radius: width / 2
            color: "transparent"
            border.color: radar.cCyan; border.width: 0.6
            scale: 1 + 2.4 * (1 - parent.glow)
            opacity: parent.glow * 0.9
          }
          Rectangle {
            anchors.centerIn: parent
            width: 11; height: 11; rotation: 45
            color: Qt.rgba(0, 0.78, 1, 0.15)
            border.color: radar.cCyan; border.width: 1.4
          }
          Rectangle {
            anchors.centerIn: parent
            width: 11; height: 11; rotation: 45
            color: Qt.rgba(0, 0.78, 1, 0.5)
            border.color: "#E8FAFF"; border.width: 1.4
            opacity: parent.glow
          }
          Rectangle {
            anchors.centerIn: parent
            width: 4; height: 4; rotation: 45; color: radar.cCyan
          }
          // target brackets
          Repeater {
            model: 4
            Item {
              required property int index
              x: (index % 2 ? 9 : -9); y: (index < 2 ? -9 : 9)
              Rectangle { x: index % 2 ? -5 : 0; y: index < 2 ? 0 : -1; width: 5; height: 1; color: radar.cCyan }
              Rectangle { x: index % 2 ? -1 : 0; y: index < 2 ? 0 : -5; width: 1; height: 5; color: radar.cCyan }
            }
          }
          Text {
            x: blip.brg < 180 ? -width - 12 : 12
            y: -16
            text: "使徒"
            color: radar.cCyan
            font.family: "Noto Sans CJK JP"; font.weight: Font.Black; font.pixelSize: 9
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- live readouts (eased / 15 Hz, outside the static layer)
  // top-right: link rates
  Column {
    layer.enabled: true
    x: radar.width - 9 - 92; y: 21; width: 92; spacing: 2
    Row {
      anchors.right: parent.right; spacing: 4
      Jp { text: "受信"; font.pixelSize: 7 }
      Mono { text: "RX"; font.pixelSize: 7 }
    }
    Mono { anchors.right: parent.right; text: radar.fmtRate(radar.hud.rxS); color: radar.cAmber; font.pixelSize: 9; font.weight: Font.Bold }
    SegMeter { width: 92; height: 4; segments: 18; value: Math.log(1 + radar.hud.rxS) / Math.log(1 + 12e6); hotFrom: 0.85 }
    Row {
      anchors.right: parent.right; spacing: 4
      Jp { text: "送信"; font.pixelSize: 7 }
      Mono { text: "TX"; font.pixelSize: 7 }
    }
    Mono { anchors.right: parent.right; text: radar.fmtRate(radar.hud.txS); color: radar.cAmber; font.pixelSize: 9; font.weight: Font.Bold }
    SegMeter { width: 92; height: 4; segments: 18; value: Math.log(1 + radar.hud.txS) / Math.log(1 + 12e6); hotFrom: 0.85 }
  }


  // bottom-right: sweep
  Column {
    x: radar.width - 9 - 92; y: targetBox.y - 58; width: 92; spacing: 1
    Row { anchors.right: parent.right; spacing: 4; Jp { text: "掃引"; font.pixelSize: 7 } Mono { text: "SWEEP"; font.pixelSize: 7 } }
    Mono { anchors.right: parent.right; text: radar.brgText(radar.hud.sweepReadout) + "°"; color: radar.cAmber; font.pixelSize: 8; font.weight: Font.Bold }
    Mono { anchors.right: parent.right; text: "1 REV/BAR 133 BPM"; font.pixelSize: 7; opacity: 0.85 }
    Mono { anchors.right: parent.right; text: "RANGE = RTT (LOG)"; font.pixelSize: 7; opacity: 0.6 }
  }

  // targetBox carries the eased Angel rate, so it has its own layer (not the big static one)
  // ---------------------------------------------------------------- the Angel's analysis box
  NervPanel {
    id: targetBox
    layer.enabled: true
    readonly property var a: radar.hud.angel
    x: 8; y: radar.height - 66; width: radar.width - 16; height: 58
    accent: a ? radar.cCyan : "#9C6A2E"
    fill: Qt.rgba(0, 0.03, 0.05, 0.78)
    title: a ? "PATTERN BLUE" : "NO CONTACT"
    jp: a ? "目標 使徒" : "目標なし"
    cut: 9
    header: 13
    alarm: a !== null && radar.hud.angelHot && radar.hud.blinkOn

    Column {
      visible: targetBox.a !== null
      width: parent.width
      spacing: 2
      Item {
        width: parent.width; height: 11
        Mono {
          width: parent.width - 110; elide: Text.ElideRight
          text: targetBox.a ? targetBox.a.ip + " :" + targetBox.a.port : ""
          color: radar.cCyan; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 0.6
        }
        Mono {
          anchors.right: parent.right
          text: "BLOOD TYPE: BLUE"
          color: radar.cCyan; font.pixelSize: 8; font.weight: Font.Bold
          opacity: radar.hud.blinkOn ? 1 : 0.55
        }
      }
      Item {
        width: parent.width; height: 10
        Mono {
          text: targetBox.a ? "BRG " + radar.brgText(targetBox.a.brg) + "  RTT " + targetBox.a.rtt.toFixed(1) + "MS  LINKS " + targetBox.a.n : ""
          color: radar.cCyan; font.pixelSize: 7; opacity: 0.9; font.letterSpacing: 0.8
        }
        Mono {
          anchors.right: parent.right
          text: targetBox.a ? radar.fmtRate(radar.hud.angelRateS) : ""
          color: "#E8FAFF"; font.pixelSize: 8; font.weight: Font.Bold
        }
      }
      SegMeter {
        width: parent.width; height: 4; segments: 40
        value: targetBox.a ? Math.log(1 + radar.hud.angelRateS) / Math.log(1 + 5e6) : 0
        color: radar.cCyan; hot: radar.cRed; hotFrom: 0.8
        dim: Qt.rgba(0, 0.78, 1, 0.12)
      }
    }
    Mono {
      visible: targetBox.a === null
      text: "ALL QUIET  //  AWAITING CONTACT  解析中"
      color: "#9C6A2E"; font.pixelSize: 8
    }
  }
}
