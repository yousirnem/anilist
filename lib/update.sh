#!/usr/bin/env bash
set -uo pipefail

LOG="$HOME/.local/share/anilist/logs/update-debug.log"
exec >> "$LOG" 2>&1
echo "---- $(date) ----"

source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/utils.sh"

NAME="$1"
EPISODE="$2"

[[ -z "$NAME" || -z "$EPISODE" ]] && exit 1

if [[ ! -f "$TOKEN_FILE" ]]; then
  bash "$LIB_DIR/auth.sh" || exit 1
fi

ACCESS_TOKEN=$(< "$TOKEN_FILE")

query='
query ($search: String) {
  Page(perPage: 10) {
    media(search: $search, type: ANIME) {
      id
      title { romaji }
      mediaListEntry {
        id
        progress
      }
    }
  }
}
'

response=$(curl -s -X POST "$API" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d "$(jq -n --arg query "$query" --arg search "$NAME" \
    '{query: $query, variables: {search: $search}}')")

match=$(echo "$response" | jq -r '.data.Page.media[0] // empty')

[[ -z "$match" ]] && dunstify "❌ $NAME not found" && exit 1

media_id=$(jq -r '.id' <<< "$match")
title=$(jq -r '.title.romaji' <<< "$match")
entry_id=$(jq -r '.mediaListEntry.id // empty' <<< "$match")
progress=$(jq -r '.mediaListEntry.progress // 0' <<< "$match")

new_progress=$((progress + 1))

mutation='
mutation ($id: Int, $mediaId: Int, $progress: Int) {
  SaveMediaListEntry(id: $id, mediaId: $mediaId, status: CURRENT, progress: $progress) {
    progress
  }
}
'

variables=$(jq -n \
  --argjson id "${entry_id:-null}" \
  --argjson mediaId "$media_id" \
  --argjson progress "$new_progress" \
  '{id: $id, mediaId: $mediaId, progress: $progress}')

update=$(curl -s -X POST https://graphql.anilist.co \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d "$(jq -n --arg query "$mutation" --argjson variables "$variables" \
    '{query: $query, variables: $variables}')")

if echo "$update" | jq -e '.data.SaveMediaListEntry' > /dev/null; then
  dunstify "✅ $title → Ep. $new_progress"
else
  dunstify "❌ Error updating $title"
fi
