// unlock.png — boot/LUKS splash logo (800x188, transparent): AUTHORIZATION REQUIRED / 認証.
boot((c, W, H) => {
  const OR = rgba('orange');
  // left: hex emblem with 認証
  const hx = 94, hy = 94;
  hexGrid(hx - 100, hy - 100, 200, 200, 13, (x, y, col, row) => {
    const d = Math.hypot(x - hx, y - hy);
    if (d > 86 || d < 60) return;
    hexPath(c, x, y, 11.5);
    if (hash(col, row, 4) < 0.35) { c.fillStyle = rgba('orange', 0.85); c.fill(); }
    else { c.strokeStyle = rgba('orange', 0.6); c.lineWidth = 1; c.stroke(); }
  });
  hexPath(c, hx, hy, 58); c.fillStyle = rgba('ink'); c.fill();
  hexPath(c, hx, hy, 56); c.fillStyle = rgba('red'); c.fill();
  hexPath(c, hx, hy, 48); c.strokeStyle = rgba('ink'); c.lineWidth = 2; c.stroke();
  c.font = jp(40, 900, true); c.fillStyle = rgba('ink'); c.textAlign = 'center'; c.textBaseline = 'middle';
  c.fillText('認証', hx, hy + 2); c.textAlign = 'left';
  // right: card
  const x0 = 206;
  c.fillStyle = OR; chamferPath(c, x0, 8, 300, 22, [0, 12, 0, 0]); c.fill();
  text(c, 'MAGI SECURITY // LEVEL A', x0 + 8, 24, { weight: 700, size: 12, color: rgba('ink'), track: 2.4 });
  hazard(c, x0 + 316, 8, 272, 22, 0, rgba('red'), null, 14);
  const w = condensed(c, 'AUTHORIZATION', x0 - 3, 112, 86, { sx: 0.56, color: rgba('bone'), bold: 0.028 });
  c.fillStyle = OR; c.fillRect(x0, 124, 588, 3);
  condensed(c, 'REQUIRED', x0 + w + 12, 112, 58, { sx: 0.6, color: OR, bold: 0.03 });
  c.font = jp(26, 900, false); c.fillStyle = rgba('red'); c.textAlign = 'right';
  c.fillText('認証が必要です', x0 + 588, 162); c.textAlign = 'left';
  text(c, 'ENTER PASSPHRASE TO', x0, 150, { weight: 600, size: 12, color: OR, track: 2.2 });
  text(c, 'UNLOCK // 第3新東京市 NERV HQ', x0, 170, { weight: 600, size: 12, color: rgba('orange', 0.8), track: 2.2, font: jp(12, 700, false) });
  brackets(c, x0 - 8, 2, 604, 184, 12, rgba('orange', 0.8), 1.5);
}, { W: 800, H: 188, D: 1, transparent: true });
