#!/usr/bin/env bash

# Root directory of the project
PREFIX="$HOME/.local/share/anilist"

# Cache / data
DATA_DIR="$PREFIX/data"
CACHE_DIR="$PREFIX/cache"
LIB_DIR="$PREFIX/lib"

# External tools
ANI_CLI="ani-cli"
ANI_SKIP="ani-skip"
MPV="mpv"
ROFI="rofi"

# AniList API
API="https://graphql.anilist.co"
CLIENT_ID="28922"
CLIENT_SECRET="D0sMSXRRCCNHw59aedmO0KigL4vsbG6QjNwi8I0r"
REDIRECT_URI="copythenext"
TOKEN_FILE="$DATA_DIR/anilist-token"
USER_FILE="$DATA_DIR/anilist-user"
