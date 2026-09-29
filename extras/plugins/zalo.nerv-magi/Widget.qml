import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Palette.js" as Pal
import "Stats.js" as Stats

// NERV MAGI: MELCHIOR·1 = CPU, BALTHASAR·2 = memory, CASPER·3 = GPU.
// Bar: three stepped load blocks. Left click: deliberation panel. Right click: btop.
Panel {
  id: root
  moduleName: "zalo.nerv-magi"
  // No private IPC target: `omarchy-shell shell summon|hide|toggle zalo.nerv-magi` routes here.

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    return decodeURIComponent(u.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }

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

  // ------------------------------------------------------- deliberation
  property int query: 0
  property var votes: [null, null, null]
  property var flips: [false, false, false]
  property var history: [[], [], []]
  property int totalOk: 0
  property int totalNo: 0
  property var logRows: []
  property int tick: 0
  readonly property int logMax: 30

  readonly property var loads: [cpu, mem, gpuLoad]

  readonly property string tooltip: "MAGI SYSTEM  審議\n"
    + "MELCHIOR·1   CPU " + Stats.pct(cpu) + "\n"
    + "BALTHASAR·2  MEM " + Stats.pct(mem) + "\n"
    + "CASPER·3     GPU " + (gpu.src === "sleep" ? "SLEEP" : Stats.pct(gpuLoad))

  function pushLog(text, kind) {
    var rows = logRows.slice(Math.max(0, logRows.length - logMax + 1))
    rows.push({ t: text, k: kind })
    logRows = rows
  }

  function castVotes() {
    var g = gpuLoad
    var next = [
      cpu < Pal.VOTE,
      mem < Pal.VOTE,
      g < 0 ? null : (g < Pal.VOTE && !(gpu.temp >= 85))
    ]
    var f = [false, false, false]
    var h = [history[0].slice(-15), history[1].slice(-15), history[2].slice(-15)]
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

    if (opened) {
      var names = ["MEL-1", "BAL-2", "CAS-3"]
      for (var j = 0; j < 3; j++)
        if (f[j]) pushLog(names[j] + (next[j] ? " 承認 " : " 否決 ") + Stats.pct(loads[j]), next[j] ? "ok" : "no")
      pushLog("Q" + Stats.pad(query % 10000, 4) + " DELIB " + ok + ":" + no, ok > no ? "ok" : (no > ok ? "no" : "sys"))
    }
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

  function launchBtop() {
    if (bar && typeof bar.run === "function") bar.run("omarchy-launch-or-focus-tui btop")
    else Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
  }

  onOpenedChanged: {
    if (opened) {
      if (logRows.length === 0) {
        var boot = ["MAGI SYSTEM BOOT", "LINK MELCHIOR·1", "LINK BALTHASAR·2", "LINK CASPER·3", "人格移植OS OK"]
        for (var i = 0; i < 18; i++) pushLog(Stats.hexOf(0x3A00 + i * 16, 4) + " " + Stats.hexStr(6), "hex")
        for (var b = 0; b < boot.length; b++) pushLog(boot[b], "sys")
      }
      refresh(true)
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

  // Locate the CPU package sensor once (hwmon numbering is not stable).
  Process {
    id: tempProbe
    command: ["bash", "-c",
      "for h in /sys/class/hwmon/hwmon*; do n=$(cat \"$h/name\" 2>/dev/null); "
      + "case $n in k10temp|coretemp|zenpower|cpu_thermal|x86_pkg_temp) [ -r \"$h/temp1_input\" ] && { echo \"$h/temp1_input\"; exit 0; };; esac; done; "
      + "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat \"$h/name\" 2>/dev/null)\" = acpitz ] && [ -r \"$h/temp1_input\" ] && { echo \"$h/temp1_input\"; exit 0; }; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.tempPath = String(text).trim()
    }
  }

  Process {
    id: gpuProc
    command: ["bash", root.pluginDir + "/gpu.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.gpu = Stats.parseGpu(text)
    }
  }

  Timer {
    interval: root.opened ? 1500 : 2000
    running: true
    repeat: true
    onTriggered: root.refresh(root.opened)
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!gpuProc.running) gpuProc.running = true
  }

  // hard-stepped scroll clock for the panel (log rows, ticker, bus packets)
  Timer {
    interval: 320
    running: root.opened
    repeat: true
    onTriggered: {
      root.tick++
      if (root.flips[0] || root.flips[1] || root.flips[2]) root.flips = [false, false, false]
      var tags = ["SYNC", "PARSE", "QUERY", "CACHE", "LINK", "EVAL"]
      root.pushLog(Stats.hexOf(0x3F00 + root.tick * 16, 4) + " " + tags[root.tick % 6] + " " + Stats.hexStr(4), "hex")
    }
  }

  Component.onCompleted: {
    tempProbe.running = true
    // seed the CPU delta so the first real sample lands one interval later
    Qt.callLater(function() { root.refresh(false) })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    useActiveColor: false
    horizontalMargin: 6
    fixedWidth: root.vertical ? -1 : glyph.implicitWidth + 12
    fixedHeight: root.vertical ? glyph.implicitHeight + 12 : -1
    tooltipText: root.opened ? "" : root.tooltip
    onPressed: function(b) {
      if (b === Qt.RightButton) root.launchBtop()
      else root.toggle()
    }

    BarGlyph {
      id: glyph
      anchors.centerIn: parent
      vertical: root.vertical
      loads: root.loads
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    padding: 0
    borderSpec: Border.none()
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(760)
    contentHeight: panel.fittedContentHeight(500)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "b") { root.close(); root.launchBtop() } }

      Loader {
        active: root.opened || panel.visible
        sourceComponent: MagiPopup { magi: root }
      }
    }
  }
}
