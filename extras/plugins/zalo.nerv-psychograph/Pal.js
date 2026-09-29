.pragma library
// NERV palette + Canvas2D helpers (shared by the psychograph HUD)

var ink = "#050403"
var ink2 = "#120C06"
var graphite = "#4A3218"
var ash = "#9C6A2E"
var bone = "#FFE9C8"
var orange = "#FF7A00"
var amber = "#FFB000"
var red = "#FF1A1A"
var blood = "#6A0000"
var green = "#39FF6A"
var cyan = "#00C8FF"

var mono = "IBM Plex Mono"
var jp = "Noto Sans CJK JP"
var serif = "Cormorant Garamond"

var RGB = {
  orange: [255, 122, 0], amber: [255, 176, 0], red: [255, 26, 26], green: [57, 255, 106],
  graphite: [74, 50, 24], ash: [156, 106, 46], bone: [255, 233, 200], ink: [5, 4, 3], cyan: [0, 200, 255]
}

function rgba(name, a) {
  var c = RGB[name] || RGB.orange
  return "rgba(" + c[0] + "," + c[1] + "," + c[2] + "," + a + ")"
}

// level (0 ok, 1 amber, 2 red) -> colour name
function levelName(level, okName) {
  return level >= 2 ? "red" : level >= 1 ? "amber" : (okName || "green")
}

// chamfered rect path, cut per corner [tl, tr, br, bl]
function chamfer(ctx, x, y, w, h, c) {
  ctx.beginPath()
  ctx.moveTo(x + c[0], y); ctx.lineTo(x + w - c[1], y); ctx.lineTo(x + w, y + c[1])
  ctx.lineTo(x + w, y + h - c[2]); ctx.lineTo(x + w - c[2], y + h); ctx.lineTo(x + c[3], y + h)
  ctx.lineTo(x, y + h - c[3]); ctx.lineTo(x, y + c[0]); ctx.closePath()
}

function brackets(ctx, x, y, w, h, len, color, lw) {
  ctx.strokeStyle = color; ctx.lineWidth = lw || 1
  ctx.beginPath()
  ctx.moveTo(x, y + len); ctx.lineTo(x, y); ctx.lineTo(x + len, y)
  ctx.moveTo(x + w - len, y); ctx.lineTo(x + w, y); ctx.lineTo(x + w, y + len)
  ctx.moveTo(x + w, y + h - len); ctx.lineTo(x + w, y + h); ctx.lineTo(x + w - len, y + h)
  ctx.moveTo(x + len, y + h); ctx.lineTo(x, y + h); ctx.lineTo(x, y + h - len)
  ctx.stroke()
}

function hexPath(ctx, cx, cy, r) {
  ctx.moveTo(cx + r * Math.cos(Math.PI / 6), cy + r * Math.sin(Math.PI / 6))
  for (var i = 1; i <= 6; i++) {
    var a = Math.PI / 6 + i * Math.PI / 3
    ctx.lineTo(cx + r * Math.cos(a), cy + r * Math.sin(a))
  }
}

function hexGrid(ctx, x, y, w, h, r, color) {
  var dx = Math.sqrt(3) * r, dy = 1.5 * r
  ctx.save()
  ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip()
  ctx.strokeStyle = color; ctx.lineWidth = 0.6
  ctx.beginPath()
  for (var row = 0; row * dy <= h + r; row++)
    for (var col = 0; col * dx <= w + dx; col++)
      hexPath(ctx, x + col * dx + (row % 2 ? dx / 2 : 0), y + row * dy, r - 0.8)
  ctx.stroke()
  ctx.restore()
}

function hazard(ctx, x, y, w, h, color, stripe) {
  stripe = stripe || 5
  ctx.save()
  ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip()
  ctx.fillStyle = color
  for (var sx = x - h - stripe * 2; sx < x + w + stripe; sx += stripe * 2) {
    ctx.beginPath()
    ctx.moveTo(sx, y + h); ctx.lineTo(sx + h, y); ctx.lineTo(sx + h + stripe, y); ctx.lineTo(sx + stripe, y + h)
    ctx.closePath(); ctx.fill()
  }
  ctx.restore()
}

function fmtRate(b) {
  if (b < 1024) return Math.round(b) + "B"
  if (b < 1024 * 1024) return (b / 1024).toFixed(b < 10240 ? 1 : 0) + "K"
  if (b < 1024 * 1024 * 1024) return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + "M"
  return (b / 1073741824).toFixed(1) + "G"
}
