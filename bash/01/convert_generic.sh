#!/bin/bash
set -euo pipefail
source resource_schema.sh

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

convert_type() {
  local resource="$1"
  local infile="$2"
  local tfout="tf_${resource}.tf"
  local impout="import_${resource}.sh"

  [[ -f "$infile" ]] || { echo "Input missing: $infile"; return; }

  echo "# Terraform manifest for $resource" > "$tfout"
  echo "#!/bin/bash" > "$impout"; chmod +x "$impout"

  IFS=","
  local reqs="${RESOURCE_ATTRS[$resource]%%;*}"
  local opts="${RESOURCE_ATTRS[$resource]##*;}"
  IFS="," req_list=($reqs) && IFS="," opt_list=($opts)

  while read -r rec; do
    declare -A vals
    vals["_ref"]=$(echo "$rec" | jq -r '._ref // empty')

    for fld in "${req_list[@]}" "${opt_list[@]}"; do
      key=${fld%%=*}; tfkey=${fld##*=}
      [[ "$key" == "${fld##*=}" ]] && tfkey="$key"
      vals["$tfkey"]=$(echo "$rec" | jq -r --arg k "$key" '.[$k] // empty')
    done

    # Skip if required missing
    for fld in "${req_list[@]}"; do
      tfkey=${fld##*=}
      [[ -z "${vals[$tfkey]}" || "${vals[$tfkey]}" == "null" ]] && continue 2
    done

    base="${vals["${req_list[0]##*=}"]}"
    for fld in "${req_list[@]:1}"; do base+="_${vals[${fld##*=}]}"; done
    safe_name=$(make_safe_tf_name "$base")

    echo "resource \"$resource\" \"$safe_name\" {" >> "$tfout"
    for fld in "${req_list[@]}" "${opt_list[@]}"; do
      tfkey=${fld##*=}; val="${vals[$tfkey]}"
      [[ -n "$val" && "$val" != "null" ]] || continue
      if [[ "$tfkey" == "dns_view" ]]; then
        echo "  dns_view = \"$val\"" >> "$tfout"
      else
        echo "  $tfkey = \"${val}\"" >> "$tfout"
      fi
    done

    # ext_attrs
    ext=$(echo "$rec" | jq -c '.extattrs // {}')
    if [[ "$ext" != "{}" ]]; then
      kv=$(echo "$ext" | jq -c 'to_entries | map({(.key): .value.value}) | add')
      echo "  ext_attrs = jsonencode($kv)" >> "$tfout"
    fi
    echo "}" >> "$tfout"

    echo "terraform import $resource.$safe_name \"${vals[_ref]}\"" >> "$impout"
  done < "$infile"

  echo "✅ Generated for $resource -> $tfout, $impout"
}

# Example use for record:a and record:cname
convert_type "infoblox_a_record" "record_a.json"
convert_type "infoblox_cname_record" "record_cname.json"
