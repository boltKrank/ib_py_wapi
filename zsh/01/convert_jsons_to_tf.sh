#!/bin/zsh
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

INPUT_DIR="object_jsons"
OUTPUT_TF="generated_objects.tf"
IMPORT_SCRIPT="import_objects.sh"
: > "$OUTPUT_TF"
: > "$IMPORT_SCRIPT"

echo "#!/bin/bash" >> "$IMPORT_SCRIPT"
echo "" >> "$IMPORT_SCRIPT"

for file in "$INPUT_DIR"/*.json(.N); do
  OBJECT_TYPE=$(basename "$file" | cut -d_ -f1 | tr '_' ':')
  TF_TYPE=$(echo "$OBJECT_TYPE" | sed 's/:/_/' | awk '{print "infoblox_" $1}')
  
  echo "📄 Processing $file (type: $OBJECT_TYPE → TF: $TF_TYPE)"

  while read -r line; do
    REF=$(echo "$line" | jq -r '._ref')
    NAME=$(echo "$line" | jq -r '.name // .ipv4addr // empty' | tr '.:' '_')

    [[ -z "$REF" || -z "$NAME" ]] && continue

    # Write Terraform resource
    echo "resource \"$TF_TYPE\" \"$NAME\" {" >> "$OUTPUT_TF"
    echo "  # Fields populated manually or with script enhancements" >> "$OUTPUT_TF"
    echo "}" >> "$OUTPUT_TF"
    echo "" >> "$OUTPUT_TF"

    # Write import command
    echo "terraform import $TF_TYPE.$NAME \"$REF\"" >> "$IMPORT_SCRIPT"
  done < "$file"
done

chmod +x "$IMPORT_SCRIPT"
echo "✅ Output files:"
echo "  • $OUTPUT_TF"
echo "  • $IMPORT_SCRIPT"
