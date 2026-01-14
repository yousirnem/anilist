#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/api.sh"

if [[ ! -f "$USER_FILE" ]] || [[ ! -f "$TOKEN_FILE" ]]; then
    bash "$LIB_DIR/auth.sh" || exit 1
fi

USER_ID=$(< "$USER_FILE")
NOW_TS=$(date +%s)

# Get all airing anime from PLANNING and CURRENT lists
query=$(get_schedule_check_query)
variables=$(jq -n --arg userName "$USER_ID" '{userName: $userName}')
response=$(call_api "$query" "$variables")

# Find the earliest upcoming airing time
next_airing_ts=$(echo "$response" | jq -r '
    .data.MediaListCollection.lists[].entries[].media
    | .nextAiringEpisode.airingAt
' | grep -v null | awk -v now="$NOW_TS" '$1 > now' | sort -n | head -n 1)

# If no upcoming releases are found, schedule the next check for 1 day from now
if [[ -z "$next_airing_ts" ]]; then
    next_airing_ts=$((NOW_TS + 86400)) # 24 hours in seconds
fi

# Save the next check timestamp to the cache file
echo "$next_airing_ts" > "$NEXT_RELEASE_CHECK_FILE"
echo "Next release check scheduled for: $(date -d "@$next_airing_ts")" >> "$LOG_FILE"
