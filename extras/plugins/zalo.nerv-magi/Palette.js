.pragma library
// NERV palette (exact values from the theme brief).
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

var mono = "IBM Plex Mono"
var serif = "Cormorant Garamond"
var jp = "Noto Sans CJK JP"

// Load thresholds: red 否決 above HOT, green 承認 below COOL, orange otherwise.
var HOT = 0.85
var COOL = 0.25
// A unit approves the standing query ("ACCEPT NEW WORKLOAD?") below this load.
var VOTE = 0.60

function stateColor(load) {
  if (load === undefined || load === null || isNaN(load) || load < 0) return ash
  if (load > HOT) return red
  if (load < COOL) return green
  return orange
}

function voteColor(v) {
  return v === true ? green : (v === false ? red : ash)
}
