import QtQuick
import "Palette.js" as Pal
import "Draw.js" as Draw

// One MAGI processor: chamfered block, name strip coloured by its current vote,
// the vote itself in the strip, live contents in the body.
Item {
  id: block
  property string name: ""
  property string jpName: ""
  property bool headTop: true
  property var cuts: [6, 6, 6, 6]
  property var vote: null          // true approve · false reject · null abstain
  property bool flash: false       // one stepped flash after a vote flips
  property int headH: 19
  default property alias content: body.data

  readonly property string vcol: Pal.voteColor(vote)

  onVcolChanged: cv.requestPaint()
  onFlashChanged: cv.requestPaint()

  Canvas {
    id: cv
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      Draw.chamfer(ctx, 1, 1, w - 2, h - 2, block.cuts)
      ctx.fillStyle = Pal.ink2
      ctx.fill()
      if (block.flash) { ctx.globalAlpha = 0.18; ctx.fillStyle = block.vcol; ctx.fill(); ctx.globalAlpha = 1 }
      ctx.save()
      Draw.chamfer(ctx, 1, 1, w - 2, h - 2, block.cuts)
      ctx.clip()
      ctx.fillStyle = block.vcol
      ctx.fillRect(0, block.headTop ? 0 : h - block.headH, w, block.headH)
      ctx.restore()
      Draw.chamfer(ctx, 1, 1, w - 2, h - 2, block.cuts)
      ctx.strokeStyle = block.vcol
      ctx.lineWidth = 2
      ctx.stroke()
    }
  }

  Item {
    id: strip
    x: 8
    width: parent.width - 16
    height: block.headH
    y: block.headTop ? 0 : parent.height - block.headH

    MonoText {
      id: nameText
      anchors.verticalCenter: parent.verticalCenter
      text: block.name
      color: Pal.ink
      font.weight: Font.Bold
      font.pixelSize: 9
      font.letterSpacing: 1.3
    }
    JpText {
      // elides rather than running under the vote when the block is narrow
      anchors.left: nameText.right
      anchors.leftMargin: 5
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, voteText.x - x - 4)
      elide: Text.ElideRight
      text: block.jpName
      color: Pal.ink
      font.pixelSize: 7
    }
    JpText {
      id: voteText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: block.vote === true ? "承認" : (block.vote === false ? "否決" : "待機")
      color: Pal.ink
      font.pixelSize: 11
      font.weight: Font.Black
    }
  }

  Item {
    id: body
    x: 9
    width: parent.width - 18
    y: block.headTop ? block.headH + 6 : 7
    height: parent.height - block.headH - 13
  }
}
