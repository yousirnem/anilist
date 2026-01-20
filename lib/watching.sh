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
  | "\(.media.title.romaji)|\(.progress)|\(.media.id)"
')

[[ -z "$airing_list" ]] && {
  dunstify -u low "No airing anime"
}

not_released=()

play_episode() {
  local anime="$1"
  local last="$2"
  local media_id="$3"
  local next_ep=$((last + 1))

  local output
  output=$(ani-cli "$anime" -e "$next_ep" --no-detach --exit-after-play -S 1 2>&1 || true)

  if grep -q "Episode not released!" <<< "$output"; then
    local next_airing_episode
    next_airing_episode=$(get_next_airing_episode "$media_id")

    if [[ -n "$next_airing_episode" && "$next_airing_episode" -eq $((last + 2)) ]]; then
      "$LIB_DIR/wait_for_episode.sh" "$anime" "$next_ep"
    else
      # Original logic for not released episodes
      local schedule_query
      schedule_query=$(get_schedule_query)
      local variables
      variables=$(jq -n --arg search "$anime" '{search: $search}')
      local schedule_response
      schedule_response=$(call_api "$schedule_query" "$variables")

      local airing_at
      airing_at=$(jq -r '.data.Media.nextAiringEpisode.airingAt // empty' <<< "$schedule_response")
      local ep_num
      ep_num=$(jq -r '.data.Media.nextAiringEpisode.episode // empty' <<< "$schedule_response")

      if [[ -n "$airing_at" ]]; then
        local now
        now=$(date +%s)
        local remaining
        remaining=$((airing_at - now))
        local date_fmt
        date_fmt=$(date -d "@$airing_at" '+%d/%m/%Y %H:%M')
        local remaining_fmt
        remaining_fmt=$(format_duration "$remaining")
        not_released+=("${anime:0:8}... [$ep_num] on $remaining_fmt")
      else
        not_released+=("$anime — Ep. $next_ep not yet available")
      fi
    fi
  fi
}

# Iterate through airing anime and try to play the next episode
while IFS= read -r line; do
  IFS='|' read -r anime last media_id <<< "$line"
  play_episode "$anime" "$last" "$media_id"
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
