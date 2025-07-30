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

while IFS= read -r record; do
  fqdn=$(echo "$record" | jq -r '.name // empty')
  ip=$(echo "$record" | jq -r '.ipv4addr // empty')
  ref=$(echo "$record" | jq -r '._ref // empty')

  [[ -z "$fqdn" || -z "$ip" || -z "$ref" ]] && continue

  # Safe Terraform resource name
  safe_name=$(echo "${fqdn}_${ip}" | sed 's/[^a-zA-Z0-9]/_/g')

  {
    echo "resource \"infoblox_a_record\" \"$safe_name\" {"
    echo "  fqdn    = \"${fqdn}\""
    echo "  ip_addr = \"${ip}\""

    # Optional attributes (renamed where necessary)
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

    # extattrs block with jsonencode
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
