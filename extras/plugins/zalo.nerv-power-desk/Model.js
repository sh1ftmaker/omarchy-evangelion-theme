// Pure helpers for the NERV internal-battery widget (no QML imports, easy to reason about).

// Fake battery states for the visual test mode (setting "simulate" or IPC `simulate <mode>`).
// remain = seconds to empty (discharging) or to full (charging); 0 with holding = no countdown.
var SIMS = {
  discharging: { external: false, charging: false, holding: false, pct: 0.62, rate: 11.4, remain: 3 * 3600 + 4 * 60 + 17, energy: 34.9 },
  low:         { external: false, charging: false, holding: false, pct: 0.12, rate: 13.8, remain: 29 * 60 + 41, energy: 6.8 },
  critical:    { external: false, charging: false, holding: false, pct: 0.04, rate: 16.2, remain: 4 * 60 + 58, energy: 2.3 },
  depleted:    { external: false, charging: false, holding: false, pct: 0.0,  rate: 17.0, remain: 3.2, energy: 0.0 },
  charging:    { external: true,  charging: true,  holding: false, pct: 0.37, rate: 15.2, remain: 2 * 3600 + 18 * 60 + 5, energy: 20.9 },
  full:        { external: true,  charging: false, holding: true,  pct: 0.80, rate: 0.0,  remain: 0, energy: 45.1 }
}

function simKey(value) {
  var k = String(value || "").toLowerCase().trim()
  return SIMS.hasOwnProperty(k) ? k : ""
}

function sim(value) {
  var k = simKey(value)
  return k ? SIMS[k] : null
}

function pad2(n) {
  n = Math.max(0, Math.floor(n))
  return n < 10 ? "0" + n : String(n % 100)
}

// Big countdown "HH:MM:SS:CC" (hours capped at 99).
function clock(sec) {
  var cs = Math.max(0, Math.floor(sec * 100))
  var h = Math.min(99, Math.floor(cs / 360000))
  var m = Math.floor((cs % 360000) / 6000)
  var s = Math.floor((cs % 6000) / 100)
  return pad2(h) + ":" + pad2(m) + ":" + pad2(s) + ":" + pad2(cs % 100)
}

// Compact bar readout: "HH:MM" above an hour, "MM:SS" below it.
function shortClock(sec) {
  sec = Math.max(0, Math.floor(sec))
  if (sec >= 3600) return pad2(Math.min(99, Math.floor(sec / 3600))) + ":" + pad2((sec % 3600) / 60)
  return pad2(sec / 60) + ":" + pad2(sec % 60)
}

function fixed(v, d) {
  var n = Number(v)
  return isFinite(n) ? n.toFixed(d) : "--"
}

// Three-digit percentage for the 7-seg ("037").
function pct3(fraction) {
  var p = Math.round(Math.max(0, Math.min(1, fraction)) * 100)
  return (p < 10 ? "00" : p < 100 ? "0" : "") + p
}

function profileLabel(name) {
  if (name === "power-saver") return { en: "SAVER", jp: "節電" }
  if (name === "balanced") return { en: "BALANCED", jp: "通常" }
  if (name === "performance") return { en: "PERFORM", jp: "全開" }
  return { en: String(name || "").toUpperCase(), jp: "" }
}

function parseProfiles(raw) {
  var lines = String(raw || "").split("\n")
  var list = [], active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return { profiles: list, active: active }
}
