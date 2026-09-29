import QtQuick
import "Palette.js" as Pal
import "Draw.js" as Draw

// NERV panel: chamfered frame with a solid header tab, title knocked out in ink.
Item {
  id: panel
  property string title: ""
  property string jp: ""
  property string accent: Pal.orange
  property int cut: 10
  property int headH: 15
  property int inset: 6
  default property alias content: body.data

  readonly property real tabW: Math.min(width * 0.9, tabRow.implicitWidth + 16)

  onTabWChanged: frame.requestPaint()
  onAccentChanged: frame.requestPaint()

  Canvas {
    id: frame
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      Draw.chamfer(ctx, 0.5, 0.5, width - 1, height - 1, [0, panel.cut, 0, panel.cut])
      ctx.globalAlpha = 0.92
      ctx.fillStyle = Pal.ink2
      ctx.fill()
      ctx.globalAlpha = 0.75
      ctx.strokeStyle = panel.accent
      ctx.lineWidth = 1
      ctx.stroke()
      ctx.globalAlpha = 1
      Draw.chamfer(ctx, 0, 0, panel.tabW, panel.headH, [0, panel.headH * 0.6, 0, 0])
      ctx.fillStyle = panel.accent
      ctx.fill()
      ctx.fillRect(0, panel.headH, width - panel.cut, 1)
    }
  }

  Row {
    id: tabRow
    x: 6
    height: panel.headH
    spacing: 6
    MonoText {
      anchors.verticalCenter: parent.verticalCenter
      text: panel.title
      color: Pal.ink
      font.weight: Font.Bold
      font.pixelSize: 9
    }
    JpText {
      anchors.verticalCenter: parent.verticalCenter
      visible: panel.jp !== ""
      text: panel.jp
      color: Pal.ink
      font.pixelSize: 8
    }
  }

  Item {
    id: body
    anchors.fill: parent
    anchors.topMargin: panel.headH + panel.inset
    anchors.leftMargin: panel.inset
    anchors.rightMargin: panel.inset
    anchors.bottomMargin: panel.inset
  }
}
