#!/usr/bin/env bash
set -euo pipefail

# =====================
# Config
# =====================
source "$HOME/.local/share/anilist/config.sh"

ANILIST_API="https://graphql.anilist.co"

if [[ ! -f "$TOKEN_FILE" ]]; then
  bash "$LIB_DIR/auth.sh" || exit 1
fi

ANILIST_TOKEN=$(< "$TOKEN_FILE")
# =====================
# Search input
# =====================
search=$(rofi -dmenu -i -p "Search anime")
[ -z "$search" ] && exit 0

# =====================
# AniList search query
# =====================
response=$(curl -s "$API" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg s "$search" '{
    query: "query ($search: String) { Page(perPage: 10) { media(search: $search, type: ANIME) { id title { romaji english native } } } }",
    variables: { search: $s }
  }')")

# =====================
# Parse results
# =====================
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

# =====================
# Auto-pick if only 1 result
# =====================
if [ "$count" -eq 1 ]; then
  choice="${results[0]}"
else
  choice=$(printf "%s\n" "${results[@]}" | rofi -dmenu -i -p "Choose anime")
  [ -z "$choice" ] && exit 0
fi

# =====================
# Extract ID and title
# =====================
media_id="${choice%%::*}"
title="${choice#*::}"

# =====================
# Set status to WATCHING
# =====================
curl -s "$ANILIST_API" \
  -H "Authorization: Bearer $ANILIST_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --argjson id "$media_id" '{
    query: "mutation ($mediaId: Int) { SaveMediaListEntry(mediaId: $mediaId, status: CURRENT) { id } }",
    variables: { mediaId: $id }
  }')" > /dev/null

# =====================
# Play with ani-cli
# =====================
ani-cli "$title" \
  --skip \
  --no-detach \
  --exit-after-play
