#!/bin/zsh
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

INPUT_DIR="object_jsons"
OUTPUT_DIR="generated"
mkdir -p "$OUTPUT_DIR"

# --- Mapping: WAPI object → Terraform resource type
typeset -A WAPI_TO_TF
WAPI_TO_TF=(
  "record:a" infoblox_a_record
  "record:aaaa" infoblox_aaaa_record
  "record:cname" infoblox_cname_record
  "record:ptr" infoblox_ptr_record
  "record:mx" infoblox_mx_record
  "record:txt" infoblox_txt_record
  "record:srv" infoblox_srv_record
  "record:alias" infoblox_alias_record
  "record:ns" infoblox_ns_record
  "network" infoblox_ipv4_network
  "ipv6network" infoblox_ipv6_network
  "ipv4networkcontainer" infoblox_ipv4_network_container
  "ipv6networkcontainer" infoblox_ipv6_network_container
  "networkview" infoblox_network_view
  "fixedaddress" infoblox_ipv4_fixed_address
  "range" infoblox_ipv4_range
  "rangetemplate" infoblox_ipv4_range_template
  "view" infoblox_dns_view
  "zone_auth" infoblox_zone_auth
  "zone_forward" infoblox_zone_forward
  "zone_delegated" infoblox_zone_delegated
  "dtclbdn" infoblox_dtc_lbdn
  "dtcpool" infoblox_dtc_pool
  "dtcserver" infoblox_dtc_server
)

echo "🚀 Starting Terraform and import file generation..."

for json_file in "$INPUT_DIR"/*.json(.N); do
  filename=$(basename "$json_file")
  safe_type=${filename%%_*}            # e.g., "record_a"
  wapi_type=${safe_type//_/:}          # e.g., "record:a"

  tf_type=${WAPI_TO_TF[$wapi_type]:-}
  [[ -z "$tf_type" ]] && echo "⚠️  Skipping unknown type: $wapi_type" && continue

  TF_OUT="${OUTPUT_DIR}/${safe_type}.tf"
  SH_OUT="${OUTPUT_DIR}/${safe_type}_import.sh"

  echo "#!/bin/bash" > "$SH_OUT"
  echo "" >> "$SH_OUT"

  echo "📄 Processing: $json_file → $tf_type"

  while read -r line; do
    [[ -z "$line" ]] && continue

    _ref=$(echo "$line" | jq -r '._ref // empty')
    [[ -z "$_ref" ]] && continue

    # Determine
