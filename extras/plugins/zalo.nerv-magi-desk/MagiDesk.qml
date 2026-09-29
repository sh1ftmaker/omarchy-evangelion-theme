import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Palette.js" as Pal
import "Stats.js" as Stats

// zalo.nerv-magi-desk — the MAGI deliberation screen as an always-on desktop-wall panel.
// MELCHIOR·1 = CPU, BALTHASAR·2 = memory, CASPER·3 = GPU. Same probes/vote logic as the
// zalo.nerv-magi bar widget (copied, not imported, so hot reload of either never breaks
// the other). Rect comes from ~/.config/omarchy/nerv-wall.json (watched), drawn on
// WlrLayer.Bottom, click-through, no focus, no exclusive zone. All polling and animation
// stops while every screen's active workspace holds windows (the wall is covered).
//
// Show / hide:  omarchy-shell shell toggle zalo.nerv-magi-desk '{}'
//               omarchy-shell nerv-magi-desk toggle | show | hide | status
Item {
  id: root

  // host injection
  property var shell
  property var manifest
  property var pluginRegistry
  property var barWidgetRegistry
  property string omarchyPath: ""

  readonly property string pluginId: "zalo.nerv-magi-desk"
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")

  property bool opened: true

  // ------------------------------------------------------------ wall-host contract
  // embedded: zalo.nerv-wall owns the window, the covered check and the one frame clock
  // (it emits frame() while wantFrames); MagiScreen listens to frame() instead of its own clock.
  property bool embedded: false
  property var wall: null
  property bool demo: false   // wall "demo" flag: this panel shows nothing identifying, so no-op
  signal frame(real frameTime, int currentFrame)
  readonly property bool wantFrames: live
  readonly property bool wallShown: opened
  readonly property var slotRect: rect
  readonly property Component face: faceComp
  function open(payloadJson) { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened; return opened ? "shown" : "hidden" }

  IpcHandler {
    target: "nerv-magi-desk"
    function toggle(): string { return root.toggle() }
    function show(): string { root.opened = true; return "shown" }
    function hide(): string { root.opened = false; return "hidden" }
    function status(): string { return root.opened ? (root.desktopVisible ? "shown" : "shown (paused)") : "hidden" }
  }

  // ------------------------------------------------------------ wall rect
  property var rect: ({ x: 8, y: 34, w: 520, h: 422 })
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
      var d
      try { d = JSON.parse(text()) } catch (e) { console.warn("nerv-magi-desk: bad nerv-wall.json:", e); return }
      if (d.reference) { root.refW = d.reference.width || 1280; root.refH = d.reference.height || 800 }
      if (d.fillAlpha !== undefined) root.fillAlpha = Number(d.fillAlpha)
      var r = d.panels ? d.panels[root.pluginId] : null
      if (r && r.w > 0 && r.h > 0) root.rect = { x: r.x || 0, y: r.y || 0, w: r.w, h: r.h }
    }
  }

  // ------------------------------------------------------------ covered?
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
  onLiveChanged: if (live) refresh(true)

  // ------------------------------------------------------------ live state
  property real cpu: 0
  property var cores: []
  property var prevStat: ({})
  property real memTotal: 0
  property real memUsed: 0
  property real memCache: 0
  property real swapTotal: 0
  property real swapUsed: 0
  readonly property real mem: memTotal > 0 ? memUsed / memTotal : 0
  property var gpu: ({ src: "wait", util: 0, used: 0, total: 0, temp: NaN, power: NaN, name: "" })
  readonly property real gpuLoad: (gpu.src === "nvidia" || gpu.src === "amdgpu") ? Math.min(1, gpu.util / 100)
    : (gpu.src === "sleep" ? 0 : -1)
  property real cpuTemp: NaN
  property string tempPath: ""
  property real uptime: 0
  property var loadAvg: ["0.00", "0.00", "0.00"]
  property string procs: ""
  readonly property var loads: [cpu, mem, gpuLoad]

  // ------------------------------------------------------- deliberation
  property int query: 0
  property var votes: [null, null, null]
  property var flips: [false, false, false]
  property var history: [[], [], []]
  property int totalOk: 0
  property int totalNo: 0
  property int tick: 0
  readonly property int histMax: 16
  readonly property int logMax: 24
  property var logRows: []
  property int logSeq: 0          // rows ever pushed: the screen scrolls the log by the delta

  function pushLog(text, kind) {
    var rows = logRows.slice(Math.max(0, logRows.length - logMax + 1))
    rows.push({ t: text, k: kind })
    logRows = rows
    logSeq++
  }

  function castVotes() {
    var g = gpuLoad
    var next = [
      cpu < Pal.VOTE,
      mem < Pal.VOTE,
      g < 0 ? null : (g < Pal.VOTE && !(gpu.temp >= 85))
    ]
    var f = [false, false, false]
    var h = [history[0].slice(1 - histMax), history[1].slice(1 - histMax), history[2].slice(1 - histMax)]
    var ok = 0, no = 0
    for (var i = 0; i < 3; i++) {
      f[i] = votes[i] !== null && next[i] !== votes[i]
      h[i].push(next[i])
      if (next[i] === true) ok++
      else if (next[i] === false) no++
    }
    totalOk += ok
    totalNo += no
    query++
    history = h
    flips = f
    votes = next

    var names = ["MEL-1", "BAL-2", "CAS-3"]
    for (var j = 0; j < 3; j++)
      if (f[j]) pushLog(names[j] + (next[j] ? " 承認 " : " 否決 ") + Stats.pct(loads[j]), next[j] ? "ok" : "no")
    pushLog("Q" + Stats.pad(query % 10000, 4) + " DELIB " + ok + ":" + no, ok > no ? "ok" : (no > ok ? "no" : "sys"))
  }

  function refresh(full) {
    statFile.reload()
    memFile.reload()
    if (full) {
      uptimeFile.reload()
      loadFile.reload()
      if (tempPath !== "") tempFile.reload()
    }
  }

  // ---------------------------------------------------------------- probes
  FileView {
    id: statFile
    path: "/proc/stat"
    printErrors: false
    onLoaded: {
      var r = Stats.parseStat(text(), root.prevStat)
      root.prevStat = r.prev
      if (!r.valid) return
      root.cpu = r.total
      root.cores = r.cores
      root.castVotes()
    }
  }
  FileView {
    id: memFile
    path: "/proc/meminfo"
    printErrors: false
    onLoaded: {
      var m = Stats.parseMeminfo(text())
      root.memTotal = m.total
      root.memUsed = m.used
      root.memCache = m.cache
      root.swapTotal = m.swapTotal
      root.swapUsed = m.swapUsed
    }
  }
  FileView {
    id: uptimeFile
    path: "/proc/uptime"
    printErrors: false
    onLoaded: root.uptime = parseFloat(text()) || 0
  }
  FileView {
    id: loadFile
    path: "/proc/loadavg"
    printErrors: false
    onLoaded: {
      var f = String(text()).trim().split(/\s+/)
      root.loadAvg = [f[0] || "0.00", f[1] || "0.00", f[2] || "0.00"]
      root.procs = f[3] || ""
    }
  }
  FileView {
    id: tempFile
    path: root.tempPath
    printErrors: false
    onLoaded: {
      var v = parseFloat(text())
      root.cpuTemp = isFinite(v) ? v / 1000 : NaN
    }
  }
  // CPU package sensor, located once (hwmon numbering is not stable)
  Process {
    id: tempProbe
    command: ["bash", "-c",
      "for h in /sys/class/hwmon/hwmon*; do n=$(cat \"$h/name\" 2>/dev/null); "
      + "case $n in k10temp|coretemp|zenpower|cpu_thermal|x86_pkg_temp) [ -r \"$h/temp1_input\" ] && { echo \"$h/temp1_input\"; exit 0; };; esac; done; "
      + "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat \"$h/name\" 2>/dev/null)\" = acpitz ] && [ -r \"$h/temp1_input\" ] && { echo \"$h/temp1_input\"; exit 0; }; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { root.tempPath = String(text).trim(); if (root.tempPath !== "") tempFile.reload() }
    }
  }
  // CASPER·3: gpu.sh reports "sleep" (and never opens the device) unless the dGPU is
  // already runtime-active, so this can't wake it; the slow cadence keeps nvidia-smi
  // from pinning it awake either.
  Process {
    id: gpuProc
    command: ["bash", root.pluginDir + "/gpu.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.gpu = Stats.parseGpu(text)
    }
  }

  Timer {
    interval: 2000
    running: root.live
    repeat: true
    onTriggered: root.refresh(true)
  }
  Timer {
    interval: 8000
    running: root.live
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!gpuProc.running) gpuProc.running = true
  }
  // hard-stepped data clock: hex log filler, vote-flip flash, blink (2.5 fps). Continuous motion
  // (bus packets, log scroll, hex shimmer) runs on the screen's vsync FrameAnimation instead.
  Timer {
    interval: 400
    running: root.live
    repeat: true
    onTriggered: {
      root.tick++
      if (root.flips[0] || root.flips[1] || root.flips[2]) root.flips = [false, false, false]
      var tags = ["SYNC", "PARSE", "QUERY", "CACHE", "LINK", "EVAL"]
      root.pushLog(Stats.hexOf(0x3F00 + root.tick * 16, 4) + " " + tags[root.tick % 6] + " " + Stats.hexStr(4), "hex")
    }
  }

  Component.onCompleted: {
    var boot = ["MAGI SYSTEM BOOT", "LINK MELCHIOR·1", "LINK BALTHASAR·2", "LINK CASPER·3", "人格移植OS OK"]
    for (var i = 0; i < 12; i++) pushLog(Stats.hexOf(0x3A00 + i * 16, 4) + " " + Stats.hexStr(6), "hex")
    for (var b = 0; b < boot.length; b++) pushLog(boot[b], "sys")
    tempProbe.running = true
    refresh(true)   // seeds the CPU delta; first real sample lands one interval later
  }

  // ------------------------------------------------------------ face (window-free content)
  Component {
    id: faceComp
    Item {
      id: face
      property real sx: 1
      property real sy: 1
      property real dpr: 1
      MagiScreen {
        magi: root
        width: root.rect.w
        height: root.rect.h
        fillAlpha: root.fillAlpha
        pxScale: Math.max(face.sx, face.sy) * face.dpr
        transform: Scale { xScale: face.sx; yScale: face.sy }
      }
    }
  }

  // standalone clock (the wall host drives frame() when embedded)
  FrameAnimation {
    running: !root.embedded && root.live
    onTriggered: root.frame(frameTime, currentFrame)
  }

  // ------------------------------------------------------------ standalone: one window per screen
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

      WlrLayershell.namespace: "zalo-nerv-magi-desk"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
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
