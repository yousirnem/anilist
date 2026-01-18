#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"

main() {
  local title="$1"
  local episode="$2"

  dunstify "Checking for episode availability" "Anime: $title\nEpisode: $episode"

  while ! ani-cli --dub-lang en --language en -e "$episode" "$title" --play; do
    dunstify "Episode not available yet" "Will retry in 10 minutes..."
    sleep 600
    dunstify "Retrying now..."
  done
}

main "$@"
