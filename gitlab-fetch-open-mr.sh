#!/bin/bash
# Export the gitlab toke in CLI first
# export GITLAB_MR_TOKEN="glpat-xxxxxxxxxxxxxxxx"
# then run script ./gitlab-fetch-open-mr.sh
set -e

# =====================
# Config
# =====================
GITLAB_URL="https://gitlab.example.com"
TOKEN="${GITLAB_MR_TOKEN:?Error: GITLAB_MR_TOKEN environment variable not set}"
GROUP_ID="12345"
PER_PAGE=100
OUTPUT_FILE="open_mrs.csv"

# =====================
# CSV Header
# =====================
echo "project_name,mr_title,author,opened_date,mr_number,mr_url" > "$OUTPUT_FILE"

# =====================
# Function: API Call
# =====================
gitlab_api() {
    local endpoint="$1"
    curl -s --header "PRIVATE-TOKEN: $TOKEN" \
        "$GITLAB_URL/api/v4/$endpoint"
}

# =====================
# Fetch All Projects in Group
# =====================
page=1

while true; do
    projects=$(gitlab_api "groups/$GROUP_ID/projects?include_subgroups=true&per_page=$PER_PAGE&page=$page")

    count=$(echo "$projects" | jq length)

    if [[ "$count" -eq 0 ]]; then
        break
    fi

    echo "$projects" | jq -r '.[] | [.id, .path_with_namespace] | @tsv' | \
    while IFS=$'\t' read -r project_id project_name; do

        echo "Checking project: $project_name"

        mrs=$(gitlab_api "projects/$project_id/merge_requests?state=opened&per_page=100")

        mr_count=$(echo "$mrs" | jq length)

        if [[ "$mr_count" -gt 0 ]]; then
            echo "$mrs" | jq -r --arg project "$project_name" '
                .[] |
                [
                    $project,
                    (.title | gsub("\""; "\"\"")),
                    .author.name,
                    .created_at,
                    .iid,
                    .web_url
                ] | @csv
            ' >> "$OUTPUT_FILE"
        fi

    done

    ((page++))
done

echo "CSV generated: $OUTPUT_FILE"
