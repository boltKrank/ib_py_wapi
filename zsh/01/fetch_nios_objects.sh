#!/bin/zsh
set -euo pipefail
trap 'echo "❌ Script failed on line $LINENO. Exiting."' ERR

# --- Default config (can be overridden by env or args) ---
HOST="${INFOBLOX_HOST:-}"
USER="${INFOBLOX_USERNAME:-admin}"
PASS="${INFOBLOX_PASSWORD:-Infoblox@312}"
WAPI_VERSION="${WAPI_VERSION:-v2.10}"
MAX_RESULTS=1000
OBJECT_TYPE=""
LIST_FILE=""
OUTDIR="object_jsons"

# --- Help text ---
usage() {
  echo "Usage: $0 [-h host] [-u user] [-p pass] [-v wapi_version] -o <object_type> | -l <object_list_file>"
  echo ""
  echo "  -o  Object type to fetch (e.g. record:a)"
  echo "  -l  File with object types to fetch (one per line)"
  echo ""
  echo "🔹 Only one of -o or -l must be provided."
  echo "🔹 Environment variables may be used for host/user/pass: INFOBLOX_HOST, INFOBLOX_USERNAME, INFOBLOX_PASSWORD"
  exit 1
}

# --- Parse flags ---
while getopts ":h:u:p:v:o:l:" opt; do 
  case $opt in
    h) HOST="$OPTARG" ;;
    u) USER="$OPTARG" ;;
    p) PASS="$OPTARG" ;;
    v) WAPI_VERSION="$OPTARG" ;;
    o) OBJECT_TYPE="$OPTARG" ;;
    l) LIST_FILE="$OPTARG" ;;
    *) usage ;;
  esac
done


# --- Validate inputs ---
if [[ -z "$HOST" ]]; then
  echo "❌ Error: Host not specified (-h or INFOBLOX_HOST)"
  usage
fi

if [[ -n "$OBJECT_TYPE" && -n "$LIST_FILE" ]]; then
  echo "❌ Error: You must provide only one of -o or -l, not both."
  usage
fi

if [[ -z "$OBJECT_TYPE" && -z "$LIST_FILE" ]]; then
  echo "❌ Error: You must specify one of -o <object_type> or -l <list_file>"
  usage
fi

mkdir -p "$OUTDIR"

fetch_object() {
  local object=$1
  local safe_name=$(echo "$object" | tr ':' '_')
  local timestamp=$(date +"%Y-%m-%dT%H-%M-%S")
  local outfile="${OUTDIR}/${safe_name}_${timestamp}.json"

  echo "📡 Fetching: $object"
  echo "  → Output: $outfile"

  local BASE_URL="https://${HOST}/wapi/${WAPI_VERSION}/${object}"
  local PARAMS="?_paging=1&_return_as_object=1&_max_results=${MAX_RESULTS}"

  local PAGE_ID=""
  local PAGE_NUM=1
  local TOTAL_COUNT=0

  touch "$outfile"
  : > "$outfile"

  while :; do
    if [[ -n "$PAGE_ID" ]]; then
      URL="${BASE_URL}${PARAMS}&_page_id=${PAGE_ID}"
    else
      URL="${BASE_URL}${PARAMS}"
    fi

    echo "🔄 Page $PAGE_NUM..."
    RESP=$(curl -sk -u "${USER}:${PASS}" "$URL")

    PAGE_ID=$(echo "$RESP" | jq -r '.next_page_id // empty')

    local PAGE_COUNT=0
    while read -r obj; do
      echo "$obj" >> "$outfile"
      ((PAGE_COUNT++))
      ((TOTAL_COUNT++))
      if (( TOTAL_COUNT % 50 == 0 )); then
        echo "  🧮 Total records so far: $TOTAL_COUNT"
      fi
    done < <(echo "$RESP" | jq -c '.result[]')

    if [[ -z "$PAGE_ID" ]]; then
      echo "✅ Done: $TOTAL_COUNT total records for $object"
      break
    fi

    ((PAGE_NUM++))
  done
}

# --- Single object fetch ---
if [[ -n "$OBJECT_TYPE" ]]; then
  fetch_object "$OBJECT_TYPE"
fi

# --- Multiple object fetch from file ---
if [[ -n "$LIST_FILE" ]]; then
  while read -r obj; do
    [[ -z "$obj" || "$obj" == \#* ]] && continue  # skip blank or commented lines
    fetch_object "$obj"
  done < "$LIST_FILE"
fi
