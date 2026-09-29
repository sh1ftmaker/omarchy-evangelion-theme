import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "Model.js" as Model

// zalo.nerv-power-desk — always-on ACTIVITY LIMIT 活動限界 panel for the NERV desktop wall.
// Desktop version of zalo.nerv-power's popup: UPower battery, 7-seg HH:MM:SS:CC countdown with
// ticking hundredths, INTERNAL / EXTERNAL umbilical chips, drain bar, low / critical hazard +
// warning box, current power profile (read-only: the panel is click-through).
//
// Placement: its rect in ~/.config/omarchy/nerv-wall.json (1280x800 reference, scaled to the
// screen), WlrLayer.Bottom, click-through, no focus, no exclusive zone.
// Performance: one vsync FrameAnimation drives the clock (hundredths, sub-pixel ticker + hazard
// scroll); it stops while all screens' active workspaces hold windows, or the panel is hidden.
// Blinks / colon stay stepped (derived from the clock with floor()). Level / drain / watts ease
// toward new UPower samples via Behaviors (only while a change is in flight).
//
// Show / hide:   omarchy-shell nerv-power-desk toggle | show | hide
// Visual test:   omarchy-shell nerv-power-desk simulate low|critical|depleted|charging|full|discharging|off|auto
//                (or "simulate": "Low" on the plugin's shell.json entry)
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "zalo.nerv-power-desk"
  property bool opened: true

  // ---- wall-host contract ------------------------------------------------------------------------
  // embedded: zalo.nerv-wall owns the window, the covered check and the one frame clock.
  property bool embedded: false
  property var wall: null
  property bool demo: false   // wall "demo" flag: this panel shows nothing identifying, so no-op
  signal frame(real frameTime, int currentFrame)
  readonly property bool wantFrames: live
  readonly property bool wallShown: opened && present
  readonly property var slotRect: rect
  readonly property Component face: faceComp

  // ---- palette (NERV-BRIEF.md) ---------------------------------------------------------------
  readonly property color cInk: "#050403"
  readonly property color cGraphite: "#4A3218"
  readonly property color cBone: "#FFE9C8"
  readonly property color cOrange: "#FF7A00"
  readonly property color cAmber: "#FFB000"
  readonly property color cRed: "#FF1A1A"
  readonly property color cBlood: "#6A0000"
  readonly property color cGreen: "#39FF6A"
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // ---- wall rect (nerv-wall.json) --------------------------------------------------------------
  property var rect: ({ x: 536, y: 34, w: 368, h: 240 })
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
      try { d = JSON.parse(text()) } catch (e) { return }
      if (d.reference) { root.refW = d.reference.width || 1280; root.refH = d.reference.height || 800 }
      if (typeof d.fillAlpha === "number") root.fillAlpha = d.fillAlpha
      var r = d.panels ? d.panels[root.pluginId] : null
      if (r && r.w > 0 && r.h > 0) root.rect = { x: r.x, y: r.y, w: r.w, h: r.h }
    }
  }

  // ---- "simulate" setting on this plugin's shell.json entry (read-only) -------------------------
  property string cfgSim: "Off"
  FileView {
    id: cfgFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var d
      try { d = JSON.parse(text()) } catch (e) { return }
      var list = d.plugins || [], v = "Off"
      for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === root.pluginId && list[i].simulate) v = String(list[i].simulate)
      root.cfgSim = v
    }
  }

  // ---- simulated states ------------------------------------------------------------------------
  property string ipcSim: ""                       // "" = follow setting, "off" = force real
  readonly property string simMode: Model.simKey(ipcSim !== "" ? ipcSim : cfgSim)
  readonly property var simData: Model.sim(simMode)
  readonly property bool simulated: simData !== null

  // ---- real battery (UPower) -------------------------------------------------------------------
  readonly property var dev: UPower.displayDevice
  readonly property var pack: {
    var list = UPower.devices ? UPower.devices.values : []
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].isLaptopBattery) return list[i]
    return null
  }
  readonly property bool realPresent: !!(dev && dev.isPresent)
  readonly property bool present: simulated || realPresent
  readonly property bool external: simulated ? simData.external : !UPower.onBattery
  readonly property real pct: simulated ? simData.pct : (dev ? Math.max(0, Math.min(1, dev.percentage)) : 0)
  readonly property real rateW: simulated ? simData.rate : (dev ? Math.abs(dev.changeRate) : 0)
  readonly property real energyWh: simulated ? simData.energy : (dev ? dev.energy : 0)
  readonly property real capacityWh: simulated ? 56.4 : (dev ? dev.energyCapacity : 0)
  // eased copies for the meters / readouts (UPower samples arrive every ~30 s .. minutes)
  property real pctE: pct
  Behavior on pctE { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
  property real rateE: rateW
  Behavior on rateE { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
  readonly property real healthPct: simulated ? 74.2 : (pack && pack.healthSupported ? pack.healthPercentage : 0)
  readonly property bool charging: {
    if (simulated) return simData.charging
    if (!dev || !external) return false
    if (dev.state !== UPowerDeviceState.Charging) return false
    return rateW > 0.2 && dev.timeToFull < 8 * 3600
  }
  readonly property bool holding: external && !charging
  readonly property real rawRemain: {
    if (simulated) return simData.remain
    if (!dev) return 0
    if (!external) {
      if (dev.timeToEmpty > 0) return dev.timeToEmpty
      return rateW > 0.1 ? energyWh / rateW * 3600 : 0
    }
    return charging && dev.timeToFull > 0 ? dev.timeToFull : 0
  }

  // ---- countdown extrapolated between UPower updates ------------------------------------------
  property real anchorRemain: 0
  property real anchorMs: 0
  property real nowMs: Date.now()
  function reanchor() {
    anchorRemain = rawRemain
    anchorMs = Date.now()
    nowMs = anchorMs
  }
  onRawRemainChanged: reanchor()
  onSimModeChanged: reanchor()
  Component.onCompleted: { reanchor(); refresh() }

  readonly property bool counting: present && !holding && anchorRemain > 0
  readonly property real remain: counting ? Math.max(0, anchorRemain - (nowMs - anchorMs) / 1000) : anchorRemain

  // ---- alarm levels ------------------------------------------------------------------------------
  readonly property bool low: present && !external && pct < 0.15
  readonly property bool critical: present && !external && (pct < 0.05 || (counting && remain < 600))
  readonly property bool depleted: present && !external && (pct <= 0.005 || (counting && remain <= 0))
  readonly property bool blinkOn: Math.floor(nowMs / 280) % 2 === 0
  readonly property bool colonOn: Math.floor(nowMs / 500) % 2 === 0

  readonly property color hud: external ? cGreen : (low ? cRed : cOrange)
  readonly property color digitBase: external ? cGreen : (low ? cRed : cAmber)
  // Critical / depleted blink is an opacity flip on the digit layer (no Canvas repaints).
  readonly property color digits: (depleted || critical) ? cRed : digitBase
  readonly property real digitOpacity: blinkOn ? 1 : (depleted ? 0.2 : (critical ? 0.45 : 1))

  // ---- power profile (read-only readout) ----------------------------------------------------------
  property string activeProfile: ""
  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = Model.parseProfiles(text)
        if (p.profiles.length > 0) root.activeProfile = p.active
      }
    }
  }
  function refresh() { if (!profilesProc.running) profilesProc.running = true }

  // ---- visibility / clocks -------------------------------------------------------------------------
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
  readonly property bool live: opened && present && desktopVisible
  onLiveChanged: if (live) { nowMs = Date.now(); refresh() }

  FrameAnimation {
    // vsync-locked (60 Hz on eDP-1): hundredths, sub-pixel ticker / hazard scroll. Stops when covered.
    running: !root.embedded && root.live
    onTriggered: root.frame(frameTime, currentFrame)
  }
  onFrame: (frameTime, currentFrame) => { root.nowMs = Date.now() }
  Timer {
    running: root.live
    repeat: true
    interval: 10000
    onTriggered: root.refresh()
  }

  // ---- host hooks + IPC ------------------------------------------------------------------------------
  function open(payloadJson) { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened; return opened ? "shown" : "hidden" }
  function show() { opened = true; return "shown" }
  function hide() { opened = false; return "hidden" }
  function simulate(mode) {
    var m = String(mode || "").toLowerCase().trim()
    ipcSim = m === "auto" ? "" : m
    return simMode === "" ? "real" : simMode
  }
  function status() {
    return JSON.stringify({
      sim: simMode, external: external, charging: charging, holding: holding,
      pct: Math.round(pct * 100), rateW: rateW, remain: Math.round(remain), health: healthPct,
      profile: activeProfile, low: low, critical: critical, depleted: depleted,
      desktopVisible: desktopVisible, fps: live ? "vsync" : 0, rect: rect
    })
  }

  IpcHandler {
    target: "nerv-power-desk"
    function toggle(): string { return root.toggle() }
    function show(): string { return root.show() }
    function hide(): string { return root.hide() }
    function simulate(mode: string): string { return root.simulate(mode) }
    function status(): string { return root.status() }
  }

  // ---- face (window-free content) ----------------------------------------------------------------
  Component {
    id: faceComp
    Item {
      id: face
      property real sx: 1
      property real sy: 1
      property real dpr: 1
      DeskFace {
        host: root
        pxScale: Math.max(face.sx, face.sy) * face.dpr
        width: root.rect.w
        height: root.rect.h
        transform: Scale { xScale: face.sx; yScale: face.sy }
      }
    }
  }

  // ---- standalone window ------------------------------------------------------------------------------
  Variants {
    model: root.embedded ? [] : Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: root.opened && root.present

      readonly property real sx: (modelData ? modelData.width : root.refW) / root.refW
      readonly property real sy: (modelData ? modelData.height : root.refH) / root.refH

      color: "transparent"
      anchors { top: true; left: true }
      margins { top: Math.round(root.rect.y * sy); left: Math.round(root.rect.x * sx) }
      implicitWidth: Math.round(root.rect.w * sx)
      implicitHeight: Math.round(root.rect.h * sy)
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "nerv-power-desk"
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
