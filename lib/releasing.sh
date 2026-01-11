#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../config.sh"

USER_ID=$(< "$USER_FILE")
ACCESS_TOKEN=$(< "$TOKEN_FILE")

TODAY_TS=$(date +%s)

CACHE_FILE="$DATA_DIR/anilist-auto-watch.json"
mkdir -p "$(dirname "$CACHE_FILE")"
[[ -f "$CACHE_FILE" ]] || echo "[]" > "$CACHE_FILE"

echo "=== AniList auto-watch (nextAiringEpisode) ==="
echo "User: $USER_ID"
echo "Now:  $(date)"
echo

query=$(
  cat << EOF
query (\$user: String) {
  MediaListCollection(userName: \$user, type: ANIME, status: PLANNING) {
    lists {
      entries {
        id
        media {
          id
          title { romaji }
          format
          episodes
          status
          nextAiringEpisode {
            episode
            airingAt
          }
        }
      }
    }
  }
}
EOF
)

response=$(curl -s -X POST "$API" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d "$(jq -n --arg query "$query" --arg user "$USER_ID" '{query: $query, variables: {user: $user}}')")

if echo "$response" | jq -e '.errors' > /dev/null; then
  echo "[ERROR] AniList returned errors:"
  echo "$response" | jq '.errors'
  exit 1
fi

entries=$(echo "$response" | jq -c '
  .data.MediaListCollection.lists // []
  | map(.entries) | flatten
')

count=$(echo "$entries" | jq 'length')
echo "[INFO] Planning entries: $count"
echo

[[ "$count" -eq 0 ]] && exit 0

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

  if [[ "$format" == "MOVIE" || "$episodes" == "1" ]]; then
    echo "[SKIP] Movie / single episode"
    continue
  fi

  if [[ "$status" != "RELEASING" ]]; then
    echo "[SKIP] Not RELEASING"
    continue
  fi

  if [[ "$airing_at" == "null" || "$next_ep" == "null" ]]; then
    echo "[SKIP] No next airing episode"
    continue
  fi

  if [[ "$next_ep" == "1" ]]; then
    if ((airing_at > TODAY_TS)); then
      echo "[SKIP] Episode 1 not aired yet"
      continue
    fi
  else
    echo "[INFO] Episode 1 already aired (next ep: $next_ep)"
  fi

  if jq -e --arg id "$media_id" '.[] | select(. == ($id | tonumber))' "$CACHE_FILE" > /dev/null; then
    echo "[SKIP] Already processed"
    continue
  fi

  echo "[ACTION] Episode 1 aired → switching to WATCHING"

  mutation_query='mutation ($id: Int) {
    SaveMediaListEntry(id: $id, status: CURRENT) {
      id
      status
    }
  }'
  variables=$(jq -n --argjson id "$entry_id" '{id: $id}')

  result=$(curl -s -X POST "$API" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$(jq -n --arg query "$mutation_query" --argjson variables "$variables" '{query: $query, variables: $variables}')")

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
