#!/bin/bash
set -euo pipefail

HOST="${INFOBLOX_HOST:-}"
USER="${INFOBLOX_USERNAME:-admin}"
PASS="${INFOBLOX_PASSWORD:-Infoblox@312}"
WAPI_VERSION="${WAPI_VERSION:-v2.13}"
MAX_RESULTS=1000
LIST_FILE="${1:-object_list.txt}"

[[ -z "$HOST" ]] && { echo "❌ Must set INFOBLOX_HOST or pass -h"; exit 1; }
[[ ! -f "$LIST_FILE" ]] && { echo "❌ Object list not found: $LIST_FILE"; exit 1; }

OUTDIR="data_dumps"
mkdir -p "$OUTDIR"

while read -r object; do
  [[ -z "$object" || "$object" =~ ^# ]] && continue  # skip blank/comment lines
  safe_object=$(echo "$object" | tr ':' '_')
  outfile="$OUTDIR/${safe_object}.json"

  echo "📡 Downloading $object..."

  URL="https://${HOST}/wapi/${WAPI_VERSION}/${object}"
  PARAMS="?_paging=1&_return_as_object=1&_max_results=${MAX_RESULTS}"

  PAGE_ID=""
  PAGE=0
  > "$outfile"

  while :; do
    ((PAGE++))
    if [[ -n "$PAGE_ID" ]]; then
      FULL_URL="${URL}${PARAMS}&_page_id=${PAGE_ID}"
    else
      FULL_URL="${URL}${PARAMS}"
    fi

    RESP=$(curl -sk -u "$USER:$PASS" "$FULL_URL")
    [[ -z "$RESP" ]] && break

    PAGE_ID=$(echo "$RESP" | jq -r '.next_page_id // empty')
    if echo "$RESP" | jq -e '.result | type == "array"' >/dev/null; then
        echo "$RESP" | jq -c '.result[]' >> "$outfile"
    else
        echo "⚠️  No results returned for $object (empty or null)."
        break
    fi


    [[ -z "$PAGE_ID" ]] && break
  done

  COUNT=$(wc -l < "$outfile")
  echo "✅ $object → $outfile ($COUNT records)"
done < "$LIST_FILE"
