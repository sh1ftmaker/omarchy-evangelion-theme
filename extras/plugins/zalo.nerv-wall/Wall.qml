import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// zalo.nerv-wall — host for the NERV desktop wall.
//
// Instead of six plugins each mounting their own layer-shell window(s), this plugin mounts ONE
// click-through, no-focus, no-exclusive-zone, transparent, full-screen WlrLayer.Bottom window per
// screen and draws every panel's face inside it at its ~/.config/omarchy/nerv-wall.json rect.
// It owns the single "is the desktop covered?" check and the single vsync FrameAnimation;
// panels consume both, so the whole wall pauses together.
//
// Panels are the unchanged zalo.nerv-* plugins, instantiated here by file URL in "embedded" mode
// (their data logic, helper processes and IPC targets keep working; their own windows and
// clocks are off). Embedded contract each panel root implements:
//   in:  embedded: bool, wall: this object (reads wall.desktopVisible)
//        demo: bool            — bound to nerv-wall.json "demo" (privacy-safe fake identifying data)
//   out: signal frame(real frameTime, int currentFrame)   — emitted by us while wantFrames
//        wantFrames: bool      — panel needs motion frames (opened && visible && …)
//        wallShown: bool       — panel face visible (per-panel IPC show/hide)
//        slotRect: {x,y,w,h}   — rect in the reference grid; refW / refH: the grid size
//        face: Component       — window-free visual content; root Item with sx, sy, dpr
//
// The six standalone plugins must be disabled while this one is enabled (theme-set hook
// nerv-mode does that), otherwise they would draw twice / register their IPC targets twice.
//
// Show / hide:  omarchy-shell nerv-wall toggle | show | hide | status
//               (per panel: omarchy-shell nerv-<name> toggle | show | hide | status, as before)
Item {
  id: wall

  // host injection
  property var shell
  property var manifest
  property string omarchyPath: ""

  property bool opened: true
  function open(payloadJson) { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened; return opened ? "shown" : "hidden" }

  IpcHandler {
    target: "nerv-wall"
    function toggle(): string { return wall.toggle() }
    function show(): string { wall.opened = true; return "shown" }
    function hide(): string { wall.opened = false; return "hidden" }
    function status(): string {
      var out = []
      for (var i = 0; i < wall.panels.length; i++) {
        var p = wall.panels[i]
        out.push(wall.specs[i].id.replace("zalo.nerv-", "") + "=" + (p ? (p.wallShown ? "shown" : "hidden") : "failed"))
      }
      return (wall.opened ? "shown" : "hidden") + " desktop=" + (wall.desktopVisible ? "visible" : "covered")
        + " clock=" + (clock.running ? "running" : "paused") + " " + out.join(" ")
    }
  }

  // ------------------------------------------------------------------ panels
  readonly property string pluginsDir: Quickshell.env("HOME") + "/.config/omarchy/plugins"
  // draw order (none overlap in the stock layout)
  readonly property var specs: [
    { id: "zalo.nerv-magi-desk",   file: "MagiDesk.qml" },
    { id: "zalo.nerv-psychograph", file: "Panel.qml" },
    { id: "zalo.nerv-power-desk",  file: "PowerDesk.qml" },
    { id: "zalo.nerv-seele",       file: "Seele.qml" },
    { id: "zalo.nerv-target",      file: "Target.qml" },
    { id: "zalo.nerv-tactical",    file: "Tactical.qml" }
  ]
  property var panels: []            // embedded panel roots, same order as specs (null = failed)

  Component.onCompleted: {
    var out = []
    for (var i = 0; i < specs.length; i++) {
      var url = "file://" + pluginsDir + "/" + specs[i].id + "/" + specs[i].file
      var comp = Qt.createComponent(url)
      var obj = null
      if (comp.status === Component.Ready) {
        obj = comp.createObject(wall, { embedded: true, wall: wall })
        if (!obj) console.warn("nerv-wall: createObject failed for", specs[i].id)
        else if ("demo" in obj) obj.demo = Qt.binding(() => wall.demo)
      } else {
        console.warn("nerv-wall: cannot load", specs[i].id + ":", comp.errorString())
      }
      out.push(obj)
    }
    panels = out
  }

  // ------------------------------------------------------------------ the one covered check
  // The desktop is visible when some screen's active workspace has no windows.
  readonly property bool hyprDesktopVisible: {
    var ms = Hyprland.monitors.values
    if (!ms || ms.length === 0) return true
    for (var i = 0; i < ms.length; i++) {
      var ws = ms[i].activeWorkspace
      if (!ws || !ws.toplevels || ws.toplevels.values.length === 0) return true
    }
    return false
  }
  // what panels read as their `desktopVisible` (also false while the whole wall is hidden)
  readonly property bool desktopVisible: opened && hyprDesktopVisible

  // ------------------------------------------------------------------ the one frame clock
  readonly property bool anyWantsFrames: {
    for (var i = 0; i < panels.length; i++) if (panels[i] && panels[i].wantFrames) return true
    return false
  }
  readonly property bool animating: desktopVisible && anyWantsFrames
  FrameAnimation {
    id: clock
    running: wall.animating
    onTriggered: {
      var ps = wall.panels
      for (var i = 0; i < ps.length; i++) {
        var p = ps[i]
        if (p && p.wantFrames) p.frame(frameTime, currentFrame)
      }
    }
  }

  // ------------------------------------------------------------------ optional bloom
  // Off unless nerv-wall.json has "bloom": true AND bloom/NervBloom.qml loads.
  property bool bloomEnabled: false
  // optional overrides for NervBloom's tuning, e.g. "bloomParams": { "intensity": 0.18 }
  property var bloomParams: ({})
  // "demo": true in nerv-wall.json → panels swap identifying data (hosts, IPs, SSID, process
  // names, PIDs, window titles) for plausible fakes, for publishable screenshots. Default off.
  property bool demo: false
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nerv-wall.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var j = JSON.parse(text())
        wall.bloomEnabled = j.bloom === true
        wall.bloomParams = j.bloomParams || {}
        wall.demo = j.demo === true
      } catch (e) {}
    }
  }

  // ------------------------------------------------------------------ one window per screen
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: wall.opened

      color: "transparent"
      anchors { top: true; left: true; right: true; bottom: true }
      exclusionMode: ExclusionMode.Ignore
      exclusiveZone: 0
      WlrLayershell.namespace: "zalo-nerv-wall"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      // ======== BLOOM INSERTION POINT ========
      // wallContent: every panel face, nothing else, transparent background, full window size.
      // Bloom = an overlay sibling ABOVE it with `source: wallContent` (see bloomLoader).
      Item {
        id: wallContent
        anchors.fill: parent
        // covered by windows: drop the subtree from the scene so data ticks (helpers keep
        // sampling slowly) don't re-render a full-screen surface nobody can see
        visible: wall.desktopVisible

        Repeater {
          model: wall.panels

          // one slot per panel: its face at the nerv-wall.json rect (scaled like the old windows)
          Loader {
            id: slot
            required property var modelData
            readonly property var p: modelData
            readonly property real sx: (win.modelData.width > 0 ? win.modelData.width : p.refW) / p.refW
            readonly property real sy: (win.modelData.height > 0 ? win.modelData.height : p.refH) / p.refH

            active: p !== null
            visible: p !== null && p.wallShown
            clip: true              // same bounds a per-panel window used to clip to
            x: p ? Math.round(p.slotRect.x * sx) : 0
            y: p ? Math.round(p.slotRect.y * sy) : 0
            width: p ? Math.max(1, Math.round(p.slotRect.w * sx)) : 0
            height: p ? Math.max(1, Math.round(p.slotRect.h * sy)) : 0
            sourceComponent: p ? p.face : null
            onLoaded: {
              item.sx = Qt.binding(() => slot.sx)
              item.sy = Qt.binding(() => slot.sy)
              item.dpr = Qt.binding(() => win.devicePixelRatio || 1)
            }
          }
        }
      }

      Loader {
        id: bloomLoader
        anchors.fill: parent
        // unloaded while covered: frees the chain's textures and costs nothing
        active: wall.bloomEnabled && wall.desktopVisible
        source: Qt.resolvedUrl("bloom/NervBloom.qml")
        onLoaded: {
          item.source = wallContent
          // stay live: in composite mode the bloom draws the wall itself, and an unchanged
          // wall costs nothing to re-capture (scene-graph dirty tracking)
          item.live = true
          applyParams()
          item.devicePixelRatio = Qt.binding(() => win.devicePixelRatio || 1)
        }
        function applyParams() {
          if (!item) return
          var bp = wall.bloomParams
          for (var k in bp) if (k in item) item[k] = bp[k]
        }
        Connections { target: wall; function onBloomParamsChanged() { bloomLoader.applyParams() } }
        onStatusChanged: if (status === Loader.Error) console.warn("nerv-wall: bloom failed to load")
      }
    }
  }
}
