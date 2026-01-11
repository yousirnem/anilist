#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

USERNAME=$(< "$USER_FILE") # AniList username
TOKEN=$(< "$TOKEN_FILE")

choice=$(printf "Serie\nMovie" | rofi -dmenu -i -p "Choose")
[[ -z "$choice" ]] && exit 0

dunstify -u low "Looking Planning List..."

query='
query ($userName: String) {
  MediaListCollection(userName: $userName, type: ANIME, status: PLANNING) {
    lists {
      entries {
        media {
          id
          title { romaji }
          format
        }
      }
    }
  }
}
'

payload=$(jq -n \
  --arg query "$query" \
  --arg userName "$USERNAME" \
  '{query: $query, variables: {userName: $userName}}')

response=$(curl -s -X POST https://graphql.anilist.co \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "$payload")

if echo "$response" | jq -e '.errors? | length > 0' > /dev/null; then
  dunstify -u critical "AniList Error" "$(echo "$response" | jq -r '.errors[0].message')"
  exit 1
fi

if [[ "$choice" == "Serie" ]]; then
  list=$(echo "$response" | jq -r '
    .data.MediaListCollection.lists[]
    | .entries[]
    | select(.media.format != "MOVIE")
    | "\(.media.title.romaji)|\(.media.id)"
  ')

  [[ -z "$list" ]] && dunstify -u low "Nothing in Planning" && exit 0

  selection=$(printf '%s\n' "$list" | rofi -dmenu -i -p "Serie")
  [[ -z "$selection" ]] && exit 0
  [[ "$selection" != *"|"* ]] && exit 1

  anime_name="${selection%%|*}"
  media_id="${selection##*|}"

  mutation='
  mutation ($mediaId: Int) {
    SaveMediaListEntry(mediaId: $mediaId, status: CURRENT) {
      id
      status
      progress
    }
  }
  '

  mutation_payload=$(jq -n \
    --arg query "$mutation" \
    --argjson mediaId "$media_id" \
    '{query: $query, variables: {mediaId: $mediaId}}')

  set +e
  update=$(curl -s -X POST https://graphql.anilist.co \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "$mutation_payload")
  set -e

  if ! echo "$update" | jq '.data.SaveMediaListEntry' > /dev/null; then
    dunstify -u critical "AniList Update Failed"
    exit 1
  fi

  dunstify -u low "▶️ $anime_name → Watching"
  ani-cli "$anime_name" -e 1 --no-detach --exit-after-play -S 1

else
  list=$(echo "$response" | jq -r '
    .data.MediaListCollection.lists[]
    | .entries[]
    | select(.media.format == "MOVIE")
    | .media.title.romaji
  ')

  [[ -z "$list" ]] && dunstify -u low "No Movie in Planning" && exit 0

  anime_name=$(printf '%s\n' "$list" | rofi -dmenu -i -p "Movie")
  [[ -z "$anime_name" ]] && exit 0

  ani-cli "$anime_name" --no-detach --exit-after-play -S 1
fi
