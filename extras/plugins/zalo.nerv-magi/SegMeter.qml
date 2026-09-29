import QtQuick
import "Palette.js" as Pal

// Segmented level meter: hard steps, hot segments turn red.
Item {
  id: meter
  property int count: 20
  property real value: 0
  property string onColor: Pal.orange
  property string hotColor: Pal.red
  property real hotFrom: Pal.HOT
  property int spacing: 1
  readonly property int lit: value > 0 ? Math.min(count, Math.ceil(value * count - 1e-6)) : 0
  readonly property real segW: (width - (count - 1) * spacing) / count

  Repeater {
    model: meter.count
    Rectangle {
      required property int index
      x: Math.round(index * (meter.segW + meter.spacing))
      width: Math.max(1, Math.round((index + 1) * (meter.segW + meter.spacing)) - x - meter.spacing)
      height: meter.height
      color: index < meter.lit ? (index >= Math.floor(meter.hotFrom * meter.count) ? meter.hotColor : meter.onColor) : Pal.graphite
      opacity: index < meter.lit ? 1 : 0.45
    }
  }
}
