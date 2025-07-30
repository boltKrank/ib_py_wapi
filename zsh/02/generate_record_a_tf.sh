#!/bin/bash
set -euo pipefail
trap 'echo "❌ Script failed on line $LINENO. Exiting."' ERR

# --- Config ---
HOST="${INFOBLOX_HOST:-}"
USER="${INFOBLOX_USERNAME:-admin}"
PASS="${INFOBLOX_PASSWORD:-Infoblox@312}"
WAPI_VERSION="${INFOBLOX_WAPI_VERSION:-v2.10}"
MAX_RESULTS=1000

TF_FILE="record_a.tf"
IMPORT_FILE="import_record_a.sh"

# --- Validate ---
if [[ -z "$HOST" ]]; then
  echo "❌ Please set INFOBLOX_HOST or pass -h <host>"
  exit 1
fi

# --- Prep output files ---
echo "# Terraform manifest for record:a objects" > "$TF_FILE"
echo "#!/bin/bash" > "$IMPORT_FILE"
chmod +x "$IMPORT_FILE"

# --- Fetch paged data ---
URL="https://${HOST}/wapi/${WAPI_VERSION}/record:a"
PARAMS="?_paging=1&_return_as_object=1&_max_results=${MAX_RESULTS}"
PAGE_ID=""
PAGE=0

echo "📡 Connecting to Infoblox WAPI @ $HOST..."
while :; do
  ((PAGE++))
  if [[ -n "$PAGE_ID" ]]; then
    FULL_URL="${URL}${PARAMS}&_page_id=${PAGE_ID}"
  else
    FULL_URL="${URL}${PARAMS}"
  fi

  echo "🔄 Fetching page $PAGE..."
  RESP=$(curl -sk -u "$USER:$PASS" "$FULL_URL")

  PAGE_ID=$(echo "$RESP" | jq -r '.next_page_id // empty')

  echo "$RESP" | jq -c '.result[]' | while read -r record; do
    name=$(echo "$record" | jq -r '.name')
    ip=$(echo "$record" | jq -r '.ipv4addr')
    ref=$(echo "$record" | jq -r '._ref')

    [[ -z "$name" || -z "$ip" || -z "$ref" ]] && continue

    # Safe Terraform name
    safe_name=$(echo "${name}_${ip}" | sed 's/[^a-zA-Z0-9]/_/g')

    {
      echo "resource \"infoblox_record_a\" \"$safe_name\" {"
      echo "  name     = \"${name}\""
      echo "  ipv4addr = \"${ip}\""

      # Optional attributes
      for attr in comment creator ddns_principal ddns_protected disable forbid_reclamation ttl view zone; do
        val=$(echo "$record" | jq -r --arg k "$attr" '.[$k] // empty')
        if [[ -n "$val" && "$val" != "null" ]]; then
          if [[ "$val" =~ ^[0-9]+$ || "$val" == "true" || "$val" == "false" ]]; then
            echo "  $attr = $val"
          else
            echo "  $attr = \"${val}\""
          fi
        fi
      done

      # extattrs
      extattrs=$(echo "$record" | jq -e -c '.extattrs // {}' || echo '')
      if [[ -n "$extattrs" && "$extattrs" != "{}" ]]; then
        echo "  extattrs = {"
        echo "$extattrs" | jq -r 'to_entries[] | "    \(.key) = \"\(.value.value)\""' 
        echo "  }"
      fi

      echo "}"
    } >> "$TF_FILE"

    echo "terraform import infoblox_record_a.$safe_name \"$ref\"" >> "$IMPORT_FILE"
  done

  [[ -z "$PAGE_ID" ]] && break
done

echo "✅ Done. Terraform file: $TF_FILE"
echo "✅ Import script: $IMPORT_FILE"
