#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/../config.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

read -r USER_ID < "$USER_FILE"

query=$(cat <<EOF
query (\$userName: String) {
  MediaListCollection(userName: \$userName, type: ANIME, status: CURRENT) {
    lists {
      name
      entries {
        media {
          title {
            romaji
          }
        }
        progress
      }
    }
  }
}
EOF
)

response=$(curl -s -X POST "https://graphql.anilist.co" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg query "$query" --arg userName "$USER_ID" '{query: $query, variables: {userName: $userName}}')")

if echo "$response" | jq -e '.errors' > /dev/null; then
  dunstify -u critical "AniList error" "Error al consultar AniList"
  exit 1
fi

anime_list=$(echo "$response" | jq -r '.data.MediaListCollection.lists[] | select(.name == "Watching") | .entries[] | "\(.media.title.romaji)|\(.progress)"')

if [[ -z "$anime_list" ]]; then
  dunstify -u low "Watching Nothing"
  exec "$LIB_DIR/planning.sh"
fi

while IFS= read -r line; do
  IFS='|' read -r anime_name last_watched <<< "$line"
  next_episode=$((last_watched + 1))

  notify-send "$anime_name" "Intentando episodio $next_episode"

  output=$(ani-cli "$anime_name" -e "$next_episode" --skip --no-detach --exit-after-play -S 1 2>&1 || true)

  if echo "$output" | grep -q "Episode not released!"; then
    schedule_query=$(cat <<EOF
query (\$search: String) {
  Media(search: \$search, type: ANIME) {
    title {
      romaji
    }
    status
    nextAiringEpisode {
      episode
      airingAt
    }
  }
}
EOF
)

    schedule_response=$(curl -s -X POST "https://graphql.anilist.co" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg query "$schedule_query" --arg search "$anime_name" '{query: $query, variables: {search: $search}}')")

airing_at=$(jq -r '.data.Media.nextAiringEpisode.airingAt // empty' <<< "$schedule_response")
episode_num=$(jq -r '.data.Media.nextAiringEpisode.episode // empty' <<< "$schedule_response")

    if [[ -n "$airing_at" ]]; then
  now=$(date +%s)
  remaining=$((airing_at - now))
  airing_date=$(date -d "@$airing_at" '+%d/%m/%Y %H:%M')
  remaining_fmt=$(format_duration "$remaining")

  dunstify -u critical -a ani-cli \
    "Episodio no disponible" \
    "$anime_name — Episodio $episode_num\nSale el $airing_date\nTiempo restante: $remaining_fmt"
else
  dunstify -u normal \
    "Episodio no disponible" \
    "$anime_name — Episodio $next_episode aún no fue lanzado"
fi  fi
done <<< "$anime_list"

dunstify -u low "Terminado"
