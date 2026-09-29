#!/usr/bin/env bash
# CASPER·3 probe. Prints one line: src|util%|vramUsedMiB|vramTotalMiB|tempC|powerW|name
#   src = nvidia | amdgpu | sleep | none
# Never wakes a runtime-suspended NVIDIA dGPU: if it is in D3, report "sleep".
dev=""
for d in /sys/bus/pci/devices/*; do
  [[ -r $d/vendor && $(<"$d/vendor") == 0x10de && $(<"$d/class") == 0x03* ]] && { dev=$d; break; }
done
if [[ -n $dev ]] && command -v nvidia-smi >/dev/null 2>&1; then
  st=$(cat "$dev/power/runtime_status" 2>/dev/null)
  if [[ $st == suspended ]]; then
    echo "sleep|0|0|0|||NVIDIA dGPU"
    exit 0
  fi
  out=$(timeout 2 nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,name \
        --format=csv,noheader,nounits 2>/dev/null | head -n1)
  if [[ -n $out ]]; then
    IFS=',' read -r u mu mt t p n <<<"$out"
    trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; echo "${s%"${s##*[![:space:]]}"}"; }
    echo "nvidia|$(trim "$u")|$(trim "$mu")|$(trim "$mt")|$(trim "$t")|$(trim "$p")|$(trim "$n")"
    exit 0
  fi
fi
for c in /sys/class/drm/card[0-9]/device /sys/class/drm/card[0-9][0-9]/device; do
  [[ -r $c/gpu_busy_percent ]] || continue
  u=$(<"$c/gpu_busy_percent")
  mu=$(( $(cat "$c/mem_info_vram_used" 2>/dev/null || echo 0) / 1048576 ))
  mt=$(( $(cat "$c/mem_info_vram_total" 2>/dev/null || echo 0) / 1048576 ))
  t=""; p=""
  for h in "$c"/hwmon/hwmon*; do
    [[ -r $h/temp1_input ]] && t=$(( $(<"$h/temp1_input") / 1000 ))
    if [[ -r $h/power1_average ]]; then p=$(awk '{printf "%.1f", $1/1000000}' "$h/power1_average")
    elif [[ -r $h/power1_input ]]; then p=$(awk '{printf "%.1f", $1/1000000}' "$h/power1_input"); fi
  done
  echo "amdgpu|$u|$mu|$mt|$t|$p|AMD RADEON iGPU"
  exit 0
done
echo "none|0|0|0|||"
