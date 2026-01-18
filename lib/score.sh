#!/usr/bin/env bash
set -euo pipefail

API_URL="https://graphql.anilist.co"
BASE_DIR="$HOME/.local/share/anilist"
TOKEN_FILE="$BASE_DIR/data/anilist-token"
USER_FILE="$BASE_DIR/data/anilist-user"

source "$BASE_DIR/lib/api.sh"

# --- Sanity checks ---
[[ -f "$TOKEN_FILE" ]] || {
  echo "Missing token file"
  exit 1
}
[[ -f "$USER_FILE" ]] || {
  echo "Missing username file"
  exit 1
}

TOKEN=$(< "$TOKEN_FILE")
USERNAME=$(< "$USER_FILE")

# --- Override call_api intentionally (simple + strict) ---
call_api() {
  local query="$1"
  local variables="$2"

  curl -s \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -X POST \
    --data "$(jq -n \
      --arg q "$query" \
      --argjson v "$variables" \
      '{query: $q, variables: $v}')" \
    "$API_URL"
}

# --- Queries ---

SCORE_FORMAT_QUERY=$(
  cat << 'EOF'
query {
  Viewer {
    mediaListOptions {
      scoreFormat
    }
  }
}
EOF
)

MEDIA_LIST_QUERY=$(
  cat << 'EOF'
query ($userName: String, $status: MediaListStatus) {
  MediaListCollection(userName: $userName, type: ANIME, status: $status) {
    lists {
      entries {
        score
        media {
          id
          title { romaji }
        }
      }
    }
  }
}
EOF
)

# --- Detect score format ---

score_format=$(
  call_api "$SCORE_FORMAT_QUERY" '{}' |
    jq -r '.data.Viewer.mediaListOptions.scoreFormat'
)

# --- Score rules per format ---

score_prompt=""
score_regex=""

case "$score_format" in
  POINT_10)
    score_prompt="Score (0–10)"
    score_regex='^([0-9]|10)$'
    ;;
  POINT_10_DECIMAL)
    score_prompt="Score (0–10, decimals ok)"
    score_regex='^([0-9]|10)(\.[0-9]+)?$'
    ;;
  POINT_100)
    score_prompt="Score (0–100)"
    score_regex='^([0-9]{1,2}|100)$'
    ;;
  POINT_5)
    score_prompt="Score (1–5)"
    score_regex='^[1-5]$'
    ;;
  POINT_3)
    score_prompt="Score (1–3)"
    score_regex='^[1-3]$'
    ;;
  *)
    echo "Unsupported score format: $score_format"
    exit 1
    ;;
esac

# --- Save mutation ---
save_score_mutation=$(get_save_media_list_entry_mutation_with_score)

# ------------------------------------------------------------------
# Single-anime mode: score.sh <media_id> [anime name]
# ------------------------------------------------------------------

if [[ $# -ge 1 && "$1" =~ ^[0-9]+$ ]]; then
  media_id="$1"
  anime_name="${2:-Anime}"

  score_input=$(rofi -dmenu -i -p "$anime_name — $score_prompt" -no-custom)
  [[ -z "$score_input" ]] && exit 0

  [[ "$score_input" =~ $score_regex ]] || {
    dunstify -u critical "AniList" "Invalid score format"
    exit 1
  }

  variables=$(jq -n \
    --argjson mediaId "$media_id" \
    --arg status "COMPLETED" \
    --argjson score "$score_input" \
    '{mediaId: $mediaId, status: $status, score: $score}')

  update=$(call_api "$save_score_mutation" "$variables")

  if echo "$update" | jq -e '.data.SaveMediaListEntry.id' > /dev/null; then
    dunstify -u low "AniList" "$anime_name → $score_input"
  else
    dunstify -u critical "AniList" "Failed to score $anime_name"
  fi

  exit 0
fi

# ------------------------------------------------------------------
# Batch mode: score completed anime with score == 0
# ------------------------------------------------------------------

variables=$(jq -n \
  --arg userName "$USERNAME" \
  --arg status "COMPLETED" \
  '{userName: $userName, status: $status}')

response=$(call_api "$MEDIA_LIST_QUERY" "$variables")

completed_list=$(echo "$response" | jq -r '
  .data.MediaListCollection.lists[]
  | .entries[]
  | select(.score == 0)
  | "\(.media.title.romaji)|\(.media.id)"
' || true)

[[ -z "$completed_list" ]] && exit 0

shuffled_list=$(printf "%s\n" "$completed_list" | shuf)

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue

  anime_name="${entry%%|*}"
  media_id="${entry##*|}"

  score_input=$(
    printf "\n" |
      rofi -dmenu -location 2 -i -p "$anime_name" \
        -theme-str 'window { height: 120px; } listview { lines: 1; }'
  )

  [[ "$score_input" =~ $score_regex ]] || continue

  variables=$(jq -n \
    --argjson mediaId "$media_id" \
    --arg status "COMPLETED" \
    --argjson score "$score_input" \
    '{mediaId: $mediaId, status: $status, score: $score}')

  update=$(call_api "$save_score_mutation" "$variables")

  if echo "$update" | jq -e '.data.SaveMediaListEntry.id' > /dev/null; then
    dunstify -u low "AniList" "$anime_name → $score_input"
  fi
done <<< "$shuffled_list"
