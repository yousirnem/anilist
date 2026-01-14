#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"
source "$HOME/.local/share/anilist/lib/utils.sh"

# Check if access token exists
ACCESS_TOKEN=$(< "$TOKEN_FILE")
if [ -z "$ACCESS_TOKEN" ]; then

  # If no access token, start authorization flow
  CODE="$*"

  # Prompt for authorization code if not provided
  if [ -z "$CODE" ]; then
    echo "Authorizing:"
    echo "1. Log in https://anilist.co"
    echo "2. Open this URL: https://anilist.co/api/v2/oauth/authorize?client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&response_type=code"
    read -rp "3. Paste the code: " CODE
  fi

  if [ -z "$CODE" ]; then
    echo "❌ No code provided. Aborting."
    exit 1
  fi

  echo "⏳ Requesting access token..."

  # Request access token from AniList
  RESPONSE=$(curl -s -X POST https://anilist.co/api/v2/oauth/token \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d '{
    "grant_type": "authorization_code",
    "client_id": "'"$CLIENT_ID"'",
    "client_secret": "'"$CLIENT_SECRET"'",
    "redirect_uri": "'"$REDIRECT_URI"'",
    "code": "'"$CODE"'"
  }')

  ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')

  # Save access token if successful
  if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
    echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    echo "✅ Access token saved"
  else
    echo "❌ Failed to get access token"
    echo "$RESPONSE" | jq
    exit 1
  fi

else
  # If access token exists, test it
  echo "🔎 Testing access token..."
  TEST_RESPONSE=$(curl -s -X POST https://graphql.anilist.co \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --data-raw '{"query":"{ Viewer { id name } }"}')

  # Check if token is valid and save username
  if echo "$TEST_RESPONSE" | jq -e '.data.Viewer.id' > /dev/null; then
    USERNAME=$(jq -r '.data.Viewer.name' <<< "$TEST_RESPONSE")
    echo "✅ Token is valid (logged in as $USERNAME)"
    echo "$USERNAME" > "$USER_FILE"
    chmod 600 "$USER_FILE"
  else
    # If token is invalid, cleanup and re-authenticate
    echo "❌ Token test failed"
    echo "$TEST_RESPONSE" | jq
    cleanup_auth
    echo "🔁 Re-authenticating..."
    exec "$0" "$@"
  fi
fi
