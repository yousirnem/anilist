#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/utils.sh"

USER_ID=$(< "$USER_FILE")

# Check for newly released episodes
bash "$LIB_DIR/releasing.sh"

query=$(
  cat << EOF
query (\$userName: String) {
  MediaListCollection(userName: \$userName, type: ANIME, status: CURRENT) {
    lists {
      name
      entries {
        progress
        media {
          title {
            romaji
          }
          status
        }
      }
    }
  }
}
EOF
)

response=$(curl -s -X POST https://graphql.anilist.co \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg query "$query" \
    --arg userName "$USER_ID" \
    '{query: $query, variables: {userName: $userName}}')")

if echo "$response" | jq -e '.errors' > /dev/null; then
  dunstify -u critical "AniList error" "Failed to fetch Watching list"
  exit 1
fi

airing_list=$(echo "$response" | jq -r '
  .data.MediaListCollection.lists[]
  | select(.name == "Watching")
  | .entries[]
  | select(.media.status == "RELEASING")
  | "\(.media.title.romaji)|\(.progress)"
')

finished_list=$(echo "$response" | jq -r '
  .data.MediaListCollection.lists[]
  | select(.name == "Watching")
  | .entries[]
  | select(.media.status == "FINISHED")
  | "\(.media.title.romaji)|\(.progress)"
')

# Route finished shows to binge.sh
if [[ -n "$finished_list" ]]; then
  export BINGE_LIST="$finished_list"
  "$LIB_DIR/binge.sh"
fi

[[ -z "$airing_list" ]] && {
  dunstify -u low "No airing anime"
  exit 0
}

not_released=()

while IFS= read -r line; do
  IFS='|' read -r anime last <<< "$line"
  next_ep=$((last + 1))

  output=$(ani-cli "$anime" \
    -e "$next_ep" \
    --skip \
    --no-detach \
    --exit-after-play \
    -S 1 2>&1 || true)

  if grep -q "Episode not released!" <<< "$output"; then
    schedule_query=$(
      cat << EOF
query (\$search: String) {
  Media(search: \$search, type: ANIME) {
    nextAiringEpisode {
      episode
      airingAt
    }
  }
}
EOF
    )

    schedule_response=$(curl -s -X POST https://graphql.anilist.co \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg query "$schedule_query" \
        --arg search "$anime" \
        '{query: $query, variables: {search: $search}}')")

    airing_at=$(jq -r '.data.Media.nextAiringEpisode.airingAt // empty' <<< "$schedule_response")
    ep_num=$(jq -r '.data.Media.nextAiringEpisode.episode // empty' <<< "$schedule_response")

    if [[ -n "$airing_at" ]]; then
      now=$(date +%s)
      remaining=$((airing_at - now))
      date_fmt=$(date -d "@$airing_at" '+%d/%m/%Y %H:%M')
      remaining_fmt=$(format_duration "$remaining")

      not_released+=(
        "$anime — Ep. $ep_num
On: $date_fmt ($remaining_fmt remaining)"
      )
    else
      not_released+=("$anime — Ep. $next_ep not yet available")
    fi
  fi
done <<< "$airing_list"

if ((${#not_released[@]})); then
  dunstify -u low -a ani-cli "Upcoming episodes" "$(printf "%s\n\n" "${not_released[@]}")"
fi
