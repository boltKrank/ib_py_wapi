#!/bin/zsh
set -euo pipefail
trap 'echo "❌ Script failed on line $LINENO. Exiting."' ERR

# --- Default config ---
HOST="${INFOBLOX_HOST:-}"
USER="${INFOBLOX_USERNAME:-admin}"
PASS="${INFOBLOX_PASSWORD:-Infoblox@312}"
WAPI_VERSION="${WAPI_VERSION:-v2.10}"
MAX_RESULTS=1000
OBJECT_TYPE=""

# --- Help text ---
usage() {
  echo "Usage: $0 [-h host] [-u username] [-p password] [-v wapi_version] -o <object_type>"
  echo "Example: $0 -h nios.local -u admin -p Infoblox@312 -v v2.12 -o record:a"
  exit 1
}

# --- Parse CLI flags ---
while getopts ":h:u:p:v:o:" opt; do
  case $opt in
    h) HOST="$OPTARG" ;;
    u) USER="$OPTARG" ;;
    p) PASS="$OPTARG" ;;
    v) WAPI_VERSION="$OPTARG" ;;
    o) OBJECT_TYPE="$OPTARG" ;;
    *) usage ;;
  esac
done

# --- Validate ---
[[ -z "$OBJECT_TYPE" ]] && { echo "❌ Object type required (-o)"; usage; }
[[ -z "$HOST" ]] && { echo "❌ Host required (-h or INFOBLOX_HOST)"; usage; }

# --- Output file setup ---
SAFE_NAME=$(echo "$OBJECT_TYPE" | tr ':' '_')
TIMESTAMP=$(date +"%Y-%m-%dT%H-%M-%S")
OUTDIR="object_jsons"
OUTFILE="${OUTDIR}/${SAFE_NAME}_${TIMESTAMP}.json"
mkdir -p "$OUTDIR"
: > "$OUTFILE"

# --- Move older files into archive ---
SUBDIR="${OUTDIR}/old_${SAFE_NAME}_jsons"
mkdir -p "$SUBDIR"
for f in ${OUTDIR}/${SAFE_NAME}_*.json(.N); do
  [[ "$f" != "$OUTFILE" ]] && mv "$f" "$SUBDIR/"
done

echo "🔧 HOST=$HOST | USER=$USER | OBJECT=$OBJECT_TYPE | WAPI=$WAPI_VERSION"
echo "💾 Output file: $OUTFILE"

# --- WAPI URL setup ---
BASE_URL="https://${HOST}/wapi/${WAPI_VERSION}/${OBJECT_TYPE}"
PARAMS="?_paging=1&_return_as_object=1&_max_results=${MAX_RESULTS}"

PAGE_ID=""
PAGE_NUM=1
TOTAL_COUNT=0

echo "📡 Starting fetch..."

while :; do
  # Build URL
  if [[ -n "$PAGE_ID" ]]; then
    URL="${BASE_URL}${PARAMS}&_page_id=${PAGE_ID}"
  else
    URL="${BASE_URL}${PARAMS}"
  fi

  echo "🔄 Page $PAGE_NUM - Requesting: $URL"
  RESP=$(curl -sk -u "${USER}:${PASS}" "$URL")

  # Validate response
  if ! echo "$RESP" | jq -e '.result | type == "array"' >/dev/null 2>&1; then
    echo "❌ ERROR: Unexpected response or object type"
    echo "$RESP" | jq . || echo "$RESP"
    exit 1
  fi

  # Extract next page ID
  PAGE_ID=$(echo "$RESP" | jq -r '.next_page_id // empty')
  echo "🔍 Next page ID: '$PAGE_ID'"

  # Process records
  PAGE_COUNT=0
  RECORDS=()
  while IFS= read -r line; do
    RECORDS+=("$line")
  done <<< "$(echo "$RESP" | jq -c '.result[]')"

  for obj in "${RECORDS[@]}"; do
    echo "$obj"
    echo "$obj" >> "$OUTFILE"
    PAGE_COUNT=$((PAGE_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if (( TOTAL_COUNT % 50 == 0 )); then
      echo "🧮 Total so far: $TOTAL_COUNT"
    fi
  done

  echo "📦 Page $PAGE_NUM had $PAGE_COUNT records."

  if [[ -z "$PAGE_ID" ]]; then
    echo "✅ All pages retrieved."
    break
  fi

  PAGE_NUM=$((PAGE_NUM + 1))
done

echo "📊 Total \"$OBJECT_TYPE\" records fetched: $TOTAL_COUNT"
echo "💾 Final file saved to: $OUTFILE"
