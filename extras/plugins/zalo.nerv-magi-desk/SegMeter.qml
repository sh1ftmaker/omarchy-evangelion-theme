import QtQuick
import "Palette.js" as Pal

// Segmented level meter. The segments are static rectangles (a dim row and a lit row); the lit
// row sits in a clip whose width eases toward the latest sample, so the fill glides between
// samples at the cost of one property change per frame (no Canvas, no per-segment bindings).
Item {
  id: meter
  property int count: 20
  property real value: 0
  property string onColor: Pal.orange
  property string hotColor: Pal.red
  property real hotFrom: Pal.HOT
  property int spacing: 1
  property int easeMs: 600
  readonly property real segW: (width - (count - 1) * spacing) / count
  readonly property int hotIdx: Math.floor(hotFrom * count)

  property real shown: Math.max(0, Math.min(1, value))
  Behavior on shown { NumberAnimation { duration: meter.easeMs; easing.type: Easing.OutCubic } }

  Repeater {
    model: meter.count
    Rectangle {
      required property int index
      x: Math.round(index * (meter.segW + meter.spacing))
      width: Math.max(1, Math.round((index + 1) * (meter.segW + meter.spacing)) - x - meter.spacing)
      height: meter.height
      color: Pal.graphite
      opacity: 0.45
    }
  }
  Item {
    width: meter.width * meter.shown
    height: meter.height
    clip: true
    Repeater {
      model: meter.count
      Rectangle {
        required property int index
        x: Math.round(index * (meter.segW + meter.spacing))
        width: Math.max(1, Math.round((index + 1) * (meter.segW + meter.spacing)) - x - meter.spacing)
        height: meter.height
        color: index >= meter.hotIdx ? meter.hotColor : meter.onColor
      }
    }
  }
}
