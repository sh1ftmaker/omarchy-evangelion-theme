#!/bin/bash
# zalo.nerv-target telemetry probe for the target window's process tree.
#   usage: telemetry.sh <pid>
#   out:   T <uptime_s>
#          P <pid> <read_bytes> <write_bytes> <utime+stime ticks> <threads> <starttime ticks> <fds>
#   (one P line per process in the tree rooted at <pid>, root first)
# Tree = ppid scan of /proc/*/stat (this kernel has no /proc/*/task/*/children), in one gawk
# pass; fds are counted with a bash glob per tree member. ~10 ms; Target.qml runs it every 2 s,
# only while the panel is visible.
root=$1
[[ $root =~ ^[0-9]+$ && -r /proc/$root/stat ]] || { echo "X"; exit 0; }
read -r up _ < /proc/uptime
echo "T $up"
shopt -s nullglob
while read -r tag p rest; do
  fd=(/proc/$p/fd/*)
  echo "P $p $rest ${#fd[@]}"
done < <(gawk -v root="$root" '
  {
    i = index($0, ") "); split(substr($0, i + 2), a, " ")   # a[1] = state (field 3)
    p = FILENAME; sub(/^\/proc\//, "", p); sub(/\/stat$/, "", p)
    kids[a[2]] = kids[a[2]] " " p
    tk[p] = a[12] + a[13]; th[p] = a[18]; st[p] = a[20]
    nextfile
  }
  END {
    if (!(root in tk)) exit
    q[0] = root; n = 1
    for (j = 0; j < n; j++) {
      m = split(kids[q[j]], c, " ")
      for (k = 1; k <= m; k++) q[n++] = c[k]
    }
    for (j = 0; j < n; j++) {
      p = q[j]; rb = 0; wb = 0; f = "/proc/" p "/io"
      while ((getline l < f) > 0) {
        if (l ~ /^read_bytes:/) rb = substr(l, 13) + 0
        else if (l ~ /^write_bytes:/) wb = substr(l, 14) + 0
      }
      close(f)
      printf "P %s %.0f %.0f %d %d %d\n", p, rb, wb, tk[p], th[p], st[p]
    }
  }' /proc/[0-9]*/stat 2>/dev/null)
