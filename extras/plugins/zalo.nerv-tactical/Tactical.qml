import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// zalo.nerv-tactical — NERV desktop HUD (Evangelion theme).
// A keep-loaded panel plugin that mounts one click-through layer-shell window per screen on
// WlrLayer.Bottom: above the wallpaper (omarchy.background is WlrLayer.Background), below
// every window. Data comes from collector.py (one JSON line / 3 s). Motion is vsync-locked
// (one FrameAnimation, time-based): the pre-rendered sweep wedge rotates, blip glow is
// recomputed from the beam angle, meters/readouts ease toward the latest sample, the ticker
// and hazard band scroll sub-pixel, and contacts glide (Behaviors) to new ranges. All of it
// pauses while the desktop is covered by windows or the HUD is hidden.
//
// Show / hide:  omarchy-shell shell toggle zalo.nerv-tactical '{}'
//               omarchy-shell nerv-tactical toggle | show | hide | status
Item {
  id: root

  // host injection (unused beyond presence)
  property var shell
  property var manifest
  property string omarchyPath: ""

  property bool opened: true

  // ------------------------------------------------------------------ wall-host contract
  // embedded: zalo.nerv-wall owns the window, the covered check and the one frame clock. It sets
  // `embedded`/`wall` at creation, drives `frame()` while `wantFrames`, and instantiates `face`
  // at slotRect inside its full-screen window (face gets sx / sy / dpr).
  property bool embedded: false
  property var wall: null
  // demo: set by zalo.nerv-wall from nerv-wall.json "demo": true — identifying data (remote
  // hosts/ports, SSID, interface, process names/PIDs, kernel log, mount paths) is replaced with
  // plausible fakes in ingest(); rates, CPU, memory, temps stay live.
  property bool demo: false
  signal frame(real frameTime, int currentFrame)
  readonly property bool wantFrames: animating
  readonly property bool wallShown: opened
  readonly property var slotRect: rect
  readonly property Component face: faceComp

  // ------------------------------------------------------------------ live data
  property var conns: []
  property var angel: null
  property int total: 0
  property int hosts: 0
  property real rx: 0
  property real tx: 0
  property string iface: ""
  property string ssid: ""
  property real cpu: 0
  property real mem: 0
  property var load: ["0.00", "0.00", "0.00"]
  property int procs: 0
  property var topProc: ({ name: "", pid: "", pct: 0 })
  property var temps: ({})
  property string dgpu: "none"
  property var disks: []
  property var kmsg: []
  property var power: ({ ac: true, bat: null })
  property real uptimeBase: 0
  property real uptimeAt: 0
  property real uptime: 0

  // contacts keyed by ip so delegates persist across samples and can glide; entries that drop
  // out are marked alive=false (fade out) and removed on the next sample.
  ListModel { id: contactModel }
  property alias contacts: contactModel

  // eased copies of the sampled values (the FrameAnimation walks them toward the targets)
  property real rxS: 0
  property real txS: 0
  property real cpuS: 0
  property real memS: 0
  property real angelRateS: 0
  property real topPctS: 0
  property real tCpuS: 0
  property real tIgpuS: 0
  property real tDgpuS: 0
  property real tNvmeS: 0
  readonly property var easeKeys: [
    ["rxS", "rx"], ["txS", "tx"], ["cpuS", "cpu"], ["memS", "mem"], ["angelRateS", "angelRate"],
    ["topPctS", "topPct"], ["tCpuS", "tCpu"], ["tIgpuS", "tIgpu"], ["tDgpuS", "tDgpu"], ["tNvmeS", "tNvme"]
  ]
  readonly property real angelRate: angel ? angel.rate : 0
  readonly property real topPct: topProc.pct || 0
  readonly property real tCpu: temps.cpu || 0
  readonly property real tIgpu: temps.igpu || 0
  readonly property real tDgpu: temps.dgpu || 0
  readonly property real tNvme: temps.nvme || 0

  // ------------------------------------------------------------------ clocks
  readonly property real periodMs: 240000 / 133      // one bar at 133 BPM = one sweep turn
  property real sweepDeg: 0
  property real sweepReadout: 0     // SWEEP bearing text, ticks at ~15 Hz (a data readout)
  property real tickerPx: 0
  property real hazardPx: 0
  readonly property real tickerSpeed: 30   // px/s
  readonly property real hazardSpeed: 6    // px/s
  readonly property bool animating: opened && desktopVisible
  property int sec: 0
  property bool blinkOn: true
  property var now: new Date()
  readonly property string tzName: {
    var m = -now.getTimezoneOffset(), s = m >= 0 ? "+" : "-"
    m = Math.abs(m)
    return "UTC" + s + (m / 60 < 10 ? "0" : "") + Math.floor(m / 60) + ":" + (m % 60 < 10 ? "0" : "") + (m % 60)
  }

  readonly property bool angelHot: angel !== null && angel.rate > 262144
  readonly property bool anyHot: (temps.cpu || 0) >= 90 || (temps.igpu || 0) >= 90 || (temps.dgpu || 0) >= 85 || (temps.nvme || 0) >= 70
  readonly property bool diskHot: {
    for (var i = 0; i < disks.length; i++) if (disks[i].pct >= 90) return true
    return false
  }

  readonly property string tickerText: {
    var parts = []
    if (topProc.name) parts.push("TOP PROCESS " + topProc.name.toUpperCase() + " [" + topProc.pid + "] " + (topProc.pct || 0).toFixed(1) + "% CPU")
    parts.push("LOAD " + load.join(" / "))
    parts.push("MEM " + mem.toFixed(0) + "%")
    parts.push("TCP CONTACTS " + total + " FROM " + hosts + " HOSTS")
    if (angel) parts.push("PATTERN BLUE " + angel.ip + " — 使徒接近")
    for (var i = kmsg.length - 1; i >= 0; i--) parts.push("KERNEL: " + kmsg[i])
    parts.push("第3新東京市 迎撃システム 稼働中")
    return parts.join("   //   ") + "   //   "
  }

  // deterministic hex filler
  function hex(seed, step, n) {
    var s = ""
    var h = (seed * 374761393 + step * 668265263) >>> 0
    for (var i = 0; i < n; i++) {
      h = Math.imul(h ^ (h >>> 13), 1274126177) >>> 0
      h = (h + 0x9e3779b9) >>> 0
      s += "0123456789ABCDEF"[(h >>> 7) & 15]
    }
    return s
  }

  function ingest(line) {
    var d
    try { d = JSON.parse(line) } catch (e) { return }
    if (demo) d = demoData(d)
    conns = d.conns || []
    angel = conns.length > 0 ? conns[0] : null
    syncContacts(conns)
    total = d.total || 0
    hosts = d.hosts || 0
    rx = d.rx || 0
    tx = d.tx || 0
    iface = d.iface || ""
    ssid = d.ssid || ""
    cpu = d.cpu || 0
    mem = d.mem || 0
    load = d.load || load
    procs = d.procs || 0
    topProc = d.top || topProc
    temps = d.temps || {}
    dgpu = d.dgpu || "none"
    disks = d.disks || []
    kmsg = d.kmsg || []
    power = d.power || power
    uptimeBase = d.uptime || 0
    uptimeAt = Date.now()
    // while paused, snap the eased values (no hidden per-frame work; nothing to glide to)
    if (!animating) snapEased()
  }

  // ------------------------------------------------------------------ demo (privacy-safe screenshots)
  // RFC 5737 documentation addresses only; rates wander with time so blips stay alive.
  readonly property var demoHosts: [
    ["203.0.113.17", "443", 0.95], ["198.51.100.42", "8443", 0.6], ["192.0.2.33", "22", 0.35],
    ["203.0.113.88", "993", 0.25], ["198.51.100.7", "5222", 0.18], ["192.0.2.140", "443", 0.12],
    ["203.0.113.201", "3478", 0.08], ["198.51.100.163", "443", 0.05], ["192.0.2.66", "853", 0.03]
  ]
  readonly property var demoProcs: ["magi", "lcl-pump", "entry-plug", "a10-nerve", "hyprland"]
  readonly property var demoKmsg: [
    "AT FIELD PHASE SHIFT NOMINAL", "UMBILICAL CABLE LOCK CONFIRMED", "MAGI SYNC CHECKSUM OK",
    "LCL PRESSURE 1.02 ATM", "A10 NERVE LINK ESTABLISHED", "TERMINAL DOGMA SEAL INTACT"
  ]
  function demoData(d) {
    var t = Date.now() / 1000, conns = []
    for (var i = 0; i < demoHosts.length; i++) {
      var h = demoHosts[i], w = 0.6 + 0.4 * Math.sin(t / (7 + i * 3) + i * 1.7)
      var rate = Math.round(h[2] * w * 180000)
      conns.push({ ip: h[0], port: h[1], brg: (i * 137.5 + 23) % 360, rtt: 8 + i * 6.5 + 3 * Math.sin(t / 5 + i),
                   rx: rate * 40, tx: rate * 9, rate: rate, n: 1 + (i * 5) % 4 })
    }
    conns.sort(function (a, b) { return b.rate - a.rate })
    d.conns = conns
    d.total = conns.length + 5
    d.hosts = conns.length
    d.iface = "wlan0"
    d.ssid = "NERV-HQ"
    var step = Math.floor(t / 30)
    d.top = { name: demoProcs[step % demoProcs.length], pid: String(1000 + (step * 7919) % 30000),
              pct: d.top && d.top.pct ? d.top.pct : 0 }
    var k = []
    for (var j = 0; j < 3; j++) k.push(demoKmsg[(step + j) % demoKmsg.length])
    d.kmsg = k
    var names = { "/": 1, "/boot": 1, "/efi": 1, "/home": 1, "/var": 1 }, ds = d.disks || []
    for (var n = 0; n < ds.length; n++) {
      if (!names[ds[n].mnt]) ds[n].mnt = "/mnt/vol" + n
      ds[n].dev = "vol" + n
    }
    return d
  }

  function snapEased() {
    for (var i = 0; i < easeKeys.length; i++) root[easeKeys[i][0]] = root[easeKeys[i][1]]
  }

  function syncContacts(list) {
    var byIp = {}
    for (var i = 0; i < list.length; i++) byIp[list[i].ip] = list[i]
    // drop contacts that already faded out, mark newly-missing ones as fading
    for (var j = contactModel.count - 1; j >= 0; j--) {
      var e = contactModel.get(j)
      if (byIp[e.ip] === undefined) {
        if (!e.alive || !animating) contactModel.remove(j)
        else contactModel.setProperty(j, "alive", false)
      }
    }
    var at = {}
    for (var k = 0; k < contactModel.count; k++) at[contactModel.get(k).ip] = k
    for (var n = 0; n < list.length; n++) {
      var c = list[n]
      var row = { ip: c.ip, port: String(c.port), brg: c.brg || 0, rtt: c.rtt || 0, bytes: (c.rx || 0) + (c.tx || 0), alive: true }
      if (at[c.ip] !== undefined) contactModel.set(at[c.ip], row)
      else contactModel.append(row)
    }
  }

  // ------------------------------------------------------------------ show / hide (+ persisted)
  // open()/close() are the host's panel hooks (shell summon/hide/toggle): session-only, since
  // the host also calls close() on every panel before a plugin reload or shell exit.
  // The plugin's own IPC target (nerv-tactical toggle|show|hide) persists the choice.
  function open(payloadJson) { setOpened(true, false) }
  function close() { setOpened(false, false) }
  function toggle() { setOpened(!opened, true); return opened ? "shown" : "hidden" }
  function setOpened(v, persist) {
    opened = v
    if (persist) stateFile.setText(v ? "shown\n" : "hidden\n")
  }

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/nerv-tactical.state"
    printErrors: false
    onLoaded: root.opened = text().trim() !== "hidden"
  }

  IpcHandler {
    target: "nerv-tactical"
    function toggle(): string { return root.toggle() }
    function show(): string { root.setOpened(true, true); return "shown" }
    function hide(): string { root.setOpened(false, true); return "hidden" }
    function status(): string { return root.opened ? "shown" : "hidden" }
  }

  // ------------------------------------------------------------------ wall layout
  // Rect comes from ~/.config/omarchy/nerv-wall.json (1280x800 reference grid, scaled to each
  // screen's logical size). The file is watched: edit + save re-packs the wall live.
  readonly property string pluginId: "zalo.nerv-tactical"
  readonly property var defaultRect: ({ x: 912, y: 34, w: 360, h: 758 })
  property var wallCfg: null
  readonly property real refW: wallCfg && wallCfg.reference && wallCfg.reference.width > 0 ? wallCfg.reference.width : 1280
  readonly property real refH: wallCfg && wallCfg.reference && wallCfg.reference.height > 0 ? wallCfg.reference.height : 800
  readonly property real fillAlpha: wallCfg && typeof wallCfg.fillAlpha === "number" ? wallCfg.fillAlpha : 0.82
  readonly property var rect: {
    var r = wallCfg && wallCfg.panels ? wallCfg.panels[pluginId] : null
    return r && r.w > 0 && r.h > 0 ? r : defaultRect
  }
  readonly property color panelFill: Qt.rgba(0.02, 0.014, 0.008, fillAlpha)

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nerv-wall.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.wallCfg = JSON.parse(text()) }
      catch (e) { console.warn("nerv-tactical: bad nerv-wall.json, keeping previous layout:", e) }
    }
    onLoadFailed: root.wallCfg = null
  }

  // ------------------------------------------------------------------ data feed
  Process {
    id: feed
    running: root.opened
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("collector.py").toString().replace(/^file:\/\//, ""))]
    stdout: SplitParser { onRead: data => root.ingest(data) }
    stderr: SplitParser { onRead: data => console.warn("nerv-tactical collector:", data) }
    onExited: (code, status) => { if (root.opened) respawn.restart() }
  }
  Timer { id: respawn; interval: 5000; onTriggered: if (root.opened && !feed.running) feed.running = true }

  // ------------------------------------------------------------------ animation clocks
  // The desktop is visible only when a screen's active workspace has no windows; otherwise
  // freeze the sweep/ticker (the HUD is behind opaque windows anyway).
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

  // vsync-locked motion clock (60 Hz on eDP-1). Everything is time-based on frameTime.
  FrameAnimation {
    id: frames
    running: !root.embedded && root.animating
    onTriggered: root.frame(frameTime, currentFrame)
  }
  onFrame: (frameTime, currentFrame) => {
    {
      var dt = Math.min(frameTime, 0.1)
      root.sweepDeg = (root.sweepDeg + dt * 360000 / root.periodMs) % 360
      root.tickerPx += dt * root.tickerSpeed
      root.hazardPx = (root.hazardPx + dt * root.hazardSpeed) % 10
      if (currentFrame % 4 === 0) root.sweepReadout = root.sweepDeg
      // exponential ease toward the latest samples (tau = 0.25 s); snap when close
      var k = 1 - Math.exp(-dt / 0.25)
      var keys = root.easeKeys
      for (var i = 0; i < keys.length; i++) {
        var cur = root[keys[i][0]], tgt = root[keys[i][1]]
        if (cur === tgt) continue
        var nv = cur + (tgt - cur) * k
        if (Math.abs(tgt - nv) <= Math.max(0.002 * Math.abs(tgt), 0.01)) nv = tgt
        root[keys[i][0]] = nv
      }
    }
  }
  Timer {
    interval: 500
    repeat: true
    running: root.animating
    triggeredOnStart: true
    onTriggered: {
      root.blinkOn = !root.blinkOn
      if (root.blinkOn) {
        root.sec += 1
        root.now = new Date()
        if (root.uptimeAt > 0) root.uptime = root.uptimeBase + (Date.now() - root.uptimeAt) / 1000
      }
    }
  }

  // ------------------------------------------------------------------ face (window-free visual content)
  Component {
    id: faceComp
    Item {
      id: face
      property real sx: 1
      property real sy: 1
      property real dpr: 1

      // Content lays out at the face size; below the minimum it lays out at the minimum and
      // is scaled down uniformly so nothing overlaps.
      Item {
        id: stage
        readonly property real minW: 350
        readonly property real minH: 700
        width: Math.max(face.width, minW)
        height: Math.max(face.height, minH)
        transformOrigin: Item.TopLeft
        scale: Math.min(face.width / width, face.height / height)

        Radar {
          id: radar
          hud: root
          width: stage.width
          height: stage.height - statusWall.height - 6
        }
        StatusWall {
          id: statusWall
          y: radar.height + 6
          width: stage.width
          hud: root
        }
      }

      // CRT scanlines over everything (painted once)
      Canvas {
        anchors.fill: parent
        opacity: 0.9
        Component.onCompleted: requestPaint()
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

  // ------------------------------------------------------------------ standalone: one HUD window per screen
  Variants {
    model: root.embedded ? [] : Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: root.opened

      // reference grid -> this screen's logical px
      readonly property real sx: (modelData.width > 0 ? modelData.width : root.refW) / root.refW
      readonly property real sy: (modelData.height > 0 ? modelData.height : root.refH) / root.refH

      color: "transparent"
      // exact rect from the screen's top-left (Ignore: margins are not offset by the bar's zone)
      anchors { top: true; left: true }
      margins { top: Math.round(root.rect.y * sy); left: Math.round(root.rect.x * sx) }
      implicitWidth: Math.max(1, Math.round(root.rect.w * sx))
      implicitHeight: Math.max(1, Math.round(root.rect.h * sy))

      WlrLayershell.namespace: "zalo-nerv-tactical"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Don't reserve space and don't get pushed by the bar's zone.
      exclusionMode: ExclusionMode.Ignore
      // click-through
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
