import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// zalo.nerv-target — POSITRON RIFLE / 目標捕捉 (NERV desktop wall panel).
// A sniper scope locked on the focused window, or the last focused one: the panel only shows on
// an empty workspace, so the lock persists after focus leaves. The target glyph sits in the scope
// where the window sits on its monitor; zoom brackets snap onto it in hard steps whenever the
// desktop is revealed or the target changes/moves, then flash LOCK ON / 照準固定.
//
// Data: Quickshell.Hyprland (activeToplevel / toplevels / rawEvent) — event-driven; the window
// geometry is refreshed (hyprctl clients) only on window events. /proc is read every 2 s, and
// only while the desktop is visible: the window's PID directly (dossier), and its whole process
// tree through telemetry.sh (TARGET TELEMETRY: disk I/O, CPU, age, threads, fds). All animation pauses while windows cover the desktop.
//
// Rect: ~/.config/omarchy/nerv-wall.json panels["zalo.nerv-target"] (1280x800 reference grid).
// Show / hide:  omarchy-shell shell toggle zalo.nerv-target '{}'
//               quickshell ipc -p $OMARCHY_PATH/shell call nerv-target toggle | on | off | status | clear
Item {
  id: root

  property var shell
  property var manifest
  property string omarchyPath: ""

  readonly property string pluginId: "zalo.nerv-target"
  property bool opened: true

  // ------------------------------------------------------------------ wall-host contract
  // embedded: zalo.nerv-wall owns the window, the covered check and the one frame clock.
  property bool embedded: false
  property var wall: null
  // demo: set by zalo.nerv-wall from nerv-wall.json "demo": true — the HUD shows a fake target
  // identity (class / title / PID / address) via the shown* properties; tracking stays live.
  property bool demo: false
  signal frame(real frameTime, int currentFrame)
  readonly property bool wantFrames: live
  readonly property bool wallShown: opened
  readonly property var slotRect: wallRect
  readonly property Component face: faceComp

  function open(payloadJson) { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened; return opened ? "shown" : "hidden" }

  IpcHandler {
    target: "nerv-target"
    function toggle(): string { return root.toggle() }
    // ("show" is swallowed by the `quickshell ipc` CLI, so the verbs are on / off)
    function on(): string { root.opened = true; return "shown" }
    function off(): string { root.opened = false; return "hidden" }
    function hide(): string { return off() }
    // drop the lock (NO TARGET) until the next focus change
    function clear(): string {
      root.tgt = null; root.hasTarget = false; root.lost = false; root.tAddr = ""; root.tPid = 0
      root.phase = 0; root.field = []
      return "cleared"
    }
    function status(): string {
      return (root.opened ? "shown" : "hidden") + " target=" + (root.hasTarget ? root.tClass + " pid " + root.tPid : "none")
        + (root.lost ? " (lost)" : "") + " desktop=" + (root.desktopVisible ? "visible" : "covered")
    }
  }

  // ------------------------------------------------------------------ wall rect
  property var wallRect: ({ x: 536, y: 540, w: 368, h: 252 })
  property real refW: 1280
  property real refH: 800
  property real fillAlpha: 0.82

  function applyWall(s) {
    try {
      var j = JSON.parse(s)
      if (j.reference) { refW = j.reference.width || 1280; refH = j.reference.height || 800 }
      if (typeof j.fillAlpha === "number") fillAlpha = j.fillAlpha
      var r = j.panels ? j.panels[pluginId] : null
      if (r && r.w > 0 && r.h > 0) wallRect = { x: +r.x, y: +r.y, w: +r.w, h: +r.h }
    } catch (e) {}
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nerv-wall.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyWall(text())
  }

  // ------------------------------------------------------------------ desktop visibility
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
  readonly property bool live: opened && desktopVisible

  onLiveChanged: {
    if (live) {
      now = Date.now()
      if (tgt) tTitle = tgt.title || tTitle
      refreshSoon()
      startSnap()
      sampleProc()
      sampleTelemetry()
    } else if (phase === 1 || phase === 2) {
      // covered mid-snap: land it now (the frame clock is about to stop)
      br = tn; phase = hasTarget ? 3 : 0
    }
  }

  // ------------------------------------------------------------------ target state
  property var tgt: null                 // HyprlandToplevel (null once destroyed)
  property bool hasTarget: false
  property string tClass: ""
  property string tTitle: ""
  property string tAddr: ""
  property int tPid: 0
  property string tWs: ""
  property int tWsId: 0
  property var tGeom: [0, 0, 0, 0]
  property bool tFloating: false
  property int tFull: 0
  property bool tXway: false
  property int tMonId: -1
  property bool lost: false
  property real lockAt: 0
  property real lostAt: 0
  property var tn: [0.4, 0.4, 0.2, 0.2]   // target rect, normalized to its monitor
  property var field: []                  // the other windows on the target's workspace (normalized)
  property real aspect: 1.6
  property real monW: 1280               // the target's monitor, logical px
  property real monH: 800
  readonly property int targets: Hyprland.toplevels.values.length
  // what the HUD displays (real values, or demo fakes)
  readonly property string shownClass: demo ? "UNIT-01" : tClass
  readonly property string shownTitle: demo ? "EVA-TEST-TYPE // 初号機 SYNC TEST" : tTitle
  readonly property string shownAddr: demo ? "0x0000EVA1" : tAddr
  readonly property int shownPid: demo ? (tPid > 0 ? 4001 : 0) : tPid

  // time on target (s): counts from acquisition, frozen when the target is destroyed
  property real now: Date.now()
  readonly property real onTarget: hasTarget ? Math.max(0, ((lost ? lostAt : now) - lockAt) / 1000) : 0
  readonly property real chargeSecs: 300
  readonly property real charge: Math.min(1, onTarget / chargeSecs)

  function acquire(t) {
    if (!t) return
    if (t !== tgt) {
      tgt = t
      hasTarget = true
      lost = false
      lockAt = Date.now()
      tTitle = t.title || ""
      tPid = 0
      cpuPrev = null; cpu = -1; rss = -1; comm = ""
      readSnap()
      if (live) startSnap()
    }
    refreshSoon()
  }

  function monFor(id) {
    var ms = Hyprland.monitors.values, m = null
    for (var i = 0; i < ms.length; i++) if (ms[i].id === id) m = ms[i]
    if (!m) m = Hyprland.focusedMonitor
    if (!m) return { x: 0, y: 0, w: 1280, h: 800 }
    var s = m.scale > 0 ? m.scale : 1
    return { x: m.x, y: m.y, w: Math.max(1, m.width / s), h: Math.max(1, m.height / s) }
  }

  function readSnap() {
    if (!tgt) return
    if (live || tTitle === "") tTitle = tgt.title || tTitle
    var o = tgt.lastIpcObject
    if (!o || !o.at || !o.size) return
    tAddr = String(o.address || "")
    tClass = String(o.class || o.initialClass || "")
    if ((o.pid || 0) !== tPid) { tPid = o.pid || 0; cpuPrev = null; cpu = -1; rss = -1 }
    tWs = o.workspace ? String(o.workspace.name) : ""
    tWsId = o.workspace ? o.workspace.id : 0
    tGeom = [o.at[0], o.at[1], o.size[0], o.size[1]]
    tFloating = !!o.floating
    tFull = o.fullscreen || 0
    tXway = !!o.xwayland
    tMonId = o.monitor
    recomputeField()
  }

  function recomputeField() {
    var m = monFor(tMonId)
    aspect = m.w / m.h
    monW = m.w; monH = m.h
    function N(at, sz) { return [(at[0] - m.x) / m.w, (at[1] - m.y) / m.h, sz[0] / m.w, sz[1] / m.h] }
    var n = N([tGeom[0], tGeom[1]], [tGeom[2], tGeom[3]])
    var moved = Math.abs(n[0] - tn[0]) + Math.abs(n[1] - tn[1]) + Math.abs(n[2] - tn[2]) + Math.abs(n[3] - tn[3]) > 0.002
    tn = n
    var f = [], tl = Hyprland.toplevels.values
    for (var i = 0; i < tl.length; i++) {
      if (tl[i] === tgt) continue
      var o = tl[i].lastIpcObject
      if (!o || !o.at || !o.size || !o.workspace || o.workspace.id !== tWsId) continue
      f.push(N(o.at, o.size))
    }
    field = f
    if (moved) { if (live && phase !== 1) startSnap(true); else if (!live) br = tn }
  }

  function checkAlive() {
    if (!hasTarget) return
    var alive = tgt !== null && tgt !== undefined && Hyprland.toplevels.values.indexOf(tgt) >= 0
    if (!alive && !lost) { lost = true; lostAt = Date.now(); tgt = null }
  }

  // seed from focus history at startup (focusHistoryID 0 = most recently focused)
  function seed() {
    if (hasTarget) return
    if (Hyprland.activeToplevel) { acquire(Hyprland.activeToplevel); return }
    var tl = Hyprland.toplevels.values, best = null, bh = 1e9
    for (var i = 0; i < tl.length; i++) {
      var o = tl[i].lastIpcObject
      if (o && o.focusHistoryID !== undefined && o.focusHistoryID < bh) { bh = o.focusHistoryID; best = tl[i] }
    }
    if (best) acquire(best)
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { root.acquire(Hyprland.activeToplevel) }
    function onRawEvent(ev) {
      var n = ev.name
      if (n === "openwindow" || n === "closewindow" || n === "movewindowv2" || n === "changefloatingmode"
          || n === "fullscreen" || n === "activewindowv2" || n === "moveworkspacev2" || n === "pin")
        root.refreshSoon()
    }
  }
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.checkAlive() }
  }
  Connections {
    target: root.tgt
    ignoreUnknownSignals: true
    function onLastIpcObjectChanged() { root.readSnap() }
    // titles can animate (spinners): only re-layout while the desktop is visible
    function onTitleChanged() { if (root.tgt && root.live) root.tTitle = root.tgt.title }
  }

  function refreshSoon() { refreshDebounce.restart() }
  Timer {
    id: refreshDebounce
    interval: 150
    onTriggered: { Hyprland.refreshToplevels(); postRefresh.restart() }
  }
  Timer {
    id: postRefresh
    interval: 250
    onTriggered: { root.checkAlive(); root.readSnap() }
  }
  Timer {
    id: seedTimer
    interval: 600
    onTriggered: root.seed()
  }
  Component.onCompleted: { Hyprland.refreshToplevels(); seedTimer.start() }

  // ------------------------------------------------------------------ bracket snap + lock flash
  // phase: 0 idle (no target) · 1 snapping · 2 LOCK ON flash · 3 locked
  // The snap is DELIBERATELY stepped (that hard snap is the style), but its steps are clocked by
  // the vsync frame clock: each snap step holds exactly 4 frames (66.7 ms @ 60 Hz), each flash
  // step 6 frames (100 ms), so the steps land evenly instead of on a drifting Timer.
  property int phase: 0
  property var br: [-0.1, -0.16, 1.2, 1.32]
  property var brFrom: [-0.1, -0.16, 1.2, 1.32]
  property int snapStep: 0
  property int flashStep: 0
  readonly property int snapSteps: 6
  readonly property real snapDt: 4 / 60
  readonly property real flashDt: 6 / 60
  property real snapT0: -1               // frame-clock time of step 0 (-1: next frame)

  function startSnap(fromCurrent) {
    if (!hasTarget) { phase = 0; return }
    if (!live) { br = tn; phase = 3; return }
    brFrom = fromCurrent ? br : [-0.1, -0.16, 1.2, 1.32]
    br = brFrom
    snapStep = 0
    flashStep = 0
    snapT0 = -1
    phase = 1
  }
  function stepSnap(el) {
    if (phase !== 1 && phase !== 2) return
    if (snapT0 < 0) snapT0 = el
    // +8 ms bias: step boundaries fall between frames, never on a vsync edge (no 3/5-frame jitter)
    var k = Math.floor((el - snapT0 + 0.008) / snapDt)
    if (phase === 1) {
      var s = Math.min(snapSteps, k)
      if (s !== snapStep) {
        snapStep = s
        var q = s / snapSteps, e = 1 - (1 - q) * (1 - q)
        var a = brFrom, b = tn
        br = s >= snapSteps ? tn : [a[0] + (b[0] - a[0]) * e, a[1] + (b[1] - a[1]) * e, a[2] + (b[2] - a[2]) * e, a[3] + (b[3] - a[3]) * e]
      }
      if (s >= snapSteps) { phase = 2; flashStep = 0; snapT0 = snapT0 + snapSteps * snapDt }
    } else {
      var f = Math.floor((el - snapT0 + 0.008) / flashDt)
      if (f >= 9) { phase = 3; flashStep = 0 }
      else if (f !== flashStep) flashStep = f
    }
  }
  onTnChanged: if (phase === 3 || phase === 0) br = tn

  // ------------------------------------------------------------------ clocks (paused when covered)
  // stepped: blink + readout refresh at 2 Hz
  property int tick: 0
  property bool blinkOn: true
  Timer {
    interval: 500
    repeat: true
    running: root.live
    onTriggered: { root.blinkOn = !root.blinkOn; root.tick += 1; root.now = Date.now() }
  }
  // continuous: one vsync FrameAnimation drives glyph spin, search sweep, the charge fill, the
  // hex line scroll and the snap step clock. Stopped when covered or hidden.
  property real spin: 0                  // radians, 1.44 rad/s
  property real fclock: 0                // seconds of visible motion
  property real frameNow: Date.now()     // wall clock, per frame (charge meter)
  FrameAnimation {
    running: !root.embedded && root.live
    onTriggered: root.frame(frameTime, currentFrame)
  }
  onFrame: (frameTime, currentFrame) => {
    {
      var dt = Math.min(0.1, frameTime)
      root.fclock += dt
      root.spin = (root.spin + dt * 1.44) % (Math.PI * 2)
      root.frameNow = Date.now()
      root.stepSnap(root.fclock)
    }
  }
  readonly property real chargeLive: hasTarget ? Math.min(1, Math.max(0, ((lost ? lostAt : frameNow) - lockAt) / 1000) / chargeSecs) : 0

  // ------------------------------------------------------------------ /proc sampling (2 s, visible only)
  property var cpuPrev: null
  property real cpu: -1
  property real rss: -1
  property string comm: ""
  property int threads: 0

  // the window's own process (dossier PID / THR / CPU / RSS rows)
  FileView { id: fStat; path: root.tPid > 0 ? "/proc/" + root.tPid + "/stat" : ""; blockLoading: true; printErrors: false }
  FileView { id: fStatus; path: root.tPid > 0 ? "/proc/" + root.tPid + "/status" : ""; blockLoading: true; printErrors: false }

  function sampleProc() {
    if (tPid <= 0 || lost) return
    fStat.reload()
    var s = fStat.text()
    var rp = s.lastIndexOf(")")
    if (rp < 0) { cpu = -1; return }
    comm = s.substring(s.indexOf("(") + 1, rp)
    var f = s.substring(rp + 2).split(" ")
    var ticks = (+f[11]) + (+f[12]), t = Date.now()
    threads = +f[17] || 0
    if (cpuPrev && cpuPrev.pid === tPid && t > cpuPrev.t) cpu = Math.max(0, (ticks - cpuPrev.ticks) / 100 / ((t - cpuPrev.t) / 1000) * 100)
    cpuPrev = { pid: tPid, ticks: ticks, t: t }
    fStatus.reload()
    var m = /VmRSS:\s+(\d+)/.exec(fStatus.text())
    rss = m ? +m[1] : -1
  }

  // target telemetry: the target's whole process tree (root = the window's PID), sampled by
  // telemetry.sh (one gawk pass over /proc/*/stat + /proc/<pid>/io, fd globs). Rates are per-PID
  // deltas summed over PIDs present in both samples, so children appearing / exiting don't spike.
  property int tmProcs: 0
  property int tmThreads: 0
  property int tmFds: 0
  property real tmAge: -1                // s since the root process started
  property real tmCpuTime: -1            // s of CPU consumed by the live tree (utime+stime)
  property real tmCpu: -1                // % of one core, tree
  property real tmRead: -1               // B/s actually read from storage (io read_bytes)
  property real tmWrite: -1              // B/s written to storage (io write_bytes)
  property var tmPrev: null              // { root, t, per: { pid: [rb, wb, ticks] } }

  function resetTelemetry() {
    tmProcs = 0; tmThreads = 0; tmFds = 0; tmAge = -1; tmCpuTime = -1
    tmCpu = -1; tmRead = -1; tmWrite = -1; tmPrev = null
  }
  onTPidChanged: resetTelemetry()

  function parseTelemetry(txt, pid, t) {
    if (pid !== tPid) return
    var lines = txt.split("\n"), up = -1, per = {}, n = 0, thr = 0, fds = 0, ticks = 0, age = -1
    var prev = tmPrev && tmPrev.root === pid ? tmPrev : null
    var dr = 0, dw = 0, dt = 0
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split(" ")
      if (f[0] === "T") up = +f[1]
      else if (f[0] === "P" && f.length >= 8) {
        var rb = +f[2], wb = +f[3], tk = +f[4]
        per[f[1]] = [rb, wb, tk]
        n++; thr += +f[5]; fds += +f[7]; ticks += tk
        if (n === 1 && up >= 0) age = up - (+f[6]) / 100
        var o = prev ? prev.per[f[1]] : null
        if (o) { dr += Math.max(0, rb - o[0]); dw += Math.max(0, wb - o[1]); dt += Math.max(0, tk - o[2]) }
      }
    }
    if (n === 0) { resetTelemetry(); return }
    tmProcs = n; tmThreads = thr; tmFds = fds; tmAge = age; tmCpuTime = ticks / 100
    if (prev && t > prev.t) {
      var secs = (t - prev.t) / 1000
      tmRead = dr / secs; tmWrite = dw / secs; tmCpu = dt / 100 / secs * 100
    }
    tmPrev = { root: pid, t: t, per: per }
  }

  Process {
    id: teleProc
    property int pid: 0
    property real t0: 0
    command: [Qt.resolvedUrl("telemetry.sh").toString().replace("file://", ""), String(pid)]
    stdout: StdioCollector { onStreamFinished: root.parseTelemetry(text, teleProc.pid, teleProc.t0) }
  }
  function sampleTelemetry() {
    if (tPid <= 0 || lost || teleProc.running) return
    teleProc.pid = tPid
    teleProc.t0 = Date.now()
    teleProc.running = true
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.live
    onTriggered: { root.sampleProc(); root.sampleTelemetry() }
  }

  // ------------------------------------------------------------------ face (window-free content)
  Component {
    id: faceComp
    Item {
      id: face
      property real sx: 1
      property real sy: 1
      property real dpr: 1

      TargetHud {
        id: hud
        hud: root
        readonly property real k: Math.max(0.01, Math.min(face.width / 368, face.height / 252))
        pxScale: k * face.dpr
        width: face.width / k
        height: face.height / k
        transform: Scale { xScale: hud.k; yScale: hud.k }
      }

      // CRT scanlines over everything (painted once)
      Canvas {
        anchors.fill: parent
        opacity: 0.9
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var c = getContext("2d")
          c.reset()
          c.clearRect(0, 0, width, height)
          c.fillStyle = "rgba(0,0,0,0.26)"
          for (var y = 0; y < height; y += 2) c.fillRect(0, y + 1, width, 0.7)
        }
      }
    }
  }

  // ------------------------------------------------------------------ standalone: one wall window per screen
  Variants {
    model: root.embedded ? [] : Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: root.opened

      readonly property real sx: (modelData ? modelData.width : 1280) / root.refW
      readonly property real sy: (modelData ? modelData.height : 800) / root.refH

      color: "transparent"
      anchors { top: true; left: true }
      margins { top: Math.round(root.wallRect.y * sy); left: Math.round(root.wallRect.x * sx) }
      implicitWidth: Math.round(root.wallRect.w * sx)
      implicitHeight: Math.round(root.wallRect.h * sy)

      WlrLayershell.namespace: "zalo-nerv-target"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
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
