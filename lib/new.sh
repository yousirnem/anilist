#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/api.sh"

if [[ ! -f "$TOKEN_FILE" ]]; then
  bash "$LIB_DIR/auth.sh" || exit 1
fi

# Search input
if [[ -t 0 ]]; then
  search=$(rofi -dmenu -i -p "Search anime")
else
  read -r search
fi

[ -z "$search" ] && exit 0

# AniList search query
query=$(get_new_search_query)
variables=$(jq -n --arg s "$search" '{search: $s}')
response=$(call_api "$query" "$variables")

# Parse results
mapfile -t results < <(
  echo "$response" | jq -r '
    .data.Page.media[]
    | "\(.id)::\(.title.romaji // .title.english // .title.native)"
  '
)

count="${#results[@]}"

[ "$count" -eq 0 ] && {
  dunstify -u low "AniList" "No results found"
  exit 1
}

# Auto-pick if only 1 result
if [ "$count" -eq 1 ]; then
  choice="${results[0]}"
else
  choice=$(printf "%s\n" "${results[@]}" | rofi -dmenu -i -p "Choose anime")
  [ -z "$choice" ] && exit 0
fi

# Extract ID and title
media_id="${choice%%::*}"
title="${choice#*::}"

# Set status to WATCHING
mutation=$(get_save_media_list_entry_mutation)
variables=$(jq -n --argjson mediaId "$media_id" '{mediaId: $mediaId, status: "CURRENT"}')
call_api "$mutation" "$variables" > /dev/null

# Play with ani-cli
ani-cli "$title" \
  --no-detach \
  --exit-after-play
