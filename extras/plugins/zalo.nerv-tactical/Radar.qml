import QtQuick

// TACTICAL / 使徒接近 — top-down radar of nearby Wi-Fi networks.
// Bearing = hash(BSSID), range = signal strength (strong = near the centre), echo size and
// brightness = signal; diamonds are secured networks, circles open ones. The associated
// network is the Angel (PATTERN BLUE); the rest are orange blips that light as the beam
// passes. The static scope is painted once; the sweep is a pre-rendered phosphor wedge that
// is only rotated (vsync, time-based); contacts are persistent delegates keyed by BSSID that
// glide to new ranges.
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
  readonly property var ringsDbm: [-50, -60, -70, -80]
  readonly property color cOrange: "#FF7A00"
  readonly property color cAmber: "#FFB000"
  readonly property color cCyan: "#00C8FF"
  readonly property color cRed: "#FF1A1A"
  readonly property color cBone: "#FFE9C8"
  readonly property color cInk: "#050403"

  // signal quality (NetworkManager %, 0..100) -> normalised range (a gamma spreads the strong
  // end, where most real networks sit); dBm rings use NM's own dBm -> % mapping
  function rn(sig) { return 0.07 + 0.9 * Math.pow(1 - Math.max(0, Math.min(100, sig)) / 100, 0.6) }
  readonly property int labelTop: 10      // only the strongest N blips carry a callsign
  function dbmPct(d) { return radar.hud.dbmPct(d) }
  function mmss(s) { var m = Math.floor(s / 60), r = s % 60; return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r }
  function ago(s) {
    if (s < 0) return "SCAN PENDING"
    if (s < 60) return "SCAN " + s + "S AGO"
    if (s < 5400) return "SCAN " + Math.floor(s / 60) + "M AGO"
    return "SCAN " + Math.floor(s / 3600) + "H AGO"
  }
  function netName(s) { return s ? s.toUpperCase() : "〈HIDDEN〉" }
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
        // inner zone (excellent signal, > -50 dBm) hatched
        c.fillStyle = "rgba(255,122,0,0.05)"
        c.beginPath(); c.arc(C, C, R * radar.rn(radar.dbmPct(radar.ringsDbm[0])), 0, TAU); c.fill()
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
        // range rings (signal, dBm)
        for (var k = 0; k < radar.ringsDbm.length; k++) {
          var rr = R * radar.rn(radar.dbmPct(radar.ringsDbm[k]))
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
        for (var q = 0; q < radar.ringsDbm.length; q++) {
          var r2 = R * radar.rn(radar.dbmPct(radar.ringsDbm[q]))
          c.fillText(radar.ringsDbm[q] + (q === radar.ringsDbm.length - 1 ? "DBM" : ""), C + Math.sin(lb) * r2 + 2, C - Math.cos(lb) * r2 + 5)
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
    // top-left: networks detected
    Column {
      x: 9; y: 21; spacing: 2
      Row {
        spacing: 4
        Mono { text: "NETWORKS"; font.pixelSize: 7 }
        Jp { text: "探知目標"; font.pixelSize: 7 }
      }
      SevenSeg { text: radar.pad3(radar.hud.netCount); digitHeight: 17; color: radar.cAmber }
      Mono { text: "SSID " + radar.hud.ssidCount + "  OPEN " + radar.hud.openCount; font.pixelSize: 7; opacity: 0.8 }
    }


    // bottom-left: interface
    Column {
      x: 9; y: targetBox.y - 58; spacing: 1
      Row { spacing: 4; Mono { text: "LINK"; font.pixelSize: 7 } Jp { text: "回線"; font.pixelSize: 7 } }
      Mono { text: (radar.hud.iface || "OFFLINE").toUpperCase(); color: radar.cAmber; font.pixelSize: 8; font.weight: Font.Bold }
      Mono {
        width: 90; elide: Text.ElideRight
        text: radar.hud.angel ? radar.hud.angel.band + " CH" + radar.hud.angel.ch + " " + radar.hud.angel.sec
            : radar.hud.wifiDev ? "WIFI IDLE" : "NO WIFI"
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
    property real len: a ? Math.max(0, radar.rn(a.sig) * radar.rs - 12) : 0
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
      required property string nid
      required property string ssid
      required property string sec
      required property string band
      required property int ch
      required property real sig
      required property real brg
      required property bool alive
      required property int rank
      readonly property bool labelled: rank < radar.labelTop
      readonly property bool angel: radar.hud.angel !== null && radar.hud.angel.id === nid
      readonly property real b: brg * Math.PI / 180
      // range + echo size + brightness glide to each new sample (Behaviors run only while animating)
      property real q: Math.max(0, Math.min(1, sig / 100))
      Behavior on q { enabled: radar.hud.animating; NumberAnimation { duration: 1200; easing.type: Easing.InOutCubic } }
      readonly property real r: radar.rn(q * 100) * radar.rs
      readonly property real sz: 2.4 + 4.6 * q
      // open networks are round echoes, secured ones diamonds
      readonly property bool local: sec === "OPEN"
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
        opacity: (0.22 + 0.3 * blip.q) * blip.presence
      }
      // beam-lit echo + callsign (gated by the shader)
      Item {
        parent: litItems
        visible: !blip.angel
        x: blip.px; y: blip.py
        opacity: (0.45 + 0.55 * blip.q) * blip.presence
        Rectangle {
          x: -width / 2; y: -height / 2
          width: blip.side; height: width
          rotation: blip.local ? 0 : 45
          radius: blip.local ? width / 2 : 0
          color: blip.local ? Qt.rgba(1, 0.1, 0.1, 0.8) : Qt.rgba(1, 0.68, 0, 0.87)
          border.color: radar.cBone; border.width: 1
        }
        Column {
          visible: blip.labelled
          x: blip.brg < 180 ? 6 : -width - 6
          y: blip.ssid ? -15 : -9
          spacing: 0
          Mono {
            visible: blip.ssid !== ""
            anchors.right: blip.brg < 180 ? undefined : parent.right
            text: { var n = radar.netName(blip.ssid); return n.length > 13 ? n.slice(0, 12) + "…" : n }
            font.pixelSize: 7; font.letterSpacing: 0.6
            color: radar.cAmber
          }
          Mono {
            anchors.right: blip.brg < 180 ? undefined : parent.right
            text: blip.sec + " " + blip.band + "/" + blip.ch
            font.pixelSize: 6; font.letterSpacing: 0.4
            color: blip.local ? radar.cRed : radar.cOrange
          }
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
          Column {
            x: blip.brg < 180 ? -width - 12 : 12
            y: -18
            Text {
              anchors.right: blip.brg < 180 ? parent.right : undefined
              text: "使徒"
              color: radar.cCyan
              font.family: "Noto Sans CJK JP"; font.weight: Font.Black; font.pixelSize: 9
            }
            Mono {
              anchors.right: blip.brg < 180 ? parent.right : undefined
              text: { var n = radar.netName(blip.ssid); return n.length > 13 ? n.slice(0, 12) + "…" : n }
              color: radar.cCyan; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 0.6
            }
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
    Mono { anchors.right: parent.right; text: radar.ago(radar.hud.scanAge); font.pixelSize: 7; opacity: 0.85 }
    Mono { anchors.right: parent.right; text: radar.hud.scanNext >= 0 ? "NEXT SCAN " + radar.mmss(radar.hud.scanNext) : "NEXT SCAN --:--"; font.pixelSize: 7; opacity: 0.85 }
    Mono { anchors.right: parent.right; text: "RANGE = SIGNAL"; font.pixelSize: 7; opacity: 0.6 }
  }

  // targetBox carries the eased link quality + RX/TX, so it has its own layer (not the big static one)
  // ---------------------------------------------------------------- the associated network
  NervPanel {
    id: targetBox
    layer.enabled: true
    readonly property var a: radar.hud.angel
    x: 8; y: radar.height - 66; width: radar.width - 16; height: 58
    accent: a ? radar.cCyan : "#9C6A2E"
    fill: Qt.rgba(0, 0.03, 0.05, 0.78)
    title: a ? "PATTERN BLUE" : "NO LINK"
    jp: a ? "目標 接続中" : "未接続"
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
          width: parent.width - 120; elide: Text.ElideRight
          text: targetBox.a ? radar.netName(targetBox.a.ssid) + "  [" + (targetBox.a.sec || "?") + "]" : ""
          color: radar.cCyan; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 0.6
        }
        Mono {
          anchors.right: parent.right
          text: targetBox.a ? (targetBox.a.dbm !== undefined ? targetBox.a.dbm + " DBM  " : "") + Math.round(radar.hud.angelSigS) + "%" : ""
          color: "#E8FAFF"; font.pixelSize: 8; font.weight: Font.Bold
          opacity: radar.hud.angelHot && !radar.hud.blinkOn ? 0.55 : 1
        }
      }
      Item {
        width: parent.width; height: 10
        Mono {
          text: {
            var a = targetBox.a
            if (!a) return ""
            var s = a.band + " CH" + a.ch + (a.freq ? " " + a.freq + "MHZ" : "")
            if (a.rxBit !== undefined) s += "  LINK " + Math.round(a.rxBit) + "/" + Math.round(a.txBit || 0) + "M"
            return s
          }
          color: radar.cCyan; font.pixelSize: 7; opacity: 0.9; font.letterSpacing: 0.6
        }
        Mono {
          anchors.right: parent.right
          text: "↓" + radar.fmtRate(radar.hud.rxS) + " ↑" + radar.fmtRate(radar.hud.txS)
          color: "#E8FAFF"; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 0.4
        }
      }
      SegMeter {
        width: parent.width; height: 4; segments: 40
        value: radar.hud.angelSigS / 100
        color: radar.cCyan; hot: radar.cCyan; hotFrom: 2
        dim: Qt.rgba(0, 0.78, 1, 0.12)
      }
    }
    Mono {
      visible: targetBox.a === null
      text: radar.hud.wifiDev ? "NOT ASSOCIATED  //  AWAITING LINK  解析中" : "NO WIRELESS INTERFACE  //  解析中"
      color: "#9C6A2E"; font.pixelSize: 8
    }
  }
}
