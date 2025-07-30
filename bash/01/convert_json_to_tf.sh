#!/bin/bash
set -euo pipefail

SCHEMA_FILE="$1"   # e.g. resource_schema.json
DATA_FILE="$2"     # e.g. record_a.json

[[ ! -f "$SCHEMA_FILE" ]] && { echo "❌ Schema file not found: $SCHEMA_FILE"; exit 1; }
[[ ! -f "$DATA_FILE" ]] && { echo "❌ Data file not found: $DATA_FILE"; exit 1; }

# Infer resource type from filename
BASE=$(basename "$DATA_FILE" .json)
RESOURCE_TYPE="infoblox_${BASE}"   # e.g. record_a.json → infoblox_record_a

TF_FILE="${BASE}.tf"
IMPORT_FILE="import_${BASE}.sh"

echo "# Terraform manifest for $RESOURCE_TYPE" > "$TF_FILE"
echo "#!/bin/bash" > "$IMPORT_FILE"
chmod +x "$IMPORT_FILE"

make_safe_tf_name() {
  local base="$1"
  local cleaned="${base//[^a-zA-Z0-9]/_}"
  if (( ${#cleaned} > 60 )); then
    local hash=$(echo -n "$base" | sha1sum | awk '{print $1}' | cut -c1-10)
    echo "${cleaned:0:50}_$hash"
  else
    echo "$cleaned"
  fi
}

# Get field mappings from JSON schema
get_fields() {
  local type="$1"
  local key="$2"
  jq -r --arg r "$type" --arg k "$key" '
    .[$r][$k][] // empty
  ' "$SCHEMA_FILE"
}

REQUIRED_FIELDS=($(get_fields "$RESOURCE_TYPE" "required"))
OPTIONAL_FIELDS=($(get_fields "$RESOURCE_TYPE" "optional"))

if [[ ${#REQUIRED_FIELDS[@]} -eq 0 ]]; then
  echo "❌ No schema found for resource type: $RESOURCE_TYPE"
  exit 1
fi

while IFS= read -r record; do
  declare -A vals

  fqdn=""
  ip=""
  view="default"
  ref=$(echo "$record" | jq -r '._ref // empty')
  [[ -z "$ref" || "$ref" == "null" ]] && continue

  for entry in "${REQUIRED_FIELDS[@]}" "${OPTIONAL_FIELDS[@]}"; do
    tf_attr="${entry%%=*}"
    wapi_attr="${entry##*=}"
    val=$(echo "$record" | jq -r --arg k "$wapi_attr" '.[$k] // empty')
    [[ "$val" == "null" ]] && val=""
    vals["$tf_attr"]="$val"

    [[ "$tf_attr" == "fqdn" || "$tf_attr" == "alias" || "$tf_attr" == "name" ]] && fqdn="$val"
    [[ "$tf_attr" == "ip_addr" ]] && ip="$val"
    [[ "$tf_attr" == "dns_view" ]] && view="$val"
  done

  [[ -z "$fqdn" && -z "$ip" ]] && continue

  base_name="${fqdn}_${ip}_${view}"
  safe_name=$(make_safe_tf_name "$base_name")

  {
    echo "resource \"$RESOURCE_TYPE\" \"$safe_name\" {"
    for entry in "${REQUIRED_FIELDS[@]}" "${OPTIONAL_FIELDS[@]}"; do
      tf_attr="${entry%%=*}"
      val="${vals[$tf_attr]}"
      [[ -z "$val" ]] && continue

      if [[ "$val" == "true" || "$val" == "false" || "$val" =~ ^[0-9]+$ ]]; then
        echo "  $tf_attr = $val"
      else
        echo "  $tf_attr = \"${val}\""
      fi
    done

    # ext_attrs block
    extattrs=$(echo "$record" | jq -c '.extattrs // {}')
    if [[ "$extattrs" != "{}" ]]; then
      kv=$(echo "$extattrs" | jq -c 'to_entries | map({(.key): .value.value}) | add')
      echo "  ext_attrs = jsonencode($kv)"
    fi

    echo "}"
  } >> "$TF_FILE"

  echo "terraform import $RESOURCE_TYPE.$safe_name \"$ref\"" >> "$IMPORT_FILE"
done < "$DATA_FILE"

echo "✅ Done: $TF_FILE and $IMPORT_FILE generated for $RESOURCE_TYPE"
