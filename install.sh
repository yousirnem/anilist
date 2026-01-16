#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

deps=(curl jq mpv rofi notify-send ani-cli)

for dep in "${deps[@]}"; do
  command -v "$dep" > /dev/null || {
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
BIN_DIR="$PREFIX/bin"

mkdir -p "$PREFIX" "$DATA_DIR" "$LIB_DIR" "$MPV_DIR" "$CACHE_DIR" "$BIN_DIR"
mkdir -p "$HOME/.config/mpv/scripts"
mkdir -p "$DESKTOP_DIR"

install -Dm755 ./anilist "$PREFIX/anilist"
install -Dm644 ./config.sh "$PREFIX/config.sh"
install -Dm644 ./lib/*.sh "$LIB_DIR/"
install -Dm644 ./mpv/anime-update.lua "$MPV_DIR/anime-update.lua"
install -Dm644 ./anilist.desktop "$DESKTOP_DIR/anilist.desktop"

ln -sf "$MPV_DIR/anime-update.lua" \
  "$HOME/.config/mpv/scripts/anime-update.lua"

echo "make sure you have .local/bin on your path"
