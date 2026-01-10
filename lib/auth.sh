#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../config.sh"

CODE="$*"

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

if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
  echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo "✅ Access token saved"
else
  echo "❌ Failed to get access token"
  echo
  echo "$RESPONSE" | jq
  exit 1
fi

echo "🔎 Testing access token..."

TEST_RESPONSE=$(curl -s -X POST https://graphql.anilist.co \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  --data-raw '{"query":"{ Viewer { id name } }"}')

if echo "$TEST_RESPONSE" | jq -e '.data.Viewer.id' > /dev/null; then
  USERNAME=$(echo "$TEST_RESPONSE" | jq -r '.data.Viewer.name')
  echo "✅ Token is valid (logged in as $USERNAME)"
  echo "$USERNAME" > "$USER_FILE"
  chmod 600 "$USER_FILE"
else
  echo "❌ Token test failed"
  echo
  echo "$TEST_RESPONSE" | jq
  exit 1
fi
