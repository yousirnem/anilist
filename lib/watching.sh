#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/utils.sh"
source "$HOME/.local/share/anilist/lib/api.sh"

USER_ID=$(< "$USER_FILE")

# Check for newly released episodes based on schedule
if [[ ! -f "$NEXT_RELEASE_CHECK_FILE" ]]; then
  bash "$LIB_DIR/schedule_releases.sh"
fi

NEXT_CHECK_TS=$(< "$NEXT_RELEASE_CHECK_FILE")
NOW_TS=$(date +%s)

if ((NOW_TS >= NEXT_CHECK_TS)); then
  bash "$LIB_DIR/releasing.sh"
fi

# Get currently watching list
query=$(get_media_list_collection_query)
variables=$(jq -n --arg userName "$USER_ID" --arg status "CURRENT" '{userName: $userName, status: $status}')
response=$(call_api "$query" "$variables")

# Filter for airing anime
airing_list=$(echo "$response" | jq -r '
  .data.MediaListCollection.lists[]
  | select(.name == "Watching")
  | .entries[]
  | select(.media.status == "RELEASING")
  | "\(.media.title.romaji)|\(.progress)"
')

[[ -z "$airing_list" ]] && {
  dunstify -u low "No airing anime"
}

not_released=()

# Iterate through airing anime and try to play the next episode
while IFS= read -r line; do
  IFS='|' read -r anime last <<< "$line"
  next_ep=$((last + 1))

  # Try to play with ani-cli
  output=$(ani-cli "$anime" \
    -e "$next_ep" \
    --no-detach \
    --exit-after-play \
    -S 1 2>&1 || true)

  # If episode is not released, get airing schedule
  if grep -q "Episode not released!" <<< "$output"; then
    schedule_query=$(get_schedule_query)
    variables=$(jq -n --arg search "$anime" '{search: $search}')
    schedule_response=$(call_api "$schedule_query" "$variables")

    airing_at=$(jq -r '.data.Media.nextAiringEpisode.airingAt // empty' <<< "$schedule_response")
    ep_num=$(jq -r '.data.Media.nextAiringEpisode.episode // empty' <<< "$schedule_response")

    # Format and add to not_released list
    if [[ -n "$airing_at" ]]; then
      now=$(date +%s)
      remaining=$((airing_at - now))
      date_fmt=$(date -d "@$airing_at" '+%d/%m/%Y %H:%M')
      remaining_fmt=$(format_duration "$remaining")
      not_released+=("${anime:0:8}... [$ep_num] on $remaining_fmt")
    else
      not_released+=("$anime — Ep. $next_ep not yet available")
    fi
  fi
done <<< "$airing_list"

# Notify about upcoming episodes
if ((${#not_released[@]})); then
  dunstify -u low -a ani-cli "Upcoming episodes" "$(printf "%s\n\n" "${not_released[@]}")"
fi

# Filter for finished anime in watching list
finished_list=$(echo "$response" | jq -r '
  .data.MediaListCollection.lists[]
  | select(.name == "Watching")
  | .entries[]
  | select(.media.status == "FINISHED")
  | "\(.media.title.romaji)|\(.progress)"
')

# If there are finished anime, start binge mode
if [[ -n "$finished_list" ]]; then
  export BINGE_LIST="$finished_list"
  "$LIB_DIR/binge.sh"
fi
