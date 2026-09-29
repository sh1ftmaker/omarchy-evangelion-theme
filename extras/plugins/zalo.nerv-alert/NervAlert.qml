import QtQuick
import Quickshell
import Quickshell.Wayland

// NERV alarm overlay. Summon with a JSON payload:
//   omarchy-shell shell summon zalo.nerv-alert '{"variant":"pattern-blue","message":"..."}'
// variants: emergency | pattern-blue | activity-limit | sync
// overrides: title, jp, message (ticker), sub (header line), value (7-seg number),
//            beats (length in 0.45 s beats, default 8), dim (bool)
//
// Timeline: ~0.2 s pre-roll with an empty surface (so Hyprland's layer fade
// has nothing to fade), hazard bands step in from top/bottom, the warning box
// slams in, blinks inverted on every beat of 133.33 BPM, then hard-cuts away.
// The surface is click-through (empty input mask) and never takes keyboard focus.
Item {
  id: root

  // Host injection (only what we use).
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool running: false
  property real t: -1
  property real startMs: 0
  property var cfg: root.configFor("emergency", {})

  readonly property real preroll: 0.2
  readonly property real beat: 0.45
  readonly property real t0: 0.14
  readonly property int beats: cfg.beats
  readonly property real total: t0 + beats * beat
  readonly property int beatIndex: t < t0 ? -1 : Math.floor((t - t0) / beat)
  readonly property real beatPhase: t < t0 ? 0 : (t - t0) - beatIndex * beat
  readonly property bool lastBeat: beatIndex >= beats - 1
  readonly property bool inv: running && beatIndex >= 0 && (lastBeat ? beatPhase > 0.22 : beatPhase < 0.2)
  readonly property int frame: Math.max(0, Math.floor(t * 15))
  readonly property bool slammed: t >= t0
  readonly property bool kick: beatIndex >= 0 && beatPhase < 0.07

  readonly property var pal: ({
    ink: "#050403", ink2: "#120C06", graphite: "#4A3218", ash: "#9C6A2E", bone: "#FFE9C8",
    orange: "#FF7A00", amber: "#FFB000", red: "#FF1A1A", blood: "#6A0000", green: "#39FF6A",
    cyan: "#00C8FF", purple: "#7A3CFF", lime: "#B6FF00"
  })
  readonly property string mono: "IBM Plex Mono"
  readonly property string jpSans: "Noto Sans CJK JP"
  readonly property string jpSerif: "Noto Serif CJK JP"

  function configFor(variant, p) {
    var P = {
      ink: "#050403", bone: "#FFE9C8", orange: "#FF7A00", amber: "#FFB000", red: "#FF1A1A",
      cyan: "#00C8FF", purple: "#7A3CFF", lime: "#B6FF00"
    }
    var c
    if (variant === "pattern-blue") {
      c = {
        accent: P.cyan, band: P.red, panelFill: Qt.rgba(0, 0.024, 0.043, 0.96),
        title: "PATTERN BLUE", jp: "パターン青　使徒と確認", titleColor: P.cyan, numColor: P.cyan,
        tab: "EMERGENCY", tabJp: "緊急事態", tabColor: P.red,
        sub: "WAVE PATTERN ANALYSIS: CONFIRMED  //  MAGI 3/3  //  BLOOD TYPE: BLUE",
        message: "PATTERN BLUE CONFIRMED // BLOOD TYPE: BLUE // 使徒 接近中 // ALL PERSONNEL TO LEVEL-1 BATTLE STATIONS // 第一種戦闘配置",
        leftLabel: "CODE", leftValue: "601", leftJp: "解析中", leftJp2: "目標",
        rightLabel: "ALARM", rightMode: "count", rightJp: "使徒接近", value: ""
      }
    } else if (variant === "activity-limit") {
      c = {
        accent: P.red, band: P.red, panelFill: Qt.rgba(0.118, 0, 0, 0.96),
        title: "ACTIVITY LIMIT", jp: "活動限界", titleColor: P.bone, numColor: P.amber,
        tab: "INTERNAL POWER", tabJp: "内部電源", tabColor: P.amber,
        sub: "EXTERNAL POWER DISCONNECTED  //  外部電源 切断  //  UMBILICAL CABLE LOST",
        message: "INTERNAL BATTERY LOW // 活動限界まで // CONNECT EXTERNAL POWER // 外部電源 接続せよ",
        leftLabel: "POWER %", leftValue: "", leftJp: "内部電源", leftJp2: "残量",
        rightLabel: "LEVEL", rightMode: "meter", rightJp: "活動限界", value: ""
      }
    } else if (variant === "sync") {
      c = {
        accent: P.purple, band: P.purple, panelFill: Qt.rgba(0.055, 0.016, 0.118, 0.96),
        title: "SYNCHRONIZATION", jp: "同調率", titleColor: P.lime, numColor: P.lime,
        tab: "NEURAL LINK", tabJp: "神経接続", tabColor: P.lime,
        sub: "A10 NERVE CONNECTION  //  HARMONICS: ALL CLEAR  //  UNIT-01",
        message: "SYNC RATIO RISING // 同調率 上昇中 // PILOT NEURAL CONNECTION STABLE // 神経接続 正常",
        leftLabel: "RATIO", leftValue: "400", leftJp: "同調率", leftJp2: "初号機",
        rightLabel: "SYNC", rightMode: "meter", rightJp: "暴走", value: ""
      }
    } else {
      c = {
        accent: P.red, band: P.red, panelFill: Qt.rgba(0.118, 0, 0, 0.96),
        title: "EMERGENCY", jp: "緊急事態発生", titleColor: P.bone, numColor: P.red,
        tab: "WARNING", tabJp: "警告", tabColor: P.red,
        sub: "NERV HQ  //  ALL PERSONNEL  //  LEVEL-1 BATTLE STATIONS",
        message: "EMERGENCY // 緊急事態 // ALL PERSONNEL TO LEVEL-1 BATTLE STATIONS // 第一種戦闘配置 // CIVILIANS EVACUATE TO SHELTERS",
        leftLabel: "LEVEL", leftValue: "1", leftJp: "第一種", leftJp2: "警戒態勢",
        rightLabel: "ALARM", rightMode: "count", rightJp: "警報発令", value: ""
      }
      variant = "emergency"
    }
    c.variant = variant
    if (p.title !== undefined && String(p.title) !== "") c.title = String(p.title)
    if (p.jp !== undefined) c.jp = String(p.jp)
    if (p.message !== undefined && String(p.message) !== "") c.message = String(p.message)
    if (p.sub !== undefined) c.sub = String(p.sub)
    if (p.value !== undefined && p.value !== null && String(p.value) !== "") c.value = String(p.value)
    if (c.value !== "") c.leftValue = c.value
    if (c.leftValue === "") c.leftValue = "--"
    if (variant === "activity-limit" && /^[0-9]$/.test(c.leftValue)) c.leftValue = "0" + c.leftValue
    // Meter fraction: battery percentage out of 100, sync ratio out of 400.
    var num = parseFloat(c.leftValue)
    c.meter = isNaN(num) ? 0.5 : Math.max(0, Math.min(1, variant === "sync" ? num / 400 : num / 100))
    var b = parseInt(p.beats)
    c.beats = isNaN(b) ? 8 : Math.max(2, Math.min(40, b))
    c.dim = p.dim === undefined ? true : p.dim !== false && p.dim !== "false"
    return c
  }

  function hexData(seed, n) {
    var s = ""
    var x = (seed * 2654435761 + 12345) >>> 0
    for (var i = 0; i < n; i++) {
      x = (x * 1103515245 + 12345) >>> 0
      s += ((x >>> 16) & 15).toString(16).toUpperCase()
    }
    return s
  }

  function open(payloadJson) {
    var p = {}
    try { p = JSON.parse(payloadJson || "{}") || {} } catch (e) { p = {} }
    if (typeof p !== "object") p = {}
    cfg = configFor(String(p.variant || "emergency"), p)
    running = false
    t = -1
    startMs = Date.now()
    opened = true
    endTimer.stop()
    clock.restart()
  }

  function close() {
    clock.stop()
    endTimer.stop()
    running = false
    opened = false
  }

  function cut() {
    // Hard cut: drop the content in one frame, unmap once the compositor has
    // shown the empty surface so the layer fade-out has nothing to fade.
    clock.stop()
    running = false
    t = -1
    endTimer.restart()
  }

  Timer {
    id: clock
    interval: 33
    repeat: true
    onTriggered: {
      var el = (Date.now() - root.startMs) / 1000
      if (el < root.preroll) return
      root.running = true
      root.t = el - root.preroll
      if (root.t >= root.total) root.cut()
    }
  }

  Timer {
    id: endTimer
    interval: 220
    onTriggered: {
      root.opened = false
      var id = root.manifest && root.manifest.id ? root.manifest.id : "zalo.nerv-alert"
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(id)
    }
  }

  PanelWindow {
    id: win
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "nerv-alert"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual-only: empty input region so every click passes through.
    mask: Region {}

    Item {
      id: stage
      anchors.fill: parent
      visible: root.running

      // Design space is 1280x800 logical; everything scales with u.
      readonly property real u: Math.min(width / 1280, height / 800)
      readonly property real ox: (width - 1280 * u) / 2
      readonly property real oy: (height - 800 * u) / 2
      function sx(v) { return ox + v * u }
      function sy(v) { return oy + v * u }

      // ---------------------------------------------------------------- dim
      Rectangle {
        anchors.fill: parent
        visible: root.cfg.dim
        color: Qt.rgba(0.02, 0.016, 0.012, root.slammed ? 0.5 : 0.25)
      }

      // ------------------------------------------------------ hazard bands
      readonly property real bandIn: Math.min(1, Math.floor(root.t / 0.035 + 1) / 4)
      readonly property real scroll: root.lastBeat ? (root.beats - 1) * 60 : root.frame * 4 + Math.max(0, root.beatIndex) * 14

      Item {
        id: topBand
        x: 0; width: parent.width
        height: 34 * stage.u
        y: stage.sy(-60 + (128 - -60) * stage.bandIn)
        Rectangle { anchors.fill: parent; color: Qt.rgba(0.02, 0.016, 0.012, 0.85) }
        Hazard {
          anchors.fill: parent
          anchors.topMargin: 3 * stage.u; anchors.bottomMargin: 3 * stage.u
          color: root.cfg.band
          stripe: 15 * stage.u
          phase: stage.scroll * stage.u
        }
      }
      Item {
        id: bottomBand
        x: 0; width: parent.width
        height: 34 * stage.u
        y: stage.sy(860 + (638 - 860) * stage.bandIn)
        Rectangle { anchors.fill: parent; color: Qt.rgba(0.02, 0.016, 0.012, 0.85) }
        Hazard {
          anchors.fill: parent
          anchors.topMargin: 3 * stage.u; anchors.bottomMargin: 3 * stage.u
          color: root.cfg.band
          stripe: 15 * stage.u
          phase: -stage.scroll * stage.u
        }
      }

      // ----------------------------------------------------------- strip
      Item {
        id: strip
        visible: root.slammed
        x: 0; width: parent.width
        y: stage.sy(166); height: 468 * stage.u

        Rectangle { anchors.fill: parent; color: Qt.rgba(0.02, 0.004, 0.0, 0.94) }
        Rectangle { width: parent.width; height: 3 * stage.u; color: root.cfg.band }
        Rectangle { width: parent.width; height: 3 * stage.u; anchors.bottom: parent.bottom; color: root.cfg.band }

        // CRT scanlines, painted once.
        Canvas {
          anchors.fill: parent
          opacity: 0.35
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onPaint: {
            var g = getContext("2d")
            g.reset()
            g.fillStyle = "#000000"
            var step = Math.max(2, 3 * stage.u)
            for (var yy = 0; yy < height; yy += step) g.fillRect(0, yy, width, Math.max(1, stage.u))
          }
        }
      }

      // Full-screen slam flash (two frames on the downbeat).
      Rectangle {
        anchors.fill: parent
        visible: root.t >= root.t0 && root.t < root.t0 + 0.07
        color: root.cfg.accent
        opacity: 0.28
      }

      // ------------------------------------------------ design-space layer
      Item {
        id: design
        visible: root.slammed
        x: stage.ox; y: stage.oy
        width: 1280 * stage.u; height: 800 * stage.u
        readonly property real u: stage.u

        // Header row: knocked-out tab + typed mono line.
        Row {
          x: 230 * design.u; y: 180 * design.u
          spacing: 12 * design.u
          Item {
            width: tabRow.implicitWidth + 22 * design.u
            height: 22 * design.u
            Chamfer {
              anchors.fill: parent
              cuts: [0, 12 * design.u, 0, 0]
              fillColor: root.cfg.tabColor
            }
            Row {
              id: tabRow
              x: 9 * design.u
              anchors.verticalCenter: parent.verticalCenter
              spacing: 8 * design.u
              Text {
                text: root.cfg.tab
                color: root.pal.ink
                font.family: root.mono; font.weight: Font.Bold
                font.pixelSize: 12 * design.u; font.letterSpacing: 2 * design.u
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: root.cfg.tabJp
                color: root.pal.ink
                font.family: root.jpSans; font.weight: Font.Black
                font.pixelSize: 13 * design.u
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 820 * design.u - x
            elide: Text.ElideRight
            text: root.cfg.sub.substring(0, Math.max(0, Math.floor((root.t - root.t0) * 90)))
                  + ((root.frame % 2) ? "_" : "")
            color: root.cfg.accent
            font.family: root.mono; font.weight: Font.DemiBold
            font.pixelSize: 11.5 * design.u; font.letterSpacing: 2 * design.u
          }
        }

        // -------------------------------------------------- the warning box
        Item {
          id: box
          x: 230 * design.u; y: 212 * design.u
          width: 820 * design.u; height: 322 * design.u
          transformOrigin: Item.Center
          scale: (root.t < root.t0 + 0.07) ? 1.08 : (root.kick && !root.lastBeat ? 1.012 : 1)
          readonly property color ink: root.inv ? root.pal.ink : root.cfg.accent
          readonly property real u: design.u

          Chamfer {
            anchors.fill: parent
            cut: 22 * box.u
            fillColor: root.inv ? root.cfg.accent : root.cfg.panelFill
            strokeColor: root.cfg.accent
            strokeWidth: 3 * box.u
          }
          Chamfer {
            anchors.fill: parent
            anchors.margins: 8 * box.u
            cut: 17 * box.u
            strokeColor: root.inv ? root.pal.ink : Qt.alpha(root.cfg.accent, 0.5)
            strokeWidth: Math.max(1, 1 * box.u)
          }
          Hazard {
            x: 22 * box.u; y: 20 * box.u
            width: parent.width - 44 * box.u; height: 26 * box.u
            color: box.ink
            stripe: 12 * box.u
            phase: stage.scroll * box.u
          }
          Hazard {
            x: 22 * box.u; y: parent.height - 46 * box.u
            width: parent.width - 44 * box.u; height: 26 * box.u
            color: box.ink
            stripe: 12 * box.u
            phase: -stage.scroll * box.u
          }

          // Title card word
          Condensed {
            id: title
            anchors.horizontalCenter: parent.horizontalCenter
            y: 42 * box.u
            text: root.cfg.title
            size: 176 * box.u
            maxWidth: 500 * box.u
            squeeze: 0.56
            color: root.inv ? root.pal.ink : root.cfg.titleColor
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 222 * box.u
            text: root.cfg.jp
            visible: text !== ""
            color: box.ink
            font.family: root.jpSerif; font.weight: Font.Black
            font.pixelSize: 32 * box.u
          }

          // Left stamp
          Column {
            x: 30 * box.u; y: 62 * box.u
            spacing: 4 * box.u
            Text {
              text: root.cfg.leftLabel
              color: box.ink
              font.family: root.mono; font.weight: Font.Bold
              font.pixelSize: 11 * box.u; font.letterSpacing: 3 * box.u
            }
            SevenSeg {
              text: root.cfg.leftValue
              digitHeight: Math.min(60 * box.u, 104 * box.u / (Math.max(1, root.cfg.leftValue.length) * 0.66 + 0.15))
              color: root.inv ? root.pal.ink : root.cfg.numColor
              showDim: !root.inv
              dimColor: Qt.alpha(root.cfg.numColor, 0.1)
            }
            Item { width: 1; height: 4 * box.u }
            Text {
              text: root.cfg.leftJp
              color: box.ink
              font.family: root.jpSans; font.weight: Font.Bold
              font.pixelSize: 14 * box.u
            }
            Text {
              text: root.cfg.leftJp2
              color: box.ink
              font.family: root.jpSans; font.weight: Font.Bold
              font.pixelSize: 14 * box.u
            }
          }

          // Right stamp
          Column {
            anchors.right: parent.right
            anchors.rightMargin: 30 * box.u
            y: 62 * box.u
            spacing: 4 * box.u
            Text {
              anchors.right: parent.right
              text: root.cfg.rightLabel
              color: box.ink
              font.family: root.mono; font.weight: Font.Bold
              font.pixelSize: 11 * box.u; font.letterSpacing: 3 * box.u
            }
            SevenSeg {
              anchors.right: parent.right
              visible: root.cfg.rightMode === "count"
              text: (Math.max(0, root.beatIndex) + 1 < 10 ? "0" : "") + (Math.max(0, root.beatIndex) + 1)
              digitHeight: 60 * box.u
              color: root.inv ? root.pal.ink : root.cfg.numColor
              showDim: !root.inv
              dimColor: Qt.alpha(root.cfg.numColor, 0.1)
            }
            // Segmented meter (battery / sync level), blinking its lit cells.
            Row {
              anchors.right: parent.right
              visible: root.cfg.rightMode === "meter"
              spacing: 3 * box.u
              height: 60 * box.u
              Repeater {
                model: 10
                Rectangle {
                  required property int index
                  readonly property bool lit: index < Math.max(1, Math.round(root.cfg.meter * 10))
                  anchors.bottom: parent.bottom
                  width: 6 * box.u
                  height: (22 + index * 3.8) * box.u
                  color: lit ? (root.inv ? root.pal.ink : root.cfg.numColor)
                             : (root.inv ? Qt.alpha(root.pal.ink, 0.25) : Qt.alpha(root.cfg.numColor, 0.12))
                }
              }
            }
            Item { width: 1; height: 4 * box.u }
            Text {
              anchors.right: parent.right
              text: root.cfg.rightJp
              color: box.ink
              font.family: root.jpSans; font.weight: Font.Bold
              font.pixelSize: 14 * box.u
            }
            Text {
              anchors.right: parent.right
              text: root.hexData(Math.max(0, root.beatIndex) * 7 + 3, 6)
              color: box.ink
              font.family: root.mono; font.weight: Font.DemiBold
              font.pixelSize: 11 * box.u; font.letterSpacing: 1 * box.u
            }
          }
        }

        // ------------------------------------------------------- ticker
        Item {
          id: tick
          x: 230 * design.u; y: 548 * design.u
          width: 820 * design.u; height: 26 * design.u
          readonly property real u: design.u

          Chamfer {
            id: tickTab
            width: tickTabRow.implicitWidth + 22 * tick.u
            height: parent.height
            cuts: [0, 0, 10 * tick.u, 0]
            fillColor: root.cfg.accent
          }
          Row {
            id: tickTabRow
            x: 9 * tick.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * tick.u
            Text {
              text: "MESSAGE"
              color: root.pal.ink
              font.family: root.mono; font.weight: Font.Bold
              font.pixelSize: 12 * tick.u; font.letterSpacing: 2 * tick.u
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: "通達"
              color: root.pal.ink
              font.family: root.jpSans; font.weight: Font.Black
              font.pixelSize: 13 * tick.u
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Rectangle {
            x: tickTab.width; width: parent.width - tickTab.width
            height: parent.height
            color: "transparent"
            border.color: Qt.alpha(root.cfg.accent, 0.6)
            border.width: Math.max(1, tick.u)
          }
          Item {
            id: tickClip
            x: tickTab.width + 10 * tick.u
            width: parent.width - tickTab.width - 20 * tick.u
            height: parent.height
            clip: true
            readonly property string msg: root.cfg.message + "  //  "
            Row {
              x: -((root.frame * 9 * tick.u) % Math.max(1, tickText.implicitWidth))
                 + (1 - Math.min(1, Math.max(0, (root.t - root.t0) / 0.25))) * tickClip.width
              anchors.verticalCenter: parent.verticalCenter
              Repeater {
                model: 3
                Text {
                  required property int index
                  text: tickClip.msg
                  color: root.cfg.accent
                  font.family: root.mono; font.weight: Font.DemiBold
                  font.pixelSize: 13 * tick.u; font.letterSpacing: 2 * tick.u
                }
              }
            }
            Text {
              id: tickText
              visible: false
              text: tickClip.msg
              font.family: root.mono; font.weight: Font.DemiBold
              font.pixelSize: 13 * tick.u; font.letterSpacing: 2 * tick.u
            }
          }
        }

        // Footer data line
        Text {
          x: 230 * design.u; y: 588 * design.u
          text: "第3新東京市  //  TOKYO-3  //  MAGI LINK " + root.hexData(root.frame, 8)
          color: Qt.alpha(root.cfg.accent, 0.55)
          font.family: root.jpSans; font.weight: Font.Medium
          font.pixelSize: 11 * design.u; font.letterSpacing: 1.5 * design.u
        }
        Text {
          x: 1050 * design.u - width; y: 588 * design.u
          text: "T+" + Math.max(0, root.t - root.t0).toFixed(2) + "  BEAT " + (Math.max(0, root.beatIndex) + 1) + "/" + root.beats
          color: Qt.alpha(root.cfg.accent, 0.55)
          font.family: root.mono; font.weight: Font.Medium
          font.pixelSize: 11 * design.u; font.letterSpacing: 1.5 * design.u
        }
      }
    }
  }
}
