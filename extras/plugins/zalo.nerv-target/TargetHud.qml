import QtQuick
import QtQuick.Shapes

// POSITRON RIFLE / 陽電子砲 目標捕捉 — the 368x252 wall panel (reference px; scaled by the window).
// Left: the scope. Static reticle painted once; other windows in a canvas repainted only on
// change. Motion is item/shape based at vsync (hud's FrameAnimation, paused when covered):
// the target rect / aim line / hairs / carets glide on eased target coords, the search sweep is
// a pre-painted wedge that only rotates, the Ramiel glyph (a 22 px canvas) spins every frame.
// The zoom brackets keep their hard stepped snap (steps clocked on whole frames).
// Right: target dossier, time on target (7-seg), positron charge, field count, corrections.
Item {
  id: t

  required property var hud

  readonly property color cOrange: "#FF7A00"
  readonly property color cAmber: "#FFB000"
  readonly property color cCyan: "#00C8FF"
  readonly property color cRed: "#FF1A1A"
  readonly property color cBone: "#FFE9C8"
  readonly property color cInk: "#050403"
  readonly property color cGraphite: "#4A3218"

  // scope geometry
  readonly property real cx: 112
  readonly property real cy: 114
  readonly property real rs: 88
  readonly property real hd: rs * 0.95
  readonly property real fw: 2 * hd * hud.aspect / Math.sqrt(1 + hud.aspect * hud.aspect)
  readonly property real fh: fw / hud.aspect
  readonly property real fx: cx - fw / 2
  readonly property real fy: cy - fh / 2

  // eased target rect (normalized): glides when the target moves / changes (Behaviors only run
  // while a move is in flight; the brackets land on the final hud.tn in hard steps meanwhile)
  property real tnx: hud.tn[0]
  property real tny: hud.tn[1]
  property real tnw: hud.tn[2]
  property real tnh: hud.tn[3]
  Behavior on tnx { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
  Behavior on tny { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
  Behavior on tnw { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
  Behavior on tnh { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

  // target centre in scope px (eased)
  readonly property real tx: fx + (tnx + tnw / 2) * fw
  readonly property real ty: fy + (tny + tnh / 2) * fh
  readonly property real tdx: tx - cx
  readonly property real tdy: ty - cy
  readonly property real azimuth: ((Math.atan2(tdx, -tdy) * 180 / Math.PI) + 360) % 360
  readonly property real elevation: -tdy / fh * 2 * 30
  readonly property real rangePx: Math.hypot((tnx + tnw / 2 - 0.5) * 1280, (tny + tnh / 2 - 0.5) * 800)

  // state
  readonly property bool has: hud.hasTarget
  readonly property bool lost: hud.lost
  readonly property color tcol: lost ? cRed : cCyan

  function css(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + (a === undefined ? c.a : a).toFixed(3) + ")" }
  function pad(n, w) { var s = String(Math.floor(n)); while (s.length < w) s = "0" + s; return s }
  function mmss(sec) {
    var s = Math.floor(sec)
    if (s >= 6000) return pad(Math.floor(s / 3600), 2) + "." + pad(Math.floor(s / 60) % 60, 2)   // HH.MM past 99:59
    return pad(Math.floor(s / 60), 2) + ":" + pad(s % 60, 2)
  }
  function fmtRss(kb) {
    if (kb < 0) return "----"
    if (kb >= 1048576) return (kb / 1048576).toFixed(2) + "G"
    return (kb / 1024).toFixed(1) + "M"
  }
  function fmtRate(bps) {
    if (bps >= 1048576) return (bps / 1048576).toFixed(1) + "M/S"
    if (bps >= 1024) return (bps / 1024).toFixed(1) + "K/S"
    return Math.round(bps) + "B/S"
  }
  function hex(seed, n) {
    var s = "", h = (seed * 374761393 + 668265263) >>> 0
    for (var i = 0; i < n; i++) {
      h = Math.imul(h ^ (h >>> 13), 1274126177) >>> 0
      h = (h + 0x9e3779b9) >>> 0
      s += "0123456789ABCDEF"[(h >>> 7) & 15]
    }
    return s
  }

  property real pxScale: 2      // device px per reference px (for crisp layers)

  // Layer A: chrome + reticle + target overlay. Re-renders only on data / glide / snap changes.
  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.ceil(width * t.pxScale), Math.ceil(height * t.pxScale))

  NervPanel {
      anchors.fill: parent
      title: "POSITRON RIFLE"
      jp: "陽電子砲 目標捕捉"
      cut: 14
      header: 14
      fill: Qt.rgba(0.02, 0.014, 0.008, t.hud.fillAlpha)
      alarm: t.lost && t.hud.blinkOn
    }
  
    // header status (right of the tick run)
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: 18
      y: 2
      width: hdrText.implicitWidth + 8
      height: 10
      color: t.cInk
      Mono {
        id: hdrText
        anchors.centerIn: parent
        font.pixelSize: 7
        font.weight: Font.Bold
        text: !t.has ? "FIELD CLEAR" : t.lost ? "TARGET LOST" : "PATTERN BLUE"
        color: !t.has ? t.cOrange : t.lost ? t.cRed : t.cCyan
        opacity: t.lost && !t.hud.blinkOn ? 0.3 : 1
      }
    }
  
    // ================================================================ static scope
    Canvas {
      id: scope
      x: 0; y: 0
      width: 212; height: 222
      Component.onCompleted: requestPaint()
      Connections { target: t.hud; function onAspectChanged() { scope.requestPaint() } }
      onPaint: {
        var c = getContext("2d")
        c.reset()
        c.clearRect(0, 0, width, height)
        var C = t.cx, Y = t.cy, R = t.rs, TAU = Math.PI * 2
        // disk
        c.beginPath(); c.arc(C, Y, R, 0, TAU); c.fillStyle = "rgba(3,2,1,0.75)"; c.fill()
        c.save()
        c.beginPath(); c.arc(C, Y, R, 0, TAU); c.clip()
        // fine grid
        c.fillStyle = "rgba(255,122,0,0.06)"
        for (var gx = C % 8; gx < 212; gx += 8) c.fillRect(Math.round(gx), 0, 1, 222)
        for (var gy = Y % 8; gy < 222; gy += 8) c.fillRect(0, Math.round(gy), 212, 1)
        // the field (the target's monitor) as a dashed frame with corner marks
        c.strokeStyle = "rgba(255,122,0,0.38)"
        c.lineWidth = 1
        c.setLineDash([2, 3])
        c.strokeRect(Math.round(t.fx) + 0.5, Math.round(t.fy) + 0.5, Math.round(t.fw), Math.round(t.fh))
        c.setLineDash([])
        c.restore()
        c.strokeStyle = "rgba(255,122,0,0.7)"
        c.beginPath()
        var fx0 = Math.round(t.fx) + 0.5, fy0 = Math.round(t.fy) + 0.5, fx1 = fx0 + Math.round(t.fw), fy1 = fy0 + Math.round(t.fh), m = 5
        c.moveTo(fx0, fy0 + m); c.lineTo(fx0, fy0); c.lineTo(fx0 + m, fy0)
        c.moveTo(fx1 - m, fy0); c.lineTo(fx1, fy0); c.lineTo(fx1, fy0 + m)
        c.moveTo(fx1, fy1 - m); c.lineTo(fx1, fy1); c.lineTo(fx1 - m, fy1)
        c.moveTo(fx0 + m, fy1); c.lineTo(fx0, fy1); c.lineTo(fx0, fy1 - m)
        c.stroke()
        // range rings
        c.strokeStyle = "rgba(255,122,0,0.28)"
        c.beginPath(); c.arc(C, Y, R * 0.33, 0, TAU); c.stroke()
        c.beginPath(); c.arc(C, Y, R * 0.66, 0, TAU); c.stroke()
        // rim
        c.strokeStyle = "rgba(255,122,0,1)"
        c.lineWidth = 1.6
        c.beginPath(); c.arc(C, Y, R, 0, TAU); c.stroke()
        c.lineWidth = 0.8
        c.strokeStyle = "rgba(255,122,0,0.5)"
        c.beginPath(); c.arc(C, Y, R - 5, 0, TAU); c.stroke()
        c.beginPath(); c.arc(C, Y, R + 4, 0, TAU); c.stroke()
        // bezel ticks every 5°
        for (var i = 0; i < 72; i++) {
          var a = i / 72 * TAU, mj = i % 6 === 0, l = mj ? 6 : 2.5
          c.strokeStyle = mj ? "rgba(255,122,0,0.9)" : "rgba(255,122,0,0.5)"
          c.beginPath()
          c.moveTo(C + Math.sin(a) * (R - 5), Y - Math.cos(a) * (R - 5))
          c.lineTo(C + Math.sin(a) * (R - 5 - l), Y - Math.cos(a) * (R - 5 - l))
          c.stroke()
        }
        // crosshair: heavy posts outside, hairline inside, mil ticks
        c.fillStyle = "rgba(255,122,0,0.95)"
        var post = R * 0.36
        c.fillRect(C - R, Y - 1.5, post, 3); c.fillRect(C + R - post, Y - 1.5, post, 3)
        c.fillRect(C - 1.5, Y - R, 3, post); c.fillRect(C - 1.5, Y + R - post, 3, post)
        c.fillStyle = "rgba(255,122,0,0.85)"
        c.fillRect(C - R + post, Y - 0.4, R - post - 6, 0.8); c.fillRect(C + 6, Y - 0.4, R - post - 6, 0.8)
        c.fillRect(C - 0.4, Y - R + post, 0.8, R - post - 6); c.fillRect(C - 0.4, Y + 6, 0.8, R - post - 6)
        for (var k = 1; k * 7 < R - post; k++) {
          var s = k * 7, ll = k % 5 === 0 ? 3.5 : 1.8
          c.fillRect(C + s - 0.4, Y - ll, 0.8, ll * 2); c.fillRect(C - s - 0.4, Y - ll, 0.8, ll * 2)
          c.fillRect(C - ll, Y + s - 0.4, ll * 2, 0.8); c.fillRect(C - ll, Y - s - 0.4, ll * 2, 0.8)
        }
        c.strokeStyle = "rgba(255,122,0,1)"
        c.lineWidth = 1
        c.beginPath(); c.arc(C, Y, 2.5, 0, TAU); c.stroke()
        // quadrant labels
        c.fillStyle = "rgba(255,122,0,0.6)"
        c.font = "600 5px 'IBM Plex Mono'"
        c.fillText("000", C + 3, Y - R + 13)
        c.fillText("090", C + R - 20, Y - 3)
        c.fillText("180", C + 3, Y + R - 9)
        c.fillText("270", C - R + 9, Y - 3)
        // elevation scale (left)
        c.fillStyle = "rgba(255,122,0,0.75)"
        c.fillRect(15.5, Y - R, 0.8, 2 * R)
        for (var e = -12; e <= 12; e++) {
          var ey = Y + e * (R / 12), big = e % 4 === 0
          c.fillRect(big ? 9 : 12, Math.round(ey), big ? 7 : 4, 0.8)
        }
        c.font = "600 5px 'IBM Plex Mono'"
        c.fillText("EL", 7, Y - R - 3)
        // azimuth scale (bottom)
        var ay = Y + R + 10
        c.fillRect(C - R, ay, 2 * R, 0.8)
        for (var z = -12; z <= 12; z++) {
          var zx = C + z * (R / 12), bg = z % 4 === 0
          c.fillRect(Math.round(zx), ay, 0.8, bg ? 6 : 3)
        }
        c.fillText("AZ", C + R + 5, ay + 5)
      }
    }
  
    // ================================================================ dynamic overlay
    // other windows on the target's workspace: dim orange silhouettes (repainted on change only)
    Canvas {
      id: fieldCv
      x: 0; y: 0
      width: 212; height: 222
      Component.onCompleted: requestPaint()
      Connections {
        target: t.hud
        function onFieldChanged() { fieldCv.requestPaint() }
        function onHasTargetChanged() { fieldCv.requestPaint() }
        function onAspectChanged() { fieldCv.requestPaint() }
      }
      onPaint: {
        var c = getContext("2d")
        c.reset()
        c.clearRect(0, 0, width, height)
        var h = t.hud
        if (!h.hasTarget) return
        c.save()
        c.beginPath(); c.arc(t.cx, t.cy, t.rs - 1, 0, Math.PI * 2); c.clip()
        c.lineWidth = 1
        for (var i = 0; i < h.field.length; i++) {
          var n = h.field[i]
          var r = [t.fx + n[0] * t.fw, t.fy + n[1] * t.fh, n[2] * t.fw, n[3] * t.fh]
          c.fillStyle = "rgba(255,122,0,0.07)"
          c.fillRect(r[0], r[1], r[2], r[3])
          c.strokeStyle = "rgba(255,122,0,0.45)"
          c.strokeRect(Math.round(r[0]) + 0.5, Math.round(r[1]) + 0.5, Math.max(1, Math.round(r[2]) - 1), Math.max(1, Math.round(r[3]) - 1))
        }
        c.restore()
      }
    }
  
    // the target window (eased rect)
    Rectangle {
      visible: t.has
      x: t.fx + t.tnx * t.fw
      y: t.fy + t.tny * t.fh
      width: Math.max(1, t.tnw * t.fw)
      height: Math.max(1, t.tnh * t.fh)
      antialiasing: true
      color: Qt.rgba(t.tcol.r, t.tcol.g, t.tcol.b, 0.13)
      border.width: 1
      border.color: Qt.rgba(t.tcol.r, t.tcol.g, t.tcol.b, 0.85)
    }
  
    // hairs, aim line, scale carets, zoom brackets: one Shape; only the paths whose inputs moved
    // are re-triangulated (hairs/aim/carets while gliding, brackets on each hard snap step)
    Shape {
      id: ov
      visible: t.has
      x: 0; y: 0
      width: 212; height: 222
      preferredRendererType: Shape.GeometryRenderer
      readonly property real oc: t.cx
      readonly property real oy: t.cy
      readonly property real orr: t.rs - 1
      readonly property color col: t.tcol
      // tracking hairs: chords of the scope circle through the target
      readonly property real hy: Math.max(oy - orr, Math.min(oy + orr, t.ty))
      readonly property real hxw: Math.sqrt(Math.max(0, orr * orr - (hy - oy) * (hy - oy)))
      readonly property real vx: Math.max(oc - orr, Math.min(oc + orr, t.tx))
      readonly property real vyh: Math.sqrt(Math.max(0, orr * orr - (vx - oc) * (vx - oc)))
      // carets on the elevation / azimuth scales
      readonly property real ey: Math.max(t.cy - t.rs, Math.min(t.cy + t.rs, t.ty))
      readonly property real ax: Math.max(t.cx - t.rs, Math.min(t.cx + t.rs, t.tx))
      readonly property real ay: t.cy + t.rs + 10
      // zoom brackets from hud.br (stepped)
      readonly property var bb: [t.fx + t.hud.br[0] * t.fw, t.fy + t.hud.br[1] * t.fh, t.hud.br[2] * t.fw, t.hud.br[3] * t.fh]
      readonly property real bw: Math.max(18, bb[2] + 8)
      readonly property real bh: Math.max(18, bb[3] + 8)
      readonly property real bx: bb[0] + bb[2] / 2 - bw / 2
      readonly property real by: bb[1] + bb[3] / 2 - bh / 2
      readonly property real bl: Math.max(5, Math.min(12, Math.min(bw, bh) * 0.28))
      function pt(x, y) { return Qt.point(x, y) }
  
      ShapePath {   // horizontal + vertical tracking hairs
        strokeColor: Qt.rgba(ov.col.r, ov.col.g, ov.col.b, 0.45)
        strokeWidth: 1
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        strokeStyle: ShapePath.DashLine
        dashPattern: [1, 2]
        PathMultiline {
          paths: [[ov.pt(ov.oc - ov.hxw, ov.hy), ov.pt(ov.oc + ov.hxw, ov.hy)],
                  [ov.pt(ov.vx, ov.oy - ov.vyh), ov.pt(ov.vx, ov.oy + ov.vyh)]]
        }
      }
      ShapePath {   // aim line: crosshair -> target
        strokeColor: Qt.rgba(ov.col.r, ov.col.g, ov.col.b, 0.8)
        strokeWidth: 1
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        strokeStyle: ShapePath.DashLine
        dashPattern: [3, 2]
        startX: ov.oc; startY: ov.oy
        PathLine { x: t.tx; y: t.ty }
      }
      ShapePath {   // scale carets
        strokeColor: "transparent"
        fillColor: ov.col
        PathMultiline {
          paths: [[ov.pt(17, ov.ey), ov.pt(23, ov.ey - 3), ov.pt(23, ov.ey + 3), ov.pt(17, ov.ey)],
                  [ov.pt(ov.ax, ov.ay - 1), ov.pt(ov.ax - 3, ov.ay - 6), ov.pt(ov.ax + 3, ov.ay - 6), ov.pt(ov.ax, ov.ay - 1)]]
        }
      }
      ShapePath {   // zoom brackets (amber while snapping)
        strokeColor: t.hud.phase === 1 ? t.cAmber : ov.col
        strokeWidth: 1.6
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.MiterJoin
        PathMultiline {
          paths: [[ov.pt(ov.bx, ov.by + ov.bl), ov.pt(ov.bx, ov.by), ov.pt(ov.bx + ov.bl, ov.by)],
                  [ov.pt(ov.bx + ov.bw - ov.bl, ov.by), ov.pt(ov.bx + ov.bw, ov.by), ov.pt(ov.bx + ov.bw, ov.by + ov.bl)],
                  [ov.pt(ov.bx + ov.bw, ov.by + ov.bh - ov.bl), ov.pt(ov.bx + ov.bw, ov.by + ov.bh), ov.pt(ov.bx + ov.bw - ov.bl, ov.by + ov.bh)],
                  [ov.pt(ov.bx + ov.bl, ov.by + ov.bh), ov.pt(ov.bx, ov.by + ov.bh), ov.pt(ov.bx, ov.by + ov.bh - ov.bl)]]
        }
      }
      ShapePath {   // converging carets on the diagonals once locked
        strokeColor: t.hud.phase >= 2 ? ov.col : "transparent"
        strokeWidth: 1.1
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        PathMultiline {
          paths: {
            var o = [], cxm = ov.bx + ov.bw / 2, cym = ov.by + ov.bh / 2
            for (var q = 0; q < 4; q++) {
              var sx = q === 0 || q === 3 ? -1 : 1, sy = q < 2 ? -1 : 1
              var ex = cxm + sx * (ov.bw / 2 + 4), ey2 = cym + sy * (ov.bh / 2 + 4)
              o.push([ov.pt(ex + sx * 5, ey2), ov.pt(ex, ey2), ov.pt(ex, ey2 + sy * 5)])
            }
            return o
          }
        }
      }
    }
  
  }

  // no target: search sweep — wedge + bearing line painted once, rotated by the frame clock
  Item {
    visible: !t.has
    x: t.cx - t.rs; y: t.cy - t.rs
    width: 2 * t.rs; height: 2 * t.rs
    rotation: t.hud.spin * 180 / Math.PI
    Canvas {
      anchors.fill: parent
      antialiasing: true
      Component.onCompleted: requestPaint()
      onPaint: {
        var c = getContext("2d")
        c.reset()
        var C = width / 2, R = t.rs - 1
        c.fillStyle = "rgba(255,122,0,0.10)"
        c.beginPath(); c.moveTo(C, C); c.arc(C, C, R, -Math.PI / 2 - 0.5, -Math.PI / 2); c.closePath(); c.fill()
        c.strokeStyle = "rgba(255,176,0,0.9)"
        c.lineWidth = 1
        c.beginPath(); c.moveTo(C, C); c.lineTo(C, C - R); c.stroke()
      }
    }
  }


  // Layer B: lock tag, no-target card, status strip, dossier column (blink / data changes only).
  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.ceil(width * t.pxScale), Math.ceil(height * t.pxScale))

  // LOCK ON flash tag in the scope
    Rectangle {
      visible: t.has && (t.hud.phase === 2 ? t.hud.flashStep % 2 === 0 : false)
      x: Math.round(t.cx - width / 2)
      y: Math.round(t.cy - t.rs + 16)
      width: lockText.implicitWidth + 10
      height: 11
      color: t.cCyan
      Mono {
        id: lockText
        anchors.centerIn: parent
        text: "LOCK ON 照準固定"
        font.family: "IBM Plex Mono, Noto Sans CJK JP"
        font.pixelSize: 7; font.weight: Font.Bold
        color: t.cInk
      }
    }
  
    // no target: centre card
    Column {
      visible: !t.has
      anchors.horizontalCenter: undefined
      x: t.cx - width / 2
      y: t.cy + 14
      spacing: 1
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: ntText.implicitWidth + 10; height: 11
        color: t.cInk
        border.color: t.cOrange; border.width: 1
        Mono { id: ntText; anchors.centerIn: parent; text: "NO TARGET"; font.pixelSize: 7; font.weight: Font.Bold; opacity: t.hud.blinkOn ? 1 : 0.4 }
      }
      Jp { anchors.horizontalCenter: parent.horizontalCenter; text: "目標なし"; font.pixelSize: 8; color: t.cAmber }
    }
  
    // ================================================================ status strip under the scope
    Item {
      x: 16; y: 224
      width: 192; height: 16
      readonly property int mode: !t.has ? 0 : t.lost ? 1 : t.hud.phase === 1 ? 2 : t.hud.phase === 2 ? 3 : 4
      readonly property color sc: mode === 1 ? t.cRed : mode === 2 ? t.cAmber : mode >= 3 ? t.cCyan : t.cOrange
      readonly property bool inv: mode === 3 ? t.hud.flashStep % 2 === 0 : mode === 1 ? t.hud.blinkOn : false
      id: strip
      Canvas {
        anchors.fill: parent
        id: stripBg
        Connections {
          target: strip
          function onScChanged() { stripBg.requestPaint() }
          function onInvChanged() { stripBg.requestPaint() }
        }
        Component.onCompleted: requestPaint()
        onPaint: {
          var c = getContext("2d")
          c.reset()
          c.clearRect(0, 0, width, height)
          var w = width, h = height, k = 5
          c.beginPath()
          c.moveTo(0.5, 0.5); c.lineTo(w - k, 0.5); c.lineTo(w - 0.5, k); c.lineTo(w - 0.5, h - 0.5); c.lineTo(k, h - 0.5); c.lineTo(0.5, h - k); c.closePath()
          c.fillStyle = strip.inv ? t.css(strip.sc, 1) : "rgba(5,4,3,0.9)"
          c.fill()
          c.strokeStyle = t.css(strip.sc, 1)
          c.lineWidth = 1
          c.stroke()
        }
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        x: 6
        spacing: 5
        Rectangle { width: 5; height: 5; anchors.verticalCenter: parent.verticalCenter; color: strip.inv ? t.cInk : strip.sc; opacity: strip.mode === 0 && !t.hud.blinkOn ? 0.25 : 1 }
        Mono {
          anchors.verticalCenter: parent.verticalCenter
          font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.6
          color: strip.inv ? t.cInk : strip.sc
          text: ["NO TARGET", "TARGET LOST", "TRACKING", "LOCK ON", "LOCKED"][strip.mode]
        }
        Jp {
          anchors.verticalCenter: parent.verticalCenter
          font.pixelSize: 8
          color: strip.inv ? t.cInk : strip.sc
          text: ["目標なし", "目標消失", "追尾中", "照準固定", "照準固定"][strip.mode]
        }
      }
      Mono {
        anchors.right: parent.right; anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: 6; opacity: 0.75
        color: strip.inv ? t.cInk : strip.sc
        text: strip.mode === 0 ? "FIELD CLEAR" : strip.mode === 1 ? "SIGNAL 0" : "RNG " + (t.rangePx / 100).toFixed(2) + "KM"
      }
    }
  
    // ================================================================ right column: dossier
    Item {
      id: col
      x: 212; y: 19
      width: 148; height: 226
  
      // --- identification
      Item {
        width: parent.width; height: 9
        Mono { text: "TARGET"; font.pixelSize: 7; opacity: 0.7 }
        Jp { x: 34; y: -1; text: "目標"; font.pixelSize: 7; opacity: 0.8 }
        Mono {
          anchors.right: parent.right
          text: t.has ? "TGT-" + (t.hud.shownAddr.length > 4 ? t.hud.shownAddr.slice(-4).toUpperCase() : "----") : "TGT-NULL"
          font.pixelSize: 6; opacity: 0.55; font.letterSpacing: 0.8
        }
      }
      Mono {
        y: 10
        width: parent.width
        elide: Text.ElideRight
        text: t.has ? (t.hud.shownClass || t.hud.comm || "UNKNOWN").toUpperCase() : "— NONE —"
        font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.0
        color: !t.has ? t.cGraphite : t.lost ? t.cRed : t.cCyan
      }
      Mono {
        y: 23
        width: parent.width
        elide: Text.ElideRight
        text: t.has ? (t.hud.shownTitle || "UNTITLED").toUpperCase() : "FIELD CLEAR — AWAITING FOCUS"
        font.pixelSize: 7; font.letterSpacing: 0.8; opacity: 0.8
        color: t.cAmber
      }
      Rectangle { y: 33; width: parent.width; height: 1; color: t.cOrange; opacity: 0.4 }
  
      // --- data rows
      Column {
        y: 36
        width: parent.width
        spacing: 1
        Repeater {
          model: [
            ["PID", t.has ? String(t.hud.shownPid || "----") : "----", "WS", t.has ? (t.hud.tWs || "-") : "-"],
            ["GEOM", t.has ? t.hud.tGeom[0] + "," + t.hud.tGeom[1] : "---,---", "", t.has ? t.hud.tGeom[2] + "×" + t.hud.tGeom[3] : "---×---"],
            ["MODE", t.has ? (t.hud.tFull ? "FULLSCR" : t.hud.tFloating ? "FLOAT" : "TILED") + (t.hud.tXway ? " XWL" : "") : "----",
                     "THR", t.has && t.hud.threads > 0 ? String(t.hud.threads) : "--"],
            ["CPU", t.has && !t.lost && t.hud.cpu >= 0 ? t.hud.cpu.toFixed(1) + "%" : "--.-%", "RSS", t.has && !t.lost ? t.fmtRss(t.hud.rss) : "----"]
          ]
          delegate: Item {
            required property var modelData
            required property int index
            width: col.width; height: 9
            Mono { text: modelData[0]; font.pixelSize: 7; opacity: 0.6 }
            Mono { x: 26; text: modelData[1]; font.pixelSize: 7; font.weight: Font.Bold; color: index === 3 && t.hud.cpu > 50 ? t.cRed : t.cAmber }
            Mono { x: 86; text: modelData[2]; font.pixelSize: 7; opacity: 0.6; visible: modelData[2] !== "" }
            Mono { anchors.right: parent.right; text: modelData[3]; font.pixelSize: 7; font.weight: Font.Bold; color: t.cAmber }
          }
        }
      }
      Rectangle { y: 77; width: parent.width; height: 1; color: t.cOrange; opacity: 0.4 }
  
      // --- time on target + field count
      Item {
        y: 80
        width: parent.width; height: 32
        Mono { text: "ON TARGET"; font.pixelSize: 6; opacity: 0.7 }
        Jp { x: 44; y: -1; text: "照準時間"; font.pixelSize: 6; opacity: 0.7 }
        SevenSeg {
          x: 0; y: 11
          digitHeight: 18
          text: t.has ? t.mmss(t.hud.onTarget) : "--:--"
          color: t.lost ? t.cRed : t.cAmber
        }
        Mono { anchors.right: parent.right; text: "TARGETS"; font.pixelSize: 6; opacity: 0.7 }
        Jp { anchors.right: parent.right; anchors.rightMargin: 38; y: -1; text: "標的"; font.pixelSize: 6; opacity: 0.7 }
        SevenSeg {
          anchors.right: parent.right
          y: 11
          digitHeight: 18
          text: t.pad(Math.min(99, t.hud.targets), 2)
          color: t.cCyan
          dim: Qt.rgba(0, 0.78, 1, 0.07)
        }
      }
  
      // --- positron charge
      Item {
        y: 116
        width: parent.width; height: 18
        readonly property bool full: t.hud.charge >= 1
        id: chg
        Mono { text: "CHARGE"; font.pixelSize: 7; opacity: 0.7 }
        Jp { x: 36; y: -1; text: "陽電子 充填"; font.pixelSize: 7; opacity: 0.8 }
        Mono {
          anchors.right: parent.right
          text: !t.has ? "000%" : chg.full ? "FIRE READY" : t.pad(t.hud.charge * 100, 3) + "%"
          font.pixelSize: 7; font.weight: Font.Bold
          color: chg.full ? t.cRed : t.cAmber
          opacity: chg.full && !t.hud.blinkOn ? 0.35 : 1
        }
      }
      Rectangle { y: 137; width: parent.width; height: 1; color: t.cOrange; opacity: 0.4 }
  
      // --- ballistic corrections (fun units, real sources)
      Mono { y: 140; text: "CORRECTION"; font.pixelSize: 6; opacity: 0.7 }
      Jp { x: 52; y: 139; text: "弾道補正"; font.pixelSize: 6; opacity: 0.7 }
      Column {
        y: 149
        width: parent.width
        spacing: 1
        Repeater {
          model: [
            ["WIND", "風速", t.hud.load[0].toFixed(2) + " M/S", "LOAD " + t.hud.load[1].toFixed(2), t.hud.load[0] > 12],
            ["GRAVITY", "重力", (9.80665 + t.hud.memPct * 0.001 + t.hud.memPsi * 0.01).toFixed(3) + " G", "MEM " + Math.round(t.hud.memPct) + "%" , t.hud.memPsi > 10],
            ["GEOMAG", "地磁気", (25 + 8 * Math.log(1 + t.hud.netRate / 1024)).toFixed(1) + " μT", "NET " + t.fmtRate(t.hud.netRate), false]
          ]
          delegate: Item {
            required property var modelData
            width: col.width; height: 10
            Mono { text: modelData[0]; font.pixelSize: 7; opacity: 0.8; color: modelData[4] ? t.cRed : t.cOrange }
            Jp { x: 40; y: -1; text: modelData[1]; font.pixelSize: 6; opacity: 0.6 }
            Mono { x: 62; text: modelData[2]; font.pixelSize: 7; font.weight: Font.Bold; color: modelData[4] ? t.cRed : t.cAmber }
            Mono { anchors.right: parent.right; y: 1; text: modelData[3]; font.pixelSize: 5; opacity: 0.55; font.letterSpacing: 0.6 }
          }
        }
      }
      Rectangle { y: 183; width: parent.width; height: 1; color: t.cOrange; opacity: 0.4 }
  
      // --- firing solution
      Item {
        y: 186
        width: parent.width; height: 9
        Mono { text: "AZ"; font.pixelSize: 6; opacity: 0.6 }
        Mono { x: 12; text: t.has ? t.pad(t.azimuth, 3) + "." + Math.floor((t.azimuth * 10) % 10) + "°" : "---.-°"; font.pixelSize: 7; font.weight: Font.Bold; color: t.tcol }
        Mono { x: 52; text: "EL"; font.pixelSize: 6; opacity: 0.6 }
        Mono { x: 64; text: t.has ? (t.elevation >= 0 ? "+" : "-") + Math.abs(t.elevation).toFixed(1) + "°" : "--.-°"; font.pixelSize: 7; font.weight: Font.Bold; color: t.tcol }
        Mono { anchors.right: parent.right; text: t.has ? "RNG " + Math.round(t.rangePx) : "RNG ---"; font.pixelSize: 7; font.weight: Font.Bold; color: t.tcol }
      }
      Mono {
        y: 206
        width: parent.width
        text: "ヤシマ作戦 // " + (t.has ? "ATTACK VECTOR " + t.pad(t.azimuth, 3) : "STANDBY") + " // 第3新東京市"
        font.family: "IBM Plex Mono, Noto Sans CJK JP"
        font.pixelSize: 6; opacity: 0.45; font.letterSpacing: 0.6
        elide: Text.ElideRight
      }
    }
  }

  // ---- per-frame movers, outside the layers
  // the target glyph: a small cyan wireframe octahedron (Ramiel), spun every frame. A 3-D spin
  // isn't an affine transform, but each edge is: 12 antialiased 1 px rectangles whose position /
  // length / rotation follow the projected vertices (no canvas rasterize + upload per frame).
  Item {
    id: glyph
    visible: t.has
    x: t.tx - 11
    y: t.ty - 11
    width: 22; height: 22
    readonly property bool flash: t.hud.phase === 2 && t.hud.flashStep % 2 === 0
    readonly property color ecol: flash ? t.cBone : t.tcol
    readonly property var edges: [[0, 2], [0, 3], [0, 4], [0, 5], [1, 2], [1, 3], [1, 4], [1, 5], [2, 4], [4, 3], [3, 5], [5, 2]]
    readonly property var verts: {
      var ang = t.hud.spin, tl = 0.3, S = 6.2, X = 11, Y = 11
      var ca = Math.cos(ang), sa = Math.sin(ang), ct = Math.cos(tl), st = Math.sin(tl)
      return [[0, -1.45, 0], [0, 1.45, 0], [1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1]].map(function (p) {
        var xr = p[0] * ca - p[2] * sa, zr = p[0] * sa + p[2] * ca
        var yr = p[1] * ct - zr * st, z2 = p[1] * st + zr * ct
        return [X + xr * S, Y + yr * S, z2]
      })
    }
    Repeater {
      model: 12
      Rectangle {
        required property int index
        readonly property var p: glyph.verts[glyph.edges[index][0]]
        readonly property var q: glyph.verts[glyph.edges[index][1]]
        x: p[0]
        y: p[1] - 0.5
        width: Math.hypot(q[0] - p[0], q[1] - p[1])
        height: 1
        transformOrigin: Item.Left
        rotation: Math.atan2(q[1] - p[1], q[0] - p[0]) * 180 / Math.PI
        antialiasing: true
        color: glyph.ecol
        opacity: (p[2] + q[2]) * 0.5 > 0.2 ? 0.35 : 1
      }
    }
  }

  SegMeter {
    x: col.x; y: col.y + 126
    width: col.width; height: 6; segments: 30
    value: t.has ? t.hud.chargeLive : 0
    hotFrom: 0.9
    color: t.cAmber
  }

  // --- hex filler: a continuous sub-pixel scroll (12 px/s) of a fixed hex run
  Item {
    x: col.x; y: col.y + 198
    width: col.width
    height: 9
    clip: true
    Mono {
      id: hexRun
      readonly property string run: {
        var s = ""
        for (var i = 0; i < 6; i++) s += t.hex(i * 37 + 5, 8) + " " + t.hex(i * 11 + 71, 4) + " "
        return s
      }
      text: run + run
      x: -((t.hud.fclock * 12) % Math.max(1, implicitWidth / 2))
      font.pixelSize: 6; opacity: 0.35; font.letterSpacing: 0.9
    }
  }
}
