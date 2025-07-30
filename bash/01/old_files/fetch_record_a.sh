#!/bin/bash
set -euo pipefail
trap 'echo "❌ Script failed on line $LINENO. Exiting."' ERR

INPUT_FILE="record_a.json"
TF_FILE="record_a.tf"
IMPORT_FILE="import_record_a.sh"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ Input file '$INPUT_FILE' not found. Run the fetch script first."
  exit 1
fi

echo "# Terraform manifest for record:a objects" > "$TF_FILE"
echo "#!/bin/bash" > "$IMPORT_FILE"
chmod +x "$IMPORT_FILE"

# Function to generate safe Terraform resource names
make_safe_tf_name() {
  local base="$1"
  local cleaned
  cleaned=$(echo "$base" | sed 's/[^a-zA-Z0-9]/_/g')
  if (( ${#cleaned} > 60 )); then
    local hash
    hash=$(echo -n "$base" | sha1sum | awk '{print $1}' | cut -c1-10)
    echo "${cleaned:0:50}_$hash"
  else
    echo "$cleaned"
  fi
}

while IFS= read -r record; do
  fqdn=$(echo "$record" | jq -r '.name // empty')
  ip=$(echo "$record" | jq -r '.ipv4addr // empty')
  view=$(echo "$record" | jq -r '.view // "default"')
  ref=$(echo "$record" | jq -r '._ref // empty')

  [[ -z "$fqdn" || -z "$ip" || -z "$ref" ]] && continue

  # Unique Terraform resource name
  base_name="${fqdn}_${ip}_${view}"
  safe_name=$(make_safe_tf_name "$base_name")

  {
    echo "resource \"infoblox_a_record\" \"$safe_name\" {"
    echo "  fqdn    = \"${fqdn}\""
    echo "  ip_addr = \"${ip}\""

    # Optional attributes
    for pair in \
      "comment comment" \
      "creator creator" \
      "ddns_principal ddns_principal" \
      "ddns_protected ddns_protected" \
      "disable disable" \
      "forbid_reclamation forbid_reclamation" \
      "ttl ttl" \
      "view dns_view" \
      "zone zone"; do

      wapi_attr=${pair%% *}
      tf_attr=${pair##* }

      val=$(echo "$record" | jq -r --arg k "$wapi_attr" '.[$k] // empty')
      if [[ -n "$val" && "$val" != "null" ]]; then
        if [[ "$val" =~ ^[0-9]+$ || "$val" == "true" || "$val" == "false" ]]; then
          echo "  $tf_attr = $val"
        else
          echo "  $tf_attr = \"${val}\""
        fi
      fi
    done

    # extattrs
    extattrs=$(echo "$record" | jq -c '.extattrs // {}')
    if [[ -n "$extattrs" && "$extattrs" != "{}" ]]; then
      kv=$(echo "$extattrs" | jq -c 'to_entries | map({(.key): .value.value}) | add')
      echo "  ext_attrs = jsonencode($kv)"
    fi

    echo "}"
  } >> "$TF_FILE"

  echo "terraform import infoblox_a_record.${safe_name} \"$ref\"" >> "$IMPORT_FILE"
done < "$INPUT_FILE"

echo "✅ Generated:"
echo "  → $TF_FILE"
echo "  → $IMPORT_FILE"
