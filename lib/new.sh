#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/api.sh"

if [[ ! -f "$TOKEN_FILE" ]]; then
  bash "$LIB_DIR/auth.sh" || exit 1
fi

# Search input
options="Search
Recommendations"
choice=$(echo "$options" | rofi -dmenu -i -p "Choose an option")

[ -z "$choice" ] && exit 0

if [[ "$choice" == "Search" ]]; then
  search=$(rofi -dmenu -i -p "Search anime")
  [ -z "$search" ] && exit 0

  # AniList search query
  query=$(get_new_search_query)
  variables=$(jq -n --arg s "$search" '{search: $s}')
  response=$(call_api "$query" "$variables")

  # Parse results
  mapfile -t results < <(
    echo "$response" | jq -r '
      .data.Page.media[]
      | "\(.id)::\(.title.romaji // .title.english // .title.native)"
    '
  )
elif [[ "$choice" == "Recommendations" ]]; then
  # Get user's anime list
  username=$(< "$USER_FILE")
  user_anime_query=$(get_all_user_media_query)
  user_anime_variables=$(jq -n --arg u "$username" '{userName: $u}')
  user_anime_response=$(call_api "$user_anime_query" "$user_anime_variables")
  user_anime_ids=$(echo "$user_anime_response" | jq '[.data.MediaListCollection.lists[].entries[].media.id]')

  # Get recommendations
  query=$(get_user_recommendations_query)
  variables="{}"
  response=$(call_api "$query" "$variables")

  # Parse and filter results
  mapfile -t results < <(
    echo "$response" | jq -r --argjson watched_ids "$user_anime_ids" '
      .data.Page.recommendations | map(
        select(.mediaRecommendation.id as $id | $watched_ids | index($id) | not)
      )[] | .mediaRecommendation | "\(.id)::\(.title.romaji // .title.english // .title.native)"
    '
  )
fi

count="${#results[@]}"

[ "$count" -eq 0 ] && {
  dunstify -u low "AniList" "No results found"
  exit 1
}

# Auto-pick if only 1 result
if [ "$count" -eq 1 ]; then
  choice="${results[0]}"
else
  choice=$(printf "%s\n" "${results[@]}" | rofi -dmenu -i -p "Choose anime")
  [ -z "$choice" ] && exit 0
fi

# Extract ID and title
media_id="${choice%%::*}"
title="${choice#*::}"

# Set status to WATCHING
mutation=$(get_save_media_list_entry_mutation)
variables=$(jq -n --argjson mediaId "$media_id" '{mediaId: $mediaId, status: "CURRENT"}')
call_api "$mutation" "$variables" > /dev/null

# Play with ani-cli
ani-cli "$title" \
  --no-detach \
  --exit-after-play
