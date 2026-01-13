#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/utils.sh"

USER_ID=$(< "$USER_FILE")
TOKEN=$(< "$TOKEN_FILE")

query=$(
  cat << 'EOF'
query ($userName: String) {
  MediaListCollection(userName: $userName, type: ANIME, status: CURRENT) {
    lists {
      name
      entries {
        progress
        media {
          id
          episodes
          status
          title {
            romaji
          }
          relations {
            edges {
              relationType
              node {
                status
                title {
                  romaji
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF
)

response=$(curl -s -X POST https://graphql.anilist.co \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg query "$query" \
    --arg userName "$USER_ID" \
    '{query: $query, variables: {userName: $userName}}')")

if echo "$response" | jq -e '.errors' > /dev/null; then
  dunstify -u critical "AniList error" "Failed to fetch anime"
  exit 1
fi

anime_list=$(echo "$response" | jq -r '
  .data.MediaListCollection.lists[]
  | select(.name == "Watching")
  | .entries[]
  | select(.media.status == "FINISHED")
  | "\(.media.title.romaji)|\(.progress)|\(.media.episodes // 0)|\(.media.id)|\(
      .media.relations.edges
      | map(select(.relationType=="SEQUEL" and (.node.status=="FINISHED" or .node.status=="RELEASING")))
      | .[0].node.title.romaji // ""
    )"
')

[[ -z "$anime_list" ]] && {
  dunstify -u low "Nothing to binge"
  exit 0
}

choice=$(printf "%s\n" "$anime_list" | rofi -dmenu -i -p "Binge")
[[ -z "$choice" ]] && exit 0

IFS='|' read -r anime current total media_id sequel <<< "$choice"

current=${current:-0}
total=${total:-0}

mark_completed() {
  curl -s -X POST https://graphql.anilist.co \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --argjson mediaId "$media_id" \
      --argjson progress "$total" \
      '{
        query: "mutation ($mediaId: Int, $progress: Int) { SaveMediaListEntry(mediaId: $mediaId, status: COMPLETED, progress: $progress) { id } }",
        variables: { mediaId: $mediaId, progress: $progress }
      }')" > /dev/null
}

while true; do
  next=$((current + 1))

  if ((total > 0 && next > total)); then
    mark_completed

    if [[ -n "$sequel" ]]; then
      next_choice=$(printf "Yes\nNo" | rofi -dmenu -p "Continue with $sequel?")
      if [[ "$next_choice" == "Yes" ]]; then
        printf "%s\n" "$sequel" | "$LIB_DIR/new.sh"
      fi
    fi

    dunstify -u low "$anime completed"
    break
  fi

  ani-cli "$anime" \
    -e "$next" \
    --skip \
    --no-detach \
    --exit-after-play \
    --rofi

  current=$next
done
