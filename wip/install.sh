#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

deps=(curl jq dunstify ani-cli mpv rofi ani-skip)

for dep in "${deps[@]}"; do
  command -v "$dep" >/dev/null || {
    echo "Missing dependency: $dep" >&2
    exit 1
  }
done

PREFIX="$HOME/.local/share/anilist"
DATA_DIR="$PREFIX/data"
LIB_DIR="$PREFIX/lib"
MPV_DIR="$PREFIX/mpv"
CACHE_DIR="$PREFIX/cache"
DESKTOP_DIR="$HOME/.local/share/applications"

mkdir -p "$PREFIX" "$DATA_DIR" "$LIB_DIR" "$MPV_DIR" "$CACHE_DIR"
mkdir -p "$HOME/.config/mpv/scripts"
mkdir -p "$DESKTOP_DIR"

install -Dm755 ./anilist "$PREFIX/anilist"
install -Dm644 ./config.sh "$PREFIX/config.sh"
install -Dm644 ./lib/*.sh "$LIB_DIR/"
install -Dm644 ./mpv/anime-update.lua "$MPV_DIR/anime-update.lua"
install -Dm644 ./anilist.desktop "$DESKTOP_DIR/anilist.desktop"

ln -sf "$MPV_DIR/anime-update.lua" \
       "$HOME/.config/mpv/scripts/anime-update.lua"

command -v update-desktop-database >/dev/null && \
  update-desktop-database "$HOME/.local/share/applications"

