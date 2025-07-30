#!/bin/zsh
set -euo pipefail
trap 'echo "❌ Script failed on line $LINENO. Exiting."' ERR

# --- Defaults (can be overridden by env or args) ---
HOST="${INFOBLOX_HOST:-}"
USER="${INFOBLOX_USERNAME:-admin}"
PASS="${INFOBLOX_PASSWORD:-Infoblox@312}"
WAPI_VERSION="${WAPI_VERSION:-v2.10}"

# --- Help Message ---
usage() {
  echo "Usage: $0 [-h host] [-u username] [-p password] [-v wapi_version]"
  echo ""
  echo "Defaults:"
  echo "  USERNAME     = admin"
  echo "  PASSWORD     = Infoblox@312"
  echo "  WAPI_VERSION = v2.10"
  echo ""
  echo "Environment variables can also be used:"
  echo "  INFOBLOX_HOST, INFOBLOX_USERNAME, INFOBLOX_PASSWORD, WAPI_VERSION"
  exit 1
}

# --- Parse CLI Arguments ---
while getopts ":h:u:p:v:" opt; do
  case $opt in
    h) HOST="$OPTARG" ;;
    u) USER="$OPTARG" ;;
    p) PASS="$OPTARG" ;;
    v) WAPI_VERSION="$OPTARG" ;;
    *) usage ;;
  esac
done

# --- Validate Required Fields ---
if [[ -z "$HOST" ]]; then
  echo "❌ Error: Missing Infoblox host."
  usage
fi

# --- Logging Configuration ---
echo "🔧 Using configuration:"
echo "  HOST         = $HOST"
echo "  USERNAME     = $USER"
echo "  PASSWORD     = ******** (length: ${#PASS})"
echo "  WAPI_VERSION = $WAPI_VERSION"

# --- Build URL ---
SCHEMA_URL="https://${HOST}/wapi/${WAPI_VERSION}/?_schema&_return_as_object=1"
echo "🌐 Requesting schema from: $SCHEMA_URL"

# --- Curl Call ---
TMPFILE=$(mktemp)
echo "📡 Sending request to Infoblox..."
HTTP_CODE=$(curl -sk -u "${USER}:${PASS}" -w "%{http_code}" -o "$TMPFILE" "$SCHEMA_URL")
RESPONSE=$(cat "$TMPFILE")
rm "$TMPFILE"

echo "📥 HTTP response status: $HTTP_CODE"

if [[ "$HTTP_CODE" -ne 200 ]]; then
  echo "❗ Error: HTTP $HTTP_CODE received"
  echo "🔎 Response:"
  echo "$RESPONSE" | jq .
  exit 1
fi

# --- Output Setup ---
TIMESTAMP=$(date +"%Y-%m-%dT%H-%M-%S")
FILENAME="supported_objects_${TIMESTAMP}.txt"
ARCHIVE_DIR="old_supported_objects"
mkdir -p "$ARCHIVE_DIR"

OUTPUT_FILE="${ARCHIVE_DIR}/${FILENAME}"

# --- Parse and save supported object names ---
echo "💾 Extracting supported object names to $OUTPUT_FILE..."
echo "$RESPONSE" | jq -r '.result.supported_objects[]' | sort > "$OUTPUT_FILE"

# --- Symlink to latest ---
ln -sf "$OUTPUT_FILE" "supported_objects_latest.txt"
echo "🔗 Symlink created: supported_objects_latest.txt → $OUTPUT_FILE"

if [[ -s "$OUTPUT_FILE" ]]; then
  echo "✅ Done. First 10 entries:"
  head "$OUTPUT_FILE"
else
  echo "❗ Error: No supported object names found."
  echo "$RESPONSE" | jq '.result.supported_objects'
  exit 1
fi



# --- Parse and save supported object names ---
echo "💾 Extracting supported object names to $OUTPUT_FILE..."

echo "$RESPONSE" | jq -r '.result.supported_objects[]' | sort > "$OUTPUT_FILE"

if [[ -s "$OUTPUT_FILE" ]]; then
  echo "✅ Done. First 10 entries:"
  head "$OUTPUT_FILE"
else
  echo "❗ Error: No supported object names found."
  echo "$RESPONSE" | jq '.result.supported_objects'
  exit 1
fi
