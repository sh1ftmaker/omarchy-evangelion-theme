import QtQuick

// Title-card voice: Cormorant Garamond 600 squeezed horizontally, faux-bolded
// by stacking a few offset copies. Fits `maxWidth` by squeezing further, then
// shrinking uniformly.
Item {
  id: r
  property string text: ""
  property color color: "#FFE9C8"
  property real size: 100
  property real maxWidth: 0
  property real squeeze: 0.58
  property real bold: 0.014

  readonly property real natural: probe.implicitWidth
  readonly property real k: maxWidth > 0 && natural * squeeze > maxWidth ? maxWidth / (natural * squeeze) : 1
  readonly property real sx: k >= 0.75 ? squeeze * k : squeeze * 0.75 * (k / 0.75)
  readonly property real sy: k >= 0.75 ? 1 : k / 0.75

  width: natural * sx
  height: probe.implicitHeight * sy

  Text {
    id: probe
    visible: false
    text: r.text
    font.family: "Cormorant Garamond"
    font.weight: Font.DemiBold
    font.pixelSize: r.size
  }

  Repeater {
    model: [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1]]
    Text {
      required property var modelData
      textFormat: Text.PlainText
      text: r.text
      color: r.color
      font: probe.font
      x: modelData[0] * r.size * r.bold * r.sx
      y: modelData[1] * r.size * r.bold * 0.5 * r.sy
      transform: Scale { xScale: r.sx; yScale: r.sy }
    }
  }
}
