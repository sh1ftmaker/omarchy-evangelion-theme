import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// zalo.nerv-tactical — NERV desktop HUD (Evangelion theme).
// A keep-loaded panel plugin that mounts one click-through layer-shell window per screen on
// WlrLayer.Bottom: above the wallpaper (omarchy.background is WlrLayer.Background), below
// every window. Data comes from collector.py (one JSON line / 3 s): the radar plots nearby
// Wi-Fi networks (NetworkManager's cached scan list; a real scan at most every 10 min) and the
// associated network is the PATTERN BLUE contact. Motion is vsync-locked
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
  // demo: set by zalo.nerv-wall from nerv-wall.json "demo": true — identifying data (nearby
  // networks, SSIDs, BSSIDs, channels, interface, timezone/location, process names/PIDs, kernel
  // log, mount paths) is replaced with plausible fakes in ingest(); rates, CPU, memory, temps
  // stay live. Toggling re-ingests the last raw sample so the swap is immediate.
  property bool demo: false
  signal frame(real frameTime, int currentFrame)
  readonly property bool wantFrames: animating
  readonly property bool wallShown: opened
  readonly property var slotRect: rect
  readonly property Component face: faceComp

  // ------------------------------------------------------------------ live data
  // wifi: nets = blips (strongest first), angel = the associated network (merged with the
  // `iw link` details: dbm, rxBit, txBit, freq), netCount/ssidCount/openCount = whole scan list
  property var nets: []
  property var angel: null
  property int netCount: 0
  property int ssidCount: 0
  property int openCount: 0
  property real scanAt: 0          // epoch s of the last scan request (0 = never / no wifi)
  property real scanEvery: 600
  property string wifiDev: ""
  // timezone (from the collector, re-read every 30 s so a change applies without a restart)
  property string tzId: ""
  property string tzAbbr: ""
  property int tzOff: -new Date().getTimezoneOffset() * 60   // seconds east of UTC
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

  // contacts keyed by BSSID so delegates persist across samples and can glide; entries that
  // drop out are marked alive=false (fade out) and removed on the next sample.
  ListModel { id: contactModel }
  property alias contacts: contactModel

  // eased copies of the sampled values (the FrameAnimation walks them toward the targets)
  property real rxS: 0
  property real txS: 0
  property real cpuS: 0
  property real memS: 0
  property real angelSigS: 0
  property real topPctS: 0
  property real tCpuS: 0
  property real tIgpuS: 0
  property real tDgpuS: 0
  property real tNvmeS: 0
  readonly property var easeKeys: [
    ["rxS", "rx"], ["txS", "tx"], ["cpuS", "cpu"], ["memS", "mem"], ["angelSigS", "angelSig"],
    ["topPctS", "topPct"], ["tCpuS", "tCpu"], ["tIgpuS", "tIgpu"], ["tDgpuS", "tDgpu"], ["tNvmeS", "tNvme"]
  ]
  // link quality 0..100 (from the associated BSS's live dBm when known, else NM's %)
  readonly property real angelSig: !angel ? 0 : angel.dbm !== undefined ? dbmPct(angel.dbm) : (angel.sig || 0)
  function dbmPct(d) { return Math.max(0, Math.min(100, 100 - (-40 - d) * 100 / 60)) }
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
  // wall time in the zone: read with the getUTC*() accessors (independent of Qt's cached TZ)
  readonly property var zoneNow: new Date(now.getTime() + tzOff * 1000)
  readonly property string tzOffText: {
    var m = Math.round(tzOff / 60), s = m >= 0 ? "+" : "-"
    m = Math.abs(m)
    return "UTC" + s + (m / 60 < 10 ? "0" : "") + Math.floor(m / 60) + ":" + (m % 60 < 10 ? "0" : "") + (m % 60)
  }
  // "America/Argentina/Buenos_Aires" -> city "BUENOS AIRES", region "AMERICA"
  readonly property string tzCity: {
    var p = tzId.split("/")
    return (p[p.length - 1] || "LOCAL").replace(/_/g, " ").toUpperCase()
  }
  readonly property string tzRegion: {
    var p = tzId.split("/")
    return p.length > 1 && p[0] !== "Etc" ? p[0].toUpperCase() : "UNIVERSAL"
  }
  // scan age / countdown in whole seconds (ticks with `now`)
  readonly property int scanAge: scanAt > 0 ? Math.max(0, Math.floor(now.getTime() / 1000 - scanAt)) : -1
  readonly property int scanNext: scanAt > 0 ? Math.max(0, Math.ceil(scanAt + scanEvery - now.getTime() / 1000)) : -1

  // weak link (<= -78 dBm) turns the target box / hazard band red
  readonly property bool angelHot: angel !== null && angel.dbm !== undefined && angel.dbm <= -78
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
    parts.push("WIFI NETWORKS " + netCount + " / " + ssidCount + " SSIDS / " + openCount + " OPEN")
    if (angel) parts.push("PATTERN BLUE " + (angel.ssid || "HIDDEN") + " — 接続中")
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

  property string lastLine: ""
  onDemoChanged: if (lastLine) ingest(lastLine)
  function ingest(line) {
    var d
    try { d = JSON.parse(line) } catch (e) { return }
    lastLine = line
    if (demo) d = demoData(d)
    var w = d.wifi || {}
    nets = w.nets || []
    angel = w.link || null
    syncContacts(nets)
    netCount = w.count || 0
    ssidCount = w.ssids || 0
    openCount = w.open || 0
    scanAt = w.scanAt || 0
    scanEvery = w.scanEvery || 600
    wifiDev = w.dev || ""
    if (d.tz) {
      tzId = d.tz.name || ""
      tzAbbr = d.tz.abbr || ""
      tzOff = d.tz.off || 0
    }
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
  // Fictional networks only (no real SSID/BSSID/channel survives from the collector sample);
  // signals wander with time so blips drift. Scan timing and rates stay live (not identifying).
  //                   ssid             sec     band   ch  base %
  readonly property var demoNets: [
    ["NERV-HQ",        "PSK",  "5G",   36, 82], ["MAGI-01",       "EAP",  "5G",   36, 74],
    ["MAGI-02",        "EAP",  "2.4G",  1, 66], ["GEOFRONT-5G",   "SAE",  "5G",  149, 71],
    ["SEELE",          "EAP",  "6G",   37, 28], ["UN-FORCES",     "PSK",  "2.4G",  6, 44],
    ["JSSDF-TAC",      "EAP",  "5G",  100, 36], ["LCL-PLANT",     "PSK",  "2.4G", 11, 52],
    ["TOKYO3-PUBLIC",  "OPEN", "2.4G",  6, 58], ["HAKONE-CAFE",   "OPEN", "5G",   44, 40],
    ["KATSURAGI",      "SAE",  "5G",  157, 48], ["EVA-CAGE-7",    "PSK",  "2.4G", 11, 30],
    ["TERMINAL-DOGMA", "EAP",  "6G",   69, 22], ["",              "PSK",  "5G",  149, 34],
    ["",               "EAP",  "2.4G",  1, 26]
  ]
  readonly property var demoProcs: ["magi", "lcl-pump", "entry-plug", "a10-nerve", "hyprland"]
  readonly property var demoKmsg: [
    "AT FIELD PHASE SHIFT NOMINAL", "UMBILICAL CABLE LOCK CONFIRMED", "MAGI SYNC CHECKSUM OK",
    "LCL PRESSURE 1.02 ATM", "A10 NERVE LINK ESTABLISHED", "TERMINAL DOGMA SEAL INTACT"
  ]
  function demoData(d) {
    var t = Date.now() / 1000, nets = [], open = 0, ssids = {}
    for (var i = 0; i < demoNets.length; i++) {
      var e = demoNets[i]
      var sig = Math.round(Math.max(8, Math.min(98, e[4] + 7 * Math.sin(t / (11 + i * 4) + i * 1.9))))
      var freq = e[2] === "2.4G" ? 2407 + 5 * e[3] : e[2] === "5G" ? 5000 + 5 * e[3] : 5950 + 5 * e[3]
      nets.push({ id: "demo-" + i, ssid: e[0], sec: e[1], band: e[2], ch: e[3], freq: freq, sig: sig,
                  dbm: Math.round(-40 - (100 - sig) * 0.6), brg: (i * 137.5 + 23) % 360, cur: i === 0 })
      if (e[1] === "OPEN") open++
      if (e[0]) ssids[e[0]] = 1
    }
    nets.sort(function (a, b) { return (b.cur - a.cur) || (b.sig - a.sig) })
    var hq = nets[0], w = d.wifi || {}
    d.wifi = {
      dev: "wlan0", nets: nets, count: nets.length, ssids: Object.keys(ssids).length, open: open,
      scanAt: w.scanAt || 0, scanEvery: w.scanEvery || 600,
      link: { id: hq.id, ssid: hq.ssid, sec: hq.sec, band: hq.band, ch: hq.ch, freq: hq.freq, sig: hq.sig,
              brg: hq.brg, cur: true, dbm: Math.round(-49 + 3 * Math.sin(t / 9)), rxBit: 866.7, txBit: 780.0 }
    }
    d.tz = { name: "Asia/TOKYO-3", abbr: "JST", off: 32400 }
    d.iface = "wlan0"
    d.ssid = hq.ssid
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
    var byId = {}
    for (var i = 0; i < list.length; i++) byId[list[i].id] = list[i]
    // drop contacts that already faded out, mark newly-missing ones as fading
    for (var j = contactModel.count - 1; j >= 0; j--) {
      var e = contactModel.get(j)
      if (byId[e.nid] === undefined) {
        if (!e.alive || !animating) contactModel.remove(j)
        else { contactModel.setProperty(j, "alive", false); contactModel.setProperty(j, "rank", 999) }
      }
    }
    var at = {}
    for (var k = 0; k < contactModel.count; k++) at[contactModel.get(k).nid] = k
    for (var n = 0; n < list.length; n++) {
      var c = list[n]
      var row = { nid: String(c.id), ssid: String(c.ssid || ""), sec: String(c.sec || ""), band: String(c.band || ""),
                  ch: Number(c.ch || 0), sig: Number(c.sig || 0), brg: Number(c.brg || 0), rank: n, alive: true }
      if (at[c.id] !== undefined) contactModel.set(at[c.id], row)
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
    stderr: SplitParser {
      onRead: data => {
        if (data.indexOf("[info] ") === 0) console.info("nerv-tactical collector:", data.slice(7))
        else console.warn("nerv-tactical collector:", data)
      }
    }
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
