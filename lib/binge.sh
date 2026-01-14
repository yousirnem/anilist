#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/utils.sh"
source "$HOME/.local/share/anilist/lib/api.sh"

# Check for user authentication
if [[ ! -f "$USER_FILE" ]] || [[ ! -f "$TOKEN_FILE" ]]; then
    bash "$LIB_DIR/auth.sh" || exit 1
fi

USER_ID=$(< "$USER_FILE")

# Get list of anime to binge
query=$(get_binge_query)
variables=$(jq -n --arg userName "$USER_ID" '{userName: $userName}')
response=$(call_api "$query" "$variables")

# Parse anime list
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

# Exit if nothing to binge
[[ -z "$anime_list" ]] && {
  dunstify -u low "Nothing to binge"
  exit 0
}

# Select anime to binge
choice=$(printf "%s\n" "$anime_list" | rofi -dmenu -i -p "Binge")
[[ -z "$choice" ]] && exit 0

# Parse choice
IFS='|' read -r anime current total media_id sequel <<< "$choice"

current=${current:-0}
total=${total:-0}

# Mark anime as completed
mark_completed() {
    local mutation
    mutation=$(get_save_media_list_entry_mutation)
    local variables
    variables=$(jq -n \
        --argjson mediaId "$media_id" \
        --argjson progress "$total" \
        '{mediaId: $mediaId, progress: $progress, status: "COMPLETED"}')
    call_api "$mutation" "$variables" > /dev/null
}

# Binge watch loop
while true; do
  next=$((current + 1))

  # Check if all episodes are watched
  if ((total > 0 && next > total)); then
    mark_completed

    # Ask to continue with sequel
    if [[ -n "$sequel" ]]; then
      next_choice=$(printf "Yes\nNo" | rofi -dmenu -p "Continue with $sequel?")
      if [[ "$next_choice" == "Yes" ]]; then
        printf "%s\n" "$sequel" | "$LIB_DIR/new.sh"
      fi
    fi

    dunstify -u low "$anime completed"
    break
  fi

  # Play next episode with ani-cli
  ani-cli "$anime" \
    -e "$next" \
    --skip \
    --no-detach \
    --exit-after-play \
    --rofi

  current=$next
done
