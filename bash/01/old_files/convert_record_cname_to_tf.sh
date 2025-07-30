#!/bin/bash
set -euo pipefail
trap 'echo "❌ Script failed on line $LINENO. Exiting."' ERR

INPUT_FILE="record_cname.json"
TF_FILE="record_cname.tf"
IMPORT_FILE="import_record_cname.sh"

[[ ! -f "$INPUT_FILE" ]] && echo "❌ Input file '$INPUT_FILE' missing" && exit 1

echo "# Terraform manifest for record:cname objects" > "$TF_FILE"
echo "#!/bin/bash" > "$IMPORT_FILE"
chmod +x "$IMPORT_FILE"

make_safe_tf_name() {
  local base="$1"
  local cleaned=$(echo "$base" | sed 's/[^a-zA-Z0-9]/_/g')
  if (( ${#cleaned} > 60 )); then
    local hash=$(echo -n "$base" | sha1sum | awk '{print $1}' | cut -c1-10)
    echo "${cleaned:0:50}_$hash"
  else
    echo "$cleaned"
  fi
}

while IFS= read -r record; do
  alias_fqdn=$(echo "$record" | jq -r '.name // empty')
  canonical=$(echo "$record" | jq -r '.canonical // empty')
  view=$(echo "$record" | jq -r '.view // "default"')
  ref=$(echo "$record" | jq -r '._ref // empty')

  [[ -z "$alias_fqdn" || -z "$canonical" || -z "$ref" ]] && continue

  base_name="${alias_fqdn}_${canonical}_${view}"
  safe_name=$(make_safe_tf_name "$base_name")

  {
    echo "resource \"infoblox_cname_record\" \"$safe_name\" {"
    echo "  alias     = \"${alias_fqdn}\""
    echo "  canonical = \"${canonical}\""

    # Include only schema-supported optional attributes
    ttl=$(echo "$record" | jq -r '.ttl // empty')
    [[ -n "$ttl" && "$ttl" != "null" ]] && echo "  ttl       = $ttl"

    [[ "$view" != "default" ]] && echo "  dns_view  = \"${view}\""

    comment=$(echo "$record" | jq -r '.comment // empty')
    [[ -n "$comment" && "$comment" != "null" ]] && echo "  comment   = \"${comment}\""

    extattrs=$(echo "$record" | jq -c '.extattrs // {}')
    if [[ "$extattrs" != "{}" ]]; then
      kv=$(echo "$extattrs" | jq -c 'to_entries | map({(.key): .value.value}) | add')
      echo "  ext_attrs = jsonencode($kv)"
    fi

    echo "}"
  } >> "$TF_FILE"

  echo "terraform import infoblox_cname_record.${safe_name} \"$ref\"" >> "$IMPORT_FILE"
done < "$INPUT_FILE"

echo "✅ Generated:"
echo "  → $TF_FILE"
echo "  → $IMPORT_FILE"
