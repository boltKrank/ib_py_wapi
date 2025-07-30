#!/usr/bin/env bash
set -xeuo pipefail

INF_DIR="${1:-./infoblox}"
OUT_SH="resource_schema.sh"
OUT_JSON="resource_schema.json"

echo "#!/usr/bin/env bash" > "$OUT_SH"
echo "# Auto-generated mapping from Infoblox provider .go files" >> "$OUT_SH"
echo "declare -A RESOURCE_ATTRS" >> "$OUT_SH"
echo "" >> "$OUT_SH"

echo "{" > "$OUT_JSON"
first=true

shopt -s nullglob
for file in "$INF_DIR"/resource_infoblox_*.go; do
  [[ "$file" == *_test.go ]] && continue  # skip test files
  tf_resource="infoblox_${file##*/resource_infoblox_}"
  tf_resource="${tf_resource%.go}"

  required=()
  optional=()
  current=""
  wapi_field=""
  flag=""

  while IFS= read -r line; do
  # Detect start of schema attribute
  if [[ $line =~ ^[[:space:]]*\"([^\"]+)\"[[:space:]]*:[[:space:]]*\{ ]]; then
    current="${BASH_REMATCH[1]}"
    wapi_field=""
    flag=""
    continue
  fi

  # Detect if field is required or optional
  if [[ $line =~ Required:\s*true ]]; then
    flag="required"
  elif [[ $line =~ Optional:\s*true ]]; then
    flag="optional"
  fi

  # Extract WAPI field from description (if available)
  if [[ $line =~ WAPI[[:space:]]field:[[:space:]]([a-zA-Z0-9_]+) ]]; then
    wapi_field="${BASH_REMATCH[1]}"
  fi

  # Detect end of schema block
  if [[ $line =~ ^[[:space:]]*\}, ]]; then
    [[ -z "$current" || -z "$flag" ]] && continue
    key="$current"
    val="${wapi_field:-$current}"
    pair="${key}=${val}"
    if [[ "$flag" == "required" ]]; then
      required+=("$pair")
    elif [[ "$flag" == "optional" ]]; then
      optional+=("$pair")
    fi
    current=""
    flag=""
    wapi_field=""
  fi
done < "$file"

  # Write to Bash output
  req_csv=$(IFS=,; echo "${required[*]}")
  opt_csv=$(IFS=,; echo "${optional[*]}")
  echo "RESOURCE_ATTRS[\"$tf_resource\"]=\"$req_csv;$opt_csv\"" >> "$OUT_SH"

  # Write to JSON output
  if ! $first; then echo "," >> "$OUT_JSON"; fi
  first=false
  echo "  \"$tf_resource\": {" >> "$OUT_JSON"
  echo "    \"required\": [" >> "$OUT_JSON"
  for i in "${!required[@]}"; do
    printf '      "%s"' "${required[$i]}"
    [[ $i -lt $(( ${#required[@]} - 1 )) ]] && echo "," || echo ""
  done
  echo "    ]," >> "$OUT_JSON"
  echo "    \"optional\": [" >> "$OUT_JSON"
  for i in "${!optional[@]}"; do
    printf '      "%s"' "${optional[$i]}"
    [[ $i -lt $(( ${#optional[@]} - 1 )) ]] && echo "," || echo ""
  done
  echo "    ]" >> "$OUT_JSON"
  echo -n "  }" >> "$OUT_JSON"
done

echo "" >> "$OUT_SH"
echo "}" >> "$OUT_JSON"

echo "✅ Wrote Bash schema to $OUT_SH"
echo "✅ Wrote JSON schema to $OUT_JSON"
