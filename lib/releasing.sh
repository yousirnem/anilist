#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/api.sh"

# Check for user authentication
USER_ID=$(< "$USER_FILE")

if [[ ! -f "$TOKEN_FILE" ]]; then
  bash "$LIB_DIR/auth.sh" || exit 1
fi

TODAY_TS=$(date +%s)

# Cache file for processed anime
CACHE_FILE="$DATA_DIR/anilist-auto-watch.json"
mkdir -p "$(dirname "$CACHE_FILE")"
[[ -f "$CACHE_FILE" ]] || echo "[]" > "$CACHE_FILE"

echo "=== AniList auto-watch (nextAiringEpisode) ==="
echo "User: $USER_ID"
echo "Now:  $(date)"
echo

# Get planning list
query=$(get_media_list_collection_query)
variables=$(jq -n --arg userName "$USER_ID" '{userName: $userName, status: "PLANNING"}')
response=$(call_api "$query" "$variables")

entries=$(echo "$response" | jq -c '
  .data.MediaListCollection.lists // []
  | map(.entries) | flatten
')

count=$(echo "$entries" | jq 'length')
echo "[INFO] Planning entries: $count"
echo

[[ "$count" -eq 0 ]] && exit 0

# Iterate through planning entries
echo "$entries" | jq -c '.[]' | while read -r entry; do
  entry_id=$(echo "$entry" | jq -r '.id')
  media_id=$(echo "$entry" | jq -r '.media.id')
  title=$(echo "$entry" | jq -r '.media.title.romaji')
  format=$(echo "$entry" | jq -r '.media.format')
  episodes=$(echo "$entry" | jq -r '.media.episodes')
  status=$(echo "$entry" | jq -r '.media.status')

  next_ep=$(echo "$entry" | jq -r '.media.nextAiringEpisode.episode')
  airing_at=$(echo "$entry" | jq -r '.media.nextAiringEpisode.airingAt')

  echo "----------------------------------------"
  echo "Anime: $title"
  echo "Format: $format | Episodes: $episodes | Status: $status"

  # Skip movies and single episode anime
  if [[ "$format" == "MOVIE" || "$episodes" == "1" ]]; then
    echo "[SKIP] Movie / single episode"
    continue
  fi

  # Skip if not releasing
  if [[ "$status" != "RELEASING" ]]; then
    echo "[SKIP] Not RELEASING"
    continue
  fi

  # Skip if no next airing episode
  if [[ "$airing_at" == "null" || "$next_ep" == "null" ]]; then
    echo "[SKIP] No next airing episode"
    continue
  fi

  # Skip if episode 1 not aired yet
  if [[ "$next_ep" == "1" ]]; then
    if ((airing_at > TODAY_TS)); then
      echo "[SKIP] Episode 1 not aired yet"
      continue
    fi
  else
    echo "[INFO] Episode 1 already aired (next ep: $next_ep)"
  fi

  # Skip if already processed
  if jq -e --arg id "$media_id" '.[] | select(. == ($id | tonumber))' "$CACHE_FILE" > /dev/null; then
    echo "[SKIP] Already processed"
    continue
  fi

  echo "[ACTION] Episode 1 aired → switching to WATCHING"

  # Move from planning to watching
  mutation_query=$(get_save_media_list_entry_mutation)
  variables=$(jq -n --argjson id "$entry_id" '{id: $id, status: "CURRENT"}')

  result=$(call_api "$mutation_query" "$variables")

  # Update cache if successful
  if echo "$result" | jq -e '.data.SaveMediaListEntry.status == "CURRENT"' > /dev/null; then
    echo "[SUCCESS] $title → WATCHING"
    dunstify "📺 Now Watching" "$title"

    jq --argjson id "$media_id" '. + [$id]' "$CACHE_FILE" > "$CACHE_FILE.tmp"
    mv "$CACHE_FILE.tmp" "$CACHE_FILE"
  else
    echo "[ERROR] Failed to update $title"
    echo "$result" | jq
  fi
done

echo
echo "=== Done ==="

# Schedule the next check
bash "$LIB_DIR/schedule_releases.sh"
