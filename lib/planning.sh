#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/utils.sh"
source "$HOME/.local/share/anilist/lib/api.sh"

# Check for user authentication
if [[ ! -f "$USER_FILE" ]] || [[ ! -f "$TOKEN_FILE" ]]; then
  bash "$LIB_DIR/auth.sh" || exit 1
fi

USERNAME=$(< "$USER_FILE") # AniList username

# Choose between Serie and Movie
choice=$(printf "Serie\nMovie" | rofi -dmenu -i -p "Choose")
[[ -z "$choice" ]] && exit 0

dunstify -u low "Looking Planning List..."

# Get planning list
query=$(get_media_list_collection_query)
variables=$(jq -n --arg userName "$USERNAME" '{userName: $userName, status: "PLANNING"}')
response=$(call_api "$query" "$variables")

# Handle series
if [[ "$choice" == "Serie" ]]; then
  list=$(echo "$response" | jq -r '
    .data.MediaListCollection.lists[]
    | .entries[]
    | select(.media.format != "MOVIE")
    | "\(.media.title.romaji)|\(.media.id)"
  ')

  [[ -z "$list" ]] && dunstify -u low "Nothing in Planning" && exit 0

  selection=$(printf '%s\n' "$list" | rofi -dmenu -i -p "Serie")
  [[ -z "$selection" ]] && exit 0
  [[ "$selection" != *"|"* ]] && exit 1

  anime_name="${selection%%|*}"
  media_id="${selection##*|}"

  # Move from planning to watching
  mutation=$(get_save_media_list_entry_mutation)
  variables=$(jq -n --argjson mediaId "$media_id" '{mediaId: $mediaId, status: "CURRENT"}')
  update=$(call_api "$mutation" "$variables")

  if ! echo "$update" | jq '.data.SaveMediaListEntry' > /dev/null; then
    dunstify -u critical "AniList Update Failed"
    exit 1
  fi

  # Play with ani-cli
  dunstify -u low "▶️ $anime_name → Watching"
  ani-cli "$anime_name" --rofi --no-detach --exit-after-play

# Handle movies
else
  list=$(echo "$response" | jq -r '
    .data.MediaListCollection.lists[]
    | .entries[]
    | select(.media.format == "MOVIE")
    | .media.title.romaji
  ')

  [[ -z "$list" ]] && dunstify -u low "No Movie in Planning" && exit 0

  anime_name=$(printf '%s\n' "$list" | rofi -dmenu -i -p "Movie")
  [[ -z "$anime_name" ]] && exit 0

  # Play with ani-cli
  ani-cli "$anime_name" --no-detach --exit-after-play -S 1
fi
