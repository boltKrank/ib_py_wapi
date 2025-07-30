#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="./terraform-provider-infoblox"
INF_DIR="$REPO_DIR/infoblox"
OUT_JSON="datasource_schema.json"

# Clone if not already present
if [[ ! -d "$INF_DIR" ]]; then
  echo "📦 Cloning Infoblox Terraform provider..."
  git clone https://github.com/infobloxopen/terraform-provider-infoblox.git "$REPO_DIR"
else
  echo "✅ Repo already exists: $REPO_DIR"
fi

echo "{" > "$OUT_JSON"
first=true

find "$INF_DIR" -maxdepth 1 -type f -name 'datasource_infoblox_*.go' ! -name '*_test.go' | while read -r file; do
  ds_name="infoblox_${file##*/datasource_infoblox_}"
  ds_name="${ds_name%.go}"

  mapfile -t lines < "$file"

  mapping=()
  in_results_block=0
  in_nested_schema=0
  brace_level=0
  current_attr=""

  for (( i=0; i<${#lines[@]}; i++ )); do
    line="${lines[i]}"

    # Detect start of results block
    if echo "$line" | grep -qE '"results"[[:space:]]*:'; then
      in_results_block=1
      continue
    fi

    # Detect start of nested schema under Elem
    if (( in_results_block )) && echo "$line" | grep -qE 'Schema:[[:space:]]*map\[string\]\*schema\.Schema\s*\{'; then
      in_nested_schema=1
      brace_level=1
      continue
    fi

    # Track nested schema block
    if (( in_nested_schema )); then
      open_count=$(grep -o '{' <<< "$line" | wc -l)
      close_count=$(grep -o '}' <<< "$line" | wc -l)
      (( brace_level += open_count - close_count ))

      # Match field name
      if echo "$line" | grep -qE '^[[:space:]]*"[^"]+"[[:space:]]*:'; then
        attr=$(echo "$line" | grep -oE '"[^"]+"' | head -1 | tr -d '"')
        mapping+=("\"$attr\": \"$attr\"")
      fi

      if (( brace_level == 0 )); then
        in_nested_schema=0
        in_results_block=0
      fi
    fi
  done

  if (( ${#mapping[@]} > 0 )); then
    if ! $first; then echo "," >> "$OUT_JSON"; fi
    first=false
    echo "  \"$ds_name\": {" >> "$OUT_JSON"
    for j in "${!mapping[@]}"; do
      echo -n "    ${mapping[$j]}" >> "$OUT_JSON"
      [[ $j -lt $(( ${#mapping[@]} - 1 )) ]] && echo "," >> "$OUT_JSON" || echo >> "$OUT_JSON"
    done
    echo -n "  }" >> "$OUT_JSON"
  fi

done

echo >> "$OUT_JSON"
echo "}" >> "$OUT_JSON"
echo "✅ Done: $OUT_JSON"
