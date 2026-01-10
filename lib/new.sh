#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"


query=$(rofi -dmenu -p "Buscar anime")
[ -z "$query" ] && exit 0

ani-cli "$query" \
  --skip \
  --no-detach \
  --exit-after-play
