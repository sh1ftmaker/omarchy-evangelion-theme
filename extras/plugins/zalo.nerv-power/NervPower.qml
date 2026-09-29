import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Ui
import "Model.js" as Model

// NERV "INTERNAL BATTERY" bar widget: Eva activity-limit countdown driven by the real laptop
// battery (UPower, same source as omarchy.power / omarchy.battery). Click for the full panel.
BarWidget {
  id: root
  moduleName: "zalo.nerv-power"

  // ---- palette (NERV-BRIEF.md) ---------------------------------------------------------
  readonly property color cInk: "#050403"
  readonly property color cInk2: "#120C06"
  readonly property color cGraphite: "#4A3218"
  readonly property color cAsh: "#9C6A2E"
  readonly property color cBone: "#FFE9C8"
  readonly property color cOrange: "#FF7A00"
  readonly property color cAmber: "#FFB000"
  readonly property color cRed: "#FF1A1A"
  readonly property color cBlood: "#6A0000"
  readonly property color cGreen: "#39FF6A"
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // ---- simulated states (visual test) ------------------------------------------------------
  // "" = follow the setting; "off" = force real data; any Model.SIMS key = fake that state.
  property string ipcSim: ""
  readonly property string simMode: Model.simKey(ipcSim !== "" ? ipcSim : setting("simulate", "Off"))
  readonly property var simData: Model.sim(simMode)
  readonly property bool simulated: simData !== null

  // ---- real battery (UPower) ---------------------------------------------------------------
  readonly property var dev: UPower.displayDevice
  // The physical pack (health / native path for cycle_count); displayDevice is the aggregate.
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
  readonly property real healthPct: simulated ? 74.2 : (pack && pack.healthSupported ? pack.healthPercentage : 0)
  readonly property real designWh: healthPct > 0 ? capacityWh / (healthPct / 100) : 0
  readonly property bool charging: {
    if (simulated) return simData.charging
    if (!dev || !external) return false
    if (dev.state !== UPowerDeviceState.Charging) return false
    // Charge-threshold hold (omarchy.power's heuristic): trickle / absurd ETA = not really charging.
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

  // ---- countdown extrapolated between UPower updates -------------------------------------
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
  Component.onCompleted: reanchor()

  readonly property bool counting: present && !holding && anchorRemain > 0
  readonly property real remain: counting ? Math.max(0, anchorRemain - (nowMs - anchorMs) / 1000) : anchorRemain

  // ---- alarm levels -------------------------------------------------------------------------
  readonly property bool low: present && !external && pct < 0.15
  readonly property bool critical: present && !external && (pct < 0.05 || (counting && remain < 600))
  readonly property bool depleted: present && !external && (pct <= 0.005 || (counting && remain <= 0))
  readonly property bool blinkOn: Math.floor(nowMs / 280) % 2 === 0
  readonly property bool colonOn: Math.floor(nowMs / 500) % 2 === 0

  // Main HUD colour for the current state.
  readonly property color stateColor: external ? cGreen : (low ? cRed : cOrange)
  readonly property color digitColor: external ? cGreen : (low ? cRed : cAmber)

  // ---- cycles from sysfs (not exposed by UPower) ----------------------------------------------
  property string cycles: ""
  FileView {
    id: cycleFile
    path: root.pack && root.pack.nativePath ? "/sys/class/power_supply/" + root.pack.nativePath + "/cycle_count" : ""
    blockLoading: true
    printErrors: false
    onLoaded: {
      var n = parseInt(String(cycleFile.text()).trim())
      root.cycles = isFinite(n) && n > 0 ? String(n) : "N/A"
    }
  }

  // ---- power profiles (same helpers as omarchy.power) ---------------------------------------
  property var profiles: []
  property string activeProfile: ""
  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = Model.parseProfiles(text)
        if (p.profiles.length === 0) return
        root.profiles = p.profiles
        root.activeProfile = p.active
      }
    }
  }
  Process {
    id: profileSetProc
    onExited: root.refresh()
  }
  function setProfile(name) {
    if (!name || profileSetProc.running) return
    activeProfile = name
    profileSetProc.command = ["omarchy-powerprofiles-set", UPower.onBattery ? "battery" : "ac", name]
    profileSetProc.running = true
  }
  function refresh() {
    if (!profilesProc.running) profilesProc.running = true
    if (cycleFile.path !== "") cycleFile.reload()
  }

  // ---- popup lifecycle (bar popout coordinator) -----------------------------------------------
  property bool opened: false
  function open() {
    if (opened || !present) return
    opened = true
    refresh()
    reanchor()
    if (bar) bar.requestPopout(root)
  }
  function close() {
    if (!opened) return
    opened = false
    if (bar) bar.releasePopout(root)
  }
  function closeForPopoutSwitch() { close() }
  function toggle() { opened ? close() : open() }
  onPresentChanged: if (!present) close()

  // One clock for everything: 30 fps while the panel shows hundredths, 7 Hz for the red blink,
  // 2 Hz (colon blink) otherwise. Canvases only repaint when their text / colour changes.
  Timer {
    running: root.present
    repeat: true
    interval: root.opened ? 33 : (root.low ? 140 : 500)
    onTriggered: root.nowMs = Date.now()
  }
  Timer {
    running: root.opened
    repeat: true
    interval: 5000
    onTriggered: root.refresh()
  }

  // ---- IPC: open/close and the keyboard-free visual test ---------------------------------------
  // quickshell ipc -p /usr/share/omarchy/shell call zalo.nerv-power simulate low|critical|depleted|charging|full|discharging|off|auto
  IpcHandler {
    target: "zalo.nerv-power"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function simulate(mode: string): string {
      var m = String(mode || "").toLowerCase()
      root.ipcSim = m === "auto" ? "" : m
      return root.simMode === "" ? "real" : root.simMode
    }
    function status(): string {
      return JSON.stringify({
        sim: root.simMode, external: root.external, charging: root.charging, holding: root.holding,
        pct: Math.round(root.pct * 100), rateW: root.rateW, remain: Math.round(root.remain),
        energyWh: root.energyWh, capacityWh: root.capacityWh, health: root.healthPct, cycles: root.cycles,
        profile: root.activeProfile, low: root.low, critical: root.critical
      })
    }
  }

  // ---- bar readout ------------------------------------------------------------------------------
  readonly property bool showLabel: setting("showLabel", true) !== false
  readonly property string barDigits: holding ? "--:--" : Model.shortClock(remain)
  readonly property bool alarmBlink: low && !blinkOn

  visible: present
  implicitWidth: present ? readout.implicitWidth + 12 : 0
  implicitHeight: present ? (vertical ? readout.implicitHeight + 12 : barSize) : 0

  Grid {
    id: readout
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 3
    spacing: 5
    verticalItemAlignment: Grid.AlignVCenter
    horizontalItemAlignment: Grid.AlignHCenter

    // 内部電源 / 外部電源 tab, title knocked out in black
    Item {
      visible: root.showLabel && !root.vertical
      width: tabText.implicitWidth + 12
      height: 16
      Chamfer {
        anchors.fill: parent
        cuts: [0, 5, 0, 5]
        lineWidth: 1
        fill: root.alarmBlink ? "transparent" : root.stateColor
        stroke: root.stateColor
      }
      Text {
        id: tabText
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 0
        text: root.external ? "外部電源" : "内部電源"
        color: root.alarmBlink ? root.stateColor : root.cInk
        font.family: "Noto Sans CJK JP"
        font.weight: Font.Black
        font.pixelSize: 10
      }
    }

    SevenSeg {
      id: barSeg
      text: root.barDigits
      digitHeight: 14
      thick: 2.3
      skew: 0.08
      color: root.alarmBlink ? root.alpha(root.cRed, 0.25) : root.digitColor
      dim: root.alpha(root.digitColor, 0.10)
      colonOn: root.holding || root.colonOn
    }

    // segmented battery meter with terminal cap
    Item {
      width: root.vertical ? 14 : 34
      height: root.vertical ? 30 : 13
      Chamfer {
        id: shell
        x: 0; y: root.vertical ? 3 : 0
        width: root.vertical ? parent.width : parent.width - 3
        height: root.vertical ? parent.height - 3 : parent.height
        cuts: [0, 3, 0, 3]
        lineWidth: 1
        stroke: root.stateColor
      }
      Rectangle {
        color: root.stateColor
        x: root.vertical ? parent.width / 2 - 3 : parent.width - 2
        y: root.vertical ? 0 : parent.height / 2 - 3
        width: root.vertical ? 6 : 2
        height: root.vertical ? 2 : 6
      }
      Grid {
        x: shell.x + 3; y: shell.y + 3
        rows: root.vertical ? 8 : 1
        columns: root.vertical ? 1 : 8
        spacing: 1
        Repeater {
          model: 8
          Rectangle {
            required property int index
            readonly property int slot: root.vertical ? 7 - index : index
            readonly property bool lit: slot < Math.ceil(root.pct * 8 - 0.001)
            width: root.vertical ? shell.width - 6 : (shell.width - 6 - 7) / 8
            height: root.vertical ? (shell.height - 6 - 7) / 8 : shell.height - 6
            color: lit ? (root.alarmBlink && slot === 0 ? root.cBlood : root.stateColor) : root.alpha(root.stateColor, 0.12)
          }
        }
      }
    }
  }

  MouseArea {
    id: hit
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (root.bar) root.bar.hideTooltip(hit)
      root.toggle()
    }
    onContainsMouseChanged: {
      if (!root.bar) return
      if (containsMouse && !root.opened) {
        var t = root.external
          ? (root.charging ? "UMBILICAL 外部電源 · " + Math.round(root.pct * 100) + "% · FULL IN " + Model.shortClock(root.remain)
                           : "UMBILICAL 外部電源 · " + Math.round(root.pct * 100) + "% · HOLDING")
          : "INTERNAL 内部電源 · " + Math.round(root.pct * 100) + "% · 活動限界 " + Model.shortClock(root.remain) + " · " + root.rateW.toFixed(1) + " W"
        root.bar.showTooltip(hit, (root.simulated ? "[SIM] " : "") + t)
      } else {
        root.bar.hideTooltip(hit)
      }
    }
  }

  // Loaded by URL (not as an inline type) so plugin hot-reload always picks up a fresh copy.
  Loader {
    id: popupLoader
    active: root.opened
    Component.onCompleted: setSource(Qt.resolvedUrl("NervPopup.qml"), { host: root, anchorItem: readout })
  }
}
