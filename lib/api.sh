#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.local/share/anilist/config.sh"

# Call AniList API
call_api() {
  local query="$1"
  local variables="$2"
  local headers=(-s -X POST -H "Content-Type: application/json")

  if [[ -f "$TOKEN_FILE" ]]; then
    ACCESS_TOKEN=$(< "$TOKEN_FILE")
    headers+=(-H "Authorization: Bearer $ACCESS_TOKEN")
  fi

  local json_payload
  json_payload=$(jq -n \
    --arg query "$query" \
    --argjson variables "$variables" \
    '{query: $query, variables: $variables}')

  local response
  response=$(curl "${headers[@]}" -d "$json_payload" "$API")

  echo "API Response: $response" >> "$LOG_FILE"

  if echo "$response" | jq -e '.errors' > /dev/null; then
    dunstify -u critical "AniList API error" "$(echo "$response" | jq -r '.errors[0].message')"
    exit 1
  fi

  echo "$response"
}

# Get query for media list collection
get_media_list_collection_query() {
  cat << 'EOF'
query ($userName: String, $status: MediaListStatus) {
  MediaListCollection(userName: $userName, type: ANIME, status: $status) {
    lists {
      name
      entries {
        id
        progress
        score
        media {
          id
          title {
            romaji
          }
          status
          format
          episodes
          nextAiringEpisode {
            episode
            airingAt
          }
        }
      }
    }
  }
}
EOF
}

# Get query for airing schedule
get_schedule_query() {
  cat << 'EOF'
query ($search: String) {
  Media(search: $search, type: ANIME) {
    nextAiringEpisode {
      episode
      airingAt
    }
  }
}
EOF
}

# Get query for search
get_search_query() {
  cat << 'EOF'
query ($search: String) {
  Page(perPage: 10) {
    media(search: $search, type: ANIME) {
      id
      title { romaji }
      mediaListEntry {
        id
        progress
      }
    }
  }
}
EOF
}

# Get mutation for saving media list entry
get_save_media_list_entry_mutation() {
  cat << 'EOF'
mutation ($id: Int, $mediaId: Int, $progress: Int, $status: MediaListStatus) {
  SaveMediaListEntry(id: $id, mediaId: $mediaId, progress: $progress, status: $status) {
    id
    progress
    status
  }
}
EOF
}

# Get mutation for saving media list entry with score
get_save_media_list_entry_mutation_with_score() {
  cat << 'EOF'
mutation ($id: Int, $mediaId: Int, $progress: Int, $status: MediaListStatus, $score: Float) {
  SaveMediaListEntry(id: $id, mediaId: $mediaId, progress: $progress, status: $status, score: $score) {
    id
    progress
    status
    score
  }
}
EOF
}

# Get query for new search
get_new_search_query() {
  cat << 'EOF'
query ($search: String) {
  Page(perPage: 10) {
    media(search: $search, type: ANIME) {
      id
      title {
        romaji
        english
        native
      }
    }
  }
}
EOF
}

# Get query for binge command
get_binge_query() {
  cat << 'EOF'
query ($userName: String) {
  MediaListCollection(userName: $userName, type: ANIME, status: CURRENT) {
    lists {
      name
      entries {
        progress
        media {
          id
          episodes
          status
          title {
            romaji
          }
          relations {
            edges {
              relationType
              node {
                status
                title {
                  romaji
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF
}

get_schedule_check_query() {
  cat << 'EOF'
query ($userName: String) {
  MediaListCollection(userName: $userName, type: ANIME, status_in: [PLANNING, CURRENT]) {
    lists {
      entries {
        media {
          nextAiringEpisode {
            airingAt
          }
        }
      }
    }
  }
}
EOF
}

get_user_recommendations_query() {
  cat << 'EOF'
query {
  Page(page: 1, perPage: 20) {
    recommendations(sort: RATING_DESC) {
      id
      mediaRecommendation {
        id
        title {
          romaji
          english
          native
        }
        type
      }
    }
  }
}
EOF
}

get_all_user_media_query() {
  cat << 'EOF'
query ($userName: String) {
  MediaListCollection(userName: $userName, type: ANIME, status_in: [PLANNING, CURRENT, COMPLETED, PAUSED, DROPPED]) {
    lists {
      entries {
        media {
          id
        }
      }
    }
  }
}
EOF
}

