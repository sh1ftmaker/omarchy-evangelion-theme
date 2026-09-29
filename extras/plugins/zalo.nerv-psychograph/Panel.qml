import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Pal.js" as Pal

// NERV desktop HUD tile of the NERV wall, on the desktop layer (WlrLayer.Bottom:
// above the wallpaper, which lives on Background, and below every window).
// Click-through, no focus, no exclusive zone. Its rect comes from
// ~/.config/omarchy/nerv-wall.json (watched: edit + save re-packs live).
//
// While every screen's active workspace has windows the HUD is covered: the
// helper is told to pause (audio capture + FFT stop, stats drop to one line / 5 s),
// the vsync FrameAnimations of both scopes stop and nothing repaints.
//
// Hide / show:  omarchy-shell shell toggle zalo.nerv-psychograph '{}'
//               omarchy-shell shell call zalo.nerv-psychograph toggle ""
//               omarchy-shell nerv-psychograph toggle
// Remove:       omarchy plugin disable zalo.nerv-psychograph
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  property bool opened: true

  // ---------------------------------------------------------------- wall-host contract
  // embedded: zalo.nerv-wall owns the window, the covered check and the one frame clock.
  // Helper lines are broadcast (statsLine / harmLine) so every face instance gets them.
  property bool embedded: false
  property var wall: null
  property bool demo: false   // wall "demo" flag: this panel shows nothing identifying, so no-op
  signal frame(real frameTime, int currentFrame)
  signal statsLine(var p)
  signal harmLine(var p)
  readonly property bool wantFrames: live
  readonly property bool wallShown: opened
  readonly property var slotRect: rect
  readonly property Component face: faceComp
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")

  function open(payloadJson) { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened; return opened ? "shown" : "hidden" }
  function show() { opened = true; return "shown" }
  function hide() { opened = false; return "hidden" }

  IpcHandler {
    target: "nerv-psychograph"
    function toggle(): string { return root.toggle() }
    function show(): string { return root.show() }
    function hide(): string { return root.hide() }
  }

  // ---------------------------------------------------------------- wall layout
  readonly property string pluginId: "zalo.nerv-psychograph"
  readonly property var defaultRect: ({ x: 8, y: 464, w: 520, h: 328 })
  property var wallCfg: null
  readonly property real refW: wallCfg && wallCfg.reference && wallCfg.reference.width > 0 ? wallCfg.reference.width : 1280
  readonly property real refH: wallCfg && wallCfg.reference && wallCfg.reference.height > 0 ? wallCfg.reference.height : 800
  readonly property real fillAlpha: wallCfg && typeof wallCfg.fillAlpha === "number" ? wallCfg.fillAlpha : 0.82
  readonly property var rect: {
    var r = wallCfg && wallCfg.panels ? wallCfg.panels[pluginId] : null
    return r && r.w > 0 && r.h > 0 ? r : defaultRect
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nerv-wall.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.wallCfg = JSON.parse(text()) }
      catch (e) { console.warn("nerv-psychograph: bad nerv-wall.json, keeping previous layout:", e) }
    }
    onLoadFailed: root.wallCfg = null
  }

  // ---------------------------------------------------------------- covered?
  // The desktop is visible only when some screen's active workspace has no windows.
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

  // ---------------------------------------------------------------- helper
  // /proc stats every 1 s + audio spectrum (only while playback exists).
  // stdin: "P" pauses (no audio capture/FFT, stats every 5 s), "R" resumes.
  Process {
    id: helper
    command: ["python3", "-u", root.pluginDir + "psychograph.py"]
    running: root.opened
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var p = line.split(" ")
        if (p[0] === "H") root.harmLine(p)
        else if (p[0] === "S") root.statsLine(p)
      }
    }
    onRunningChanged: if (running) root.sendState()
    onExited: function(code) { if (root.opened) restart.start() }
  }
  Timer {
    id: restart
    interval: 3000
    onTriggered: if (root.opened && !helper.running) helper.running = Qt.binding(function() { return root.opened })
  }
  function sendState() { if (helper.running) helper.write(root.live ? "R\n" : "P\n") }
  onLiveChanged: sendState()

  // standalone clock (the wall host drives frame() when embedded)
  FrameAnimation {
    running: !root.embedded && root.live
    onTriggered: root.frame(frameTime, currentFrame)
  }

  // ---------------------------------------------------------------- face (window-free content)
  Component {
    id: faceComp
    Item {
      id: face
      property real sx: 1
      property real sy: 1
      property real dpr: 1

      Connections {
        target: root
        function onStatsLine(p) { psycho.push(p) }
        function onHarmLine(p) { harmonics.frame(p) }
      }

      // Content lays out at the face size; below the minimum it lays out at the
      // minimum and is scaled down uniformly so nothing overlaps.
      Item {
        id: stage
        readonly property real minW: 420
        readonly property real minH: 310
        width: Math.max(face.width, minW)
        height: Math.max(face.height, minH)
        transformOrigin: Item.TopLeft
        scale: Math.min(face.width / width, face.height / height)

        // 190 : 132 split of the tile (6 px gutter)
        readonly property int psyH: Math.round((height - 6) * 190 / 322)

        PsychoPanel {
          id: psycho
          x: 0; y: 0
          width: stage.width; height: stage.psyH
          fillAlpha: root.fillAlpha
          live: root.live
          ticker: root
        }

        HarmonicsPanel {
          id: harmonics
          x: 0; y: stage.psyH + 6
          width: stage.width; height: stage.height - stage.psyH - 6
          fillAlpha: root.fillAlpha
          live: root.live
          ticker: root
        }
      }

      // CRT scanlines over everything (painted once per resize)
      Canvas {
        anchors.fill: parent
        opacity: 0.9
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.fillStyle = "rgba(0,0,0,0.26)"
          for (var y = 0; y < height; y += 2) ctx.fillRect(0, y + 1, width, 0.7)
        }
      }
    }
  }

  // ---------------------------------------------------------------- standalone window
  Variants {
    model: root.embedded ? [] : [0]

    PanelWindow {
      id: win
      required property var modelData   // Variants plumbing only (single window, default screen)
      visible: root.opened

      readonly property real sx: (screen && screen.width > 0 ? screen.width : root.refW) / root.refW
      readonly property real sy: (screen && screen.height > 0 ? screen.height : root.refH) / root.refH

      // exact rect from the screen's top-left (Ignore: margins are not offset by the bar's zone)
      anchors { top: true; left: true }
      margins { top: Math.round(root.rect.y * sy); left: Math.round(root.rect.x * sx) }
      implicitWidth: Math.max(1, Math.round(root.rect.w * sx))
      implicitHeight: Math.max(1, Math.round(root.rect.h * sy))
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "nerv-psychograph"
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
