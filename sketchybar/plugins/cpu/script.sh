#!/bin/sh
set -e

CORES=$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null || echo 1)

CPU=$(
  /bin/ps -A -o %cpu= |
    /usr/bin/awk -v cores="$CORES" '
      { sum += $1 }
      END {
        if (cores < 1) {
          cores = 1
        }

        value = sum / cores
        if (value < 0) {
          value = 0
        }
        if (value > 100) {
          value = 100
        }

        printf "%.0f", value
      }
    '
)

sketchybar --set "$NAME" label="${CPU}%"
