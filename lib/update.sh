#!/usr/bin/env bash
set -uo pipefail

LOG="$HOME/.local/share/anilist/logs/update-debug.log"
exec >> "$LOG" 2>&1
echo "---- $(date) ----"

source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/api.sh"

# Input arguments
NAME="$1"
EPISODE="$2"

[[ -z "$NAME" || -z "$EPISODE" ]] && exit 1

# Check for user authentication
if [[ ! -f "$TOKEN_FILE" ]]; then
  bash "$LIB_DIR/auth.sh" || exit 1
fi

# Search for anime
query=$(get_search_query)
variables=$(jq -n --arg search "$NAME" '{search: $search}')
response=$(call_api "$query" "$variables")

# Get first match
match=$(echo "$response" | jq -r '.data.Page.media[0] // empty')

[[ -z "$match" ]] && dunstify "❌ $NAME not found" && exit 1

# Parse match data
media_id=$(jq -r '.id' <<< "$match")
title=$(jq -r '.title.romaji' <<< "$match")
entry_id=$(jq -r '.mediaListEntry.id // empty' <<< "$match")
progress=$(jq -r '.mediaListEntry.progress // 0' <<< "$match")

# Calculate new progress
new_progress=$((progress + 1))

# Update progress on AniList
mutation=$(get_save_media_list_entry_mutation)
variables=$(jq -n \
  --argjson id "${entry_id:-null}" \
  --argjson mediaId "$media_id" \
  --argjson progress "$new_progress" \
  '{id: $id, mediaId: $mediaId, progress: $progress, status: "CURRENT"}')

update=$(call_api "$mutation" "$variables")

# Notify user of the result
if echo "$update" | jq -e '.data.SaveMediaListEntry' > /dev/null; then
  dunstify "✅ $title → Ep. $new_progress"
else
  dunstify "❌ Error updating $title"
fi
