#!/usr/bin/env bash
set -euo pipefail
source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/utils.sh"

USER_ID=$(< "$USER_FILE")

bash $LIB_DIR/releasing.sh

query=$(
  cat << EOF
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
  dunstify -u low "Nothing on Watching"
  exec "$LIB_DIR/planning.sh"
fi

not_released=()
while IFS= read -r line; do
  IFS='|' read -r anime_name last_watched <<< "$line"
  next_episode=$((last_watched + 1))

  output=$(ani-cli "$anime_name" -e "$next_episode" --skip --no-detach --exit-after-play -S 1 2>&1 || true)

  if echo "$output" | grep -q "Episode not released!"; then
    schedule_query=$(
      cat << EOF
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

      not_released+=(
        "$anime_name — Ep. $episode_num
	on: $airing_date, $remaining_fmt remaining"
      )
    else
      not_released+=(
        "$anime_name — Ep. $next_episode not yet avalible"
      )
    fi
  fi
done <<< "$anime_list"

if ((${#not_released[@]} > 0)); then
  message=$(printf "%s\n\n" "${not_released[@]}")

  dunstify -u critical -a ani-cli \
    "Not Avalibe" \
    "$message"
else
  dunstify -u low "Nothing on Watching"
fi
