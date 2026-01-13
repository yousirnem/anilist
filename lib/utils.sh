#!/usr/bin/env bash

# Normalize function
normalize() {
  echo "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[:\-–—]/ /g; s/[^a-z0-9 ]//g; s/ +/ /g; s/^ //; s/ $//'
}

format_duration() {
  local s=$1
  ((s < 0)) && echo "avalible" && return

  local d=$((s / 86400))
  local h=$(((s % 86400) / 3600))
  local m=$(((s % 3600) / 60))

  if ((d > 0)); then
    printf "%dd %dh %dm" "$d" "$h" "$m"
  elif ((h > 0)); then
    printf "%dh %dm" "$h" "$m"
  else
    printf "%dm" "$m"
  fi
}
