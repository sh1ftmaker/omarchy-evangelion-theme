import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// zalo.nerv-seele: SOUND ONLY / 人類補完委員会. NERV desktop-wall panel.
// The 12 hungriest processes sit on the council as SEELE monoliths; each slab's red text, edge
// glow and voice meter follow that process's live CPU (from /proc jiffy deltas, council.py).
// Seats are sticky (a member keeps its number until it exits or is clearly out-consumed) and
// the member with the most CPU "has the floor": bracketed, lit, its CPU history drawn as a
// voice print. Rect comes from ~/.config/omarchy/nerv-wall.json (entry "zalo.nerv-seele").
// Layer Bottom (above the wallpaper, below windows), click-through, no focus, no exclusive zone.
// Motion runs at the display refresh rate (one vsync-locked FrameAnimation clock `t`, plus
// NumberAnimations for eased levels / cross-fades) while data is sampled every 2 s; values
// ease between samples and all per-frame work is GPU-side (opacity, clip, x, one shader).
// Animation stops while every screen's workspace has windows, and the helper slows to 5 s.
//
// Show / hide:  omarchy-shell shell toggle zalo.nerv-seele '{}'
//               omarchy-shell nerv-seele toggle | show | hide | status
Item {
  id: root

  property var shell
  property var manifest
  property string omarchyPath: ""

  property bool opened: true

  // ---------------------------------------------------------------- wall-host contract
  // embedded: zalo.nerv-wall owns the window, the covered check and the one frame clock.
  property bool embedded: false
  property var wall: null
  // demo: set by zalo.nerv-wall from nerv-wall.json "demo": true — the council is a fixed fake
  // roster with synthetic, wandering CPU (no real process names / PIDs); totals stay live.
  property bool demo: false
  onDemoChanged: { hasData = false; demoSpeaker = -1 }
  signal frame(real frameTime, int currentFrame)
  readonly property bool wantFrames: animate
  readonly property bool wallShown: opened
  readonly property var slotRect: rect
  readonly property Component face: faceComp

  // ---------------------------------------------------------------- wall rect
  readonly property var defaultRect: ({ x: 536, y: 282, w: 368, h: 250 })
  property var rect: defaultRect
  property real refW: 1280
  property real refH: 800
  property real fillAlpha: 0.82

  FileView {
    id: wallFile
    path: Quickshell.env("HOME") + "/.config/omarchy/nerv-wall.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var j = JSON.parse(text())
        var r = j.panels && j.panels["zalo.nerv-seele"]
        root.rect = (r && r.w > 0 && r.h > 0) ? { x: r.x, y: r.y, w: r.w, h: r.h } : root.defaultRect
        if (j.reference) { root.refW = j.reference.width || 1280; root.refH = j.reference.height || 800 }
        if (j.fillAlpha !== undefined) root.fillAlpha = j.fillAlpha
      } catch (e) {
        root.rect = root.defaultRect
      }
    }
    onLoadFailed: root.rect = root.defaultRect
  }

  // ---------------------------------------------------------------- live data
  property var seats: []
  property int speaker: -1
  property var hist: []
  property int procs: 0
  property int threads: 0
  property real machine: 0
  property int ncpu: 1
  property var log: []
  property bool hasData: false

  readonly property var spk: (speaker >= 0 && speaker < seats.length) ? seats[speaker] : null

  function ingest(line) {
    var d
    try { d = JSON.parse(line) } catch (e) { return }
    if (demo) d = demoData(d)
    seats = d.seats || []
    speaker = d.speaker
    hist = d.hist || []
    procs = d.procs || 0
    threads = d.threads || 0
    machine = d.machine || 0
    ncpu = d.ncpu || 1
    log = d.log || []
    // sample cadence for the voice-print scroll (measured in animation time)
    if (hasData && t > sampleT) sampleDt = Math.max(0.8, Math.min(6, sampleDt * 0.5 + (t - sampleT) * 0.5))
    sampleT = t
    hasData = true
  }

  // ---------------------------------------------------------------- demo roster
  readonly property var demoRoster: [
    ["magi", 1101, 38, 410e6, 24], ["hyprland", 1187, 22, 190e6, 12], ["firefox", 2204, 16, 820e6, 96],
    ["lcl-pump", 1312, 12, 64e6, 4], ["entry-plug", 1420, 9, 120e6, 8], ["a10-nerve", 1466, 7, 48e6, 6],
    ["at-field", 1538, 5, 36e6, 3], ["pipewire", 1003, 4, 28e6, 5], ["umbilical", 1611, 3, 22e6, 2],
    ["dummy-plug", 1702, 2, 18e6, 2], ["kernel-dogma", 1788, 1.5, 12e6, 1], ["lilin-scan", 1845, 1, 9e6, 1]
  ]
  property int demoSpeaker: -1
  function demoCpu(i, t) {
    var r = demoRoster[i]
    return Math.max(0.1, r[2] * (0.55 + 0.45 * Math.sin(t / (9 + i * 2.3) + i * 2.1)
                                 + 0.2 * Math.sin(t / (2.7 + i * 0.4) + i)))
  }
  function demoData(d) {
    var t = Date.now() / 1000, out = [], best = 0
    for (var i = 0; i < demoRoster.length; i++) {
      var r = demoRoster[i], c = demoCpu(i, t)
      out.push({ pid: r[1], name: r[0], cpu: Math.round(c * 10) / 10,
                 now: Math.round(demoCpu(i, t - 1) * 10) / 10, rss: r[3], thr: r[4] })
      if (out[i].cpu > out[best].cpu) best = i
    }
    var log = []
    if (demoSpeaker < 0 || out[best].cpu > out[demoSpeaker].cpu * 1.3 + 0.8) demoSpeaker = best
    var hh = new Date(), stamp = two(hh.getHours()) + ":" + two(hh.getMinutes())
    for (var k = 0; k < 4; k++) {
      var m = (Math.floor(t / 20) + k) % demoRoster.length
      log.push(stamp + " [" + two(m + 1) + "] " + demoRoster[m][0].toUpperCase() + (k % 2 ? " 着席 SEATED" : " 発言中 HAS THE FLOOR"))
    }
    var hist = []
    for (var h = 63; h >= 0; h--) hist.push(Math.round(demoCpu(demoSpeaker, t - h * 2) * 10) / 10)
    d.seats = out
    d.speaker = demoSpeaker
    d.hist = hist
    d.log = log
    return d
  }

  function lvl(cpu) { return Math.max(0, Math.min(1, Math.sqrt(Math.max(0, cpu) / 100))) }
  function two(n) { return (n < 10 ? "0" : "") + n }
  function fmtBytes(b) {
    if (b >= 1073741824) return (b / 1073741824).toFixed(2) + " GiB"
    if (b >= 1048576) return (b / 1048576).toFixed(b >= 104857600 ? 0 : 1) + " MiB"
    return Math.round(b / 1024) + " KiB"
  }

  readonly property string minutes: {
    var parts = []
    if (spk) parts.push("MEMBER " + two(speaker + 1) + " [" + spk.name.toUpperCase() + "] 発言中 SPEAKING … " + spk.now.toFixed(1) + "% CPU")
    for (var i = log.length - 1; i >= 0; i--) parts.push(log[i])
    parts.push("COUNCIL " + procs + " PROC / " + threads + " THR · LOAD " + machine.toFixed(0) + "%")
    parts.push("人類補完計画 · 予定通りだ ALL IS ACCORDING TO THE SCENARIO")
    return parts.join("   ///   ") + "   ///   "
  }

  // ---------------------------------------------------------------- show / hide
  function open(payloadJson) { opened = true }
  function close() { opened = false }
  function toggle() { setOpened(!opened, true); return opened ? "shown" : "hidden" }
  function setOpened(v, persist) {
    opened = v
    if (persist) stateFile.setText(v ? "shown\n" : "hidden\n")
  }
  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/nerv-seele.state"
    printErrors: false
    onLoaded: root.opened = text().trim() !== "hidden"
  }
  IpcHandler {
    target: "nerv-seele"
    function toggle(): string { return root.toggle() }
    function show(): string { root.setOpened(true, true); return "shown" }
    function hide(): string { root.setOpened(false, true); return "hidden" }
    function status(): string { return root.opened ? "shown" : "hidden" }
  }

  // ---------------------------------------------------------------- feed
  Process {
    id: feed
    running: root.opened
    stdinEnabled: true
    command: ["python3", "-u", decodeURIComponent(Qt.resolvedUrl("council.py").toString().replace(/^file:\/\//, ""))]
    stdout: SplitParser { onRead: data => root.ingest(data) }
    stderr: SplitParser { onRead: data => console.warn("nerv-seele council:", data) }
    onRunningChanged: if (running) write(root.desktopVisible ? "active\n" : "idle\n")
    onExited: (code, status) => { if (root.opened) respawn.restart() }
  }
  Timer { id: respawn; interval: 5000; onTriggered: if (root.opened && !feed.running) feed.running = true }

  // ---------------------------------------------------------------- pause when covered
  readonly property bool desktopVisible: embedded ? (wall ? wall.desktopVisible : true) : localDesktopVisible
  readonly property bool localDesktopVisible: {
    if (embedded) return true
    var ms = Hyprland.monitors.values
    if (!ms || ms.length === 0) return true
    for (var i = 0; i < ms.length; i++) {
      var ws = ms[i].activeWorkspace
      if (!ws || !ws.toplevels || ws.toplevels.values.length === 0) return true
    }
    return false
  }
  readonly property bool animate: opened && desktopVisible
  onDesktopVisibleChanged: if (feed.running) feed.write(desktopVisible ? "active\n" : "idle\n")

  // animation clock (seconds); advances only while visible
  property real t: 0
  property real sampleT: 0
  property real sampleDt: 2.1
  readonly property real sampleProg: Math.min(1, Math.max(0, (t - sampleT) / sampleDt))
  property bool blinkOn: true
  property string clock: ""

  FrameAnimation {
    running: !root.embedded && root.animate
    onTriggered: root.frame(frameTime, currentFrame)
  }
  onFrame: (frameTime, currentFrame) => { root.t += Math.min(frameTime, 0.1) }
  // blink + session clock stay stepped (terminal-like)
  Timer {
    interval: 500
    repeat: true
    running: root.animate
    triggeredOnStart: true
    onTriggered: {
      root.blinkOn = !root.blinkOn
      var d = new Date()
      root.clock = root.two(d.getHours()) + ":" + root.two(d.getMinutes()) + ":" + root.two(d.getSeconds())
    }
  }

  // ---------------------------------------------------------------- face (window-free content)
  Component {
    id: faceComp
    Item {
      id: face
      property real sx: 1
      property real sy: 1
      property real dpr: 1
      readonly property real k: Math.min(sx, sy)

      Council {
        hud: root
        width: face.width / face.k
        height: face.height / face.k
        scale: face.k
        transformOrigin: Item.TopLeft
      }

      // CRT scanlines (painted on resize only)
      Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var c = getContext("2d")
          c.reset()
          c.fillStyle = "rgba(0,0,0,0.26)"
          for (var y = 0; y < height; y += 2) c.fillRect(0, y + 1, width, 0.7)
        }
      }
    }
  }

  // ---------------------------------------------------------------- standalone: one window per screen
  Variants {
    model: root.embedded ? [] : Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: root.opened

      readonly property real sx: modelData.width / root.refW
      readonly property real sy: modelData.height / root.refH

      color: "transparent"
      anchors { top: true; left: true }
      margins { top: Math.round(root.rect.y * sy); left: Math.round(root.rect.x * sx) }
      implicitWidth: Math.round(root.rect.w * sx)
      implicitHeight: Math.round(root.rect.h * sy)
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "zalo-nerv-seele"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      Loader {
        anchors.fill: parent
        sourceComponent: faceComp
        onLoaded: {
          item.sx = Qt.binding(() => win.sx)
          item.sy = Qt.binding(() => win.sy)
          item.dpr = Qt.binding(() => win.devicePixelRatio || 1)
        }
      }
    }
  }
}
