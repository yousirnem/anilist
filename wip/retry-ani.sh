
#!/bin/bash

LOG_FILE="$HOME/.anime_release_times.log"
USER_ID="Lochy"
API_URL="https://graphql.anilist.co"

data='{
  "query": "query ($userName: String) { MediaListCollection(userName: $userName, type: ANIME) { lists { name entries { media { title { romaji } } progress } } } }",
  "variables": { "userName": "'$USER_ID'" }
}'

response=$(curl -s -X POST "$API_URL" -H "Content-Type: application/json" --data-raw "$data")

anime_list=$(echo "$response" | jq -r '.data.MediaListCollection.lists[] | select(.name == "Watching") | .entries[] | "\(.media.title.romaji)|\(.progress)"')

# Allow user to pick an entry
echo "Select an anime by number:"
IFS=$'\n' read -r -d '' -a anime_array <<< "$anime_list"
select anime in "${anime_array[@]}"; do
  if [[ -n "$anime" ]]; then
    IFS='|' read -r anime_name anime_episode <<< "$anime"
    echo "fetching $anime_name $(($anime_episode + 1)))"
    break
  else
    echo "Invalid selection. Try again."
  fi
done

ANIME_EP=$anime_episode
ANIME_NAME=$anime_name
ENTRY="$ANIME_NAME - Episode $ANIME_EP"

if grep -Fq "$ENTRY" "$LOG_FILE"; then
    echo "$ENTRY is already marked as available. Playing now..."
else
    while true; do
        CURRENT_TIME=$(date '+%H:%M')
        RELEASE_TIME=$(grep -F "$ENTRY" "$LOG_FILE" | awk -F'Released at: ' '{print $2}' | awk '{print $2}')
        
        if [[ -n "$RELEASE_TIME" && "$CURRENT_TIME" < "$RELEASE_TIME" ]]; then
            echo "$ENTRY release time ($RELEASE_TIME) is not due yet. Waiting..."
            sleep 300
            continue
        fi
        
        ani-cli "$ANIME_NAME" -e "$ANIME_EP"
        if [ $? -ne 1 ]; then
            TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
            echo "$ENTRY - Released at: $TIMESTAMP" >> "$LOG_FILE"
            echo "$ENTRY is now available and logged at $TIMESTAMP."
            break
        fi
        echo "$ENTRY not yet available. Retrying in 60 seconds..."
        sleep 60
    done 
fi

