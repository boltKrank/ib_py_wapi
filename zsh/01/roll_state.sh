#!/bin/zsh

# Settings
STATE_DIR="./"                     # or change to your Terraform working dir
BASE_NAME="terraform.tfstate.backup"
MAX_BACKUPS=5                      # number of historical versions to keep

cd "$STATE_DIR" || exit 1

# Exit if the main backup doesn't exist
if [[ ! -f "$BASE_NAME" ]]; then
  echo "No backup file ($BASE_NAME) found."
  exit 1
fi

# Roll older backups
for ((i=MAX_BACKUPS-1; i>=1; i--)); do
  if [[ -f "$BASE_NAME.$i" ]]; then
    mv "$BASE_NAME.$i" "$BASE_NAME.$((i+1))"
  fi
done

# Move current .backup to .backup.1
mv "$BASE_NAME" "$BASE_NAME.1"

echo "Rolled backups. $BASE_NAME -> $BASE_NAME.1 and so on."
