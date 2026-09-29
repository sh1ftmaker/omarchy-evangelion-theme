.pragma library
// Canvas helpers: 45° chamfered rectangles and pointy-top hexagons.

function chamfer(ctx, x, y, w, h, c) {
  var tl, tr, br, bl
  if (typeof c === "number") { tl = tr = br = bl = c }
  else { tl = c[0]; tr = c[1]; br = c[2]; bl = c[3] }
  ctx.beginPath()
  ctx.moveTo(x + tl, y)
  ctx.lineTo(x + w - tr, y)
  ctx.lineTo(x + w, y + tr)
  ctx.lineTo(x + w, y + h - br)
  ctx.lineTo(x + w - br, y + h)
  ctx.lineTo(x + bl, y + h)
  ctx.lineTo(x, y + h - bl)
  ctx.lineTo(x, y + tl)
  ctx.closePath()
}

function hex(ctx, cx, cy, r) {
  ctx.beginPath()
  for (var i = 0; i < 6; i++) {
    var a = Math.PI / 6 + i * Math.PI / 3
    var px = cx + r * Math.cos(a), py = cy + r * Math.sin(a)
    if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
  }
  ctx.closePath()
}

// Quantise 0..1 into n hard steps (no smooth motion anywhere).
function step(v, n) {
  if (!(v > 0)) return 0
  return Math.min(n, Math.ceil(v * n - 1e-6)) / n
}
