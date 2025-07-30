#!/usr/bin/env bash
set -euo pipefail

INF_DIR="./terraform-provider-infoblox/infoblox"
OUT_JSON="datasource_schema.json"

echo "{" > "$OUT_JSON"
first=true

find "$INF_DIR" -maxdepth 1 -type f -name 'datasource_infoblox_*.go' ! -name '*_test.go' | while read -r file; do
  ds_name="infoblox_${file##*/datasource_infoblox_}"
  ds_name="${ds_name%.go}"

  mapfile -t lines < "$file"

  mapping=()
  in_results_block=0
  in_elem_block=0
  in_schema_block=0
  brace_level=0

  for (( i=0; i<${#lines[@]}; i++ )); do
    line="${lines[i]}"

    # Look for the start of the results block
    if echo "$line" | grep -qE '^[[:space:]]*"results"[[:space:]]*:'; then
      in_results_block=1
      continue
    fi

    # Once in results, find Elem block
    if (( in_results_block )) && echo "$line" | grep -qE 'Elem:[[:space:]]*&schema\.Resource\{'; then
      in_elem_block=1
      brace_level=1
      continue
    fi

    # Once in Elem, look for Schema start
    if (( in_elem_block )) && echo "$line" | grep -qE 'Schema:[[:space:]]*map\[string\]\*schema\.Schema[[:space:]]*\{'; then
      in_schema_block=1
      brace_level=1
      continue
    fi

    # Track braces and extract fields
    if (( in_schema_block )); then
      open_count=$(grep -o '{' <<< "$line" | wc -l)
      close_count=$(grep -o '}' <<< "$line" | wc -l)
      (( brace_level += open_count - close_count ))

      if echo "$line" | grep -qE '^[[:space:]]*"[^"]+"[[:space:]]*:'; then
        attr=$(echo "$line" | grep -oE '"[^"]+"' | head -1 | tr -d '"')
        mapping+=("\"$attr\": \"$attr\"")
      fi

      if (( brace_level <= 0 )); then
        in_schema_block=0
        in_elem_block=0
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
