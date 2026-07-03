#!/bin/bash
set -e

DEST_PROJECT="fcsp-azure-dev"
DEST_DATASET="kk_dataset"
DEST_LOCATION="EU"

# These values are required to rewrite the project and dataset references in the views.
SRC_PROJECT="fcsp-azure-dev"
SRC_DATASET="colt_mwc_2026_bgd_dev"

BUCKET="gs://colt-mwc-2026-gcs-poc/backup_${SRC_DATASET}"
IN="./backup_${SRC_DATASET}"

# Create the destination dataset first; ignore the error when it already exists.
echo "1) Creating destination dataset (if it does not exist)..."
bq mk --dataset --location="${DEST_LOCATION}" "${DEST_PROJECT}:${DEST_DATASET}" 2>/dev/null || \
  echo "   (already exists, continuing)"

# Load the base tables before recreating views so dependencies are present.
echo "2) Loading tables from AVRO..."
while read -r TABLE; do
  [ -z "$TABLE" ] && continue
  echo "   -> Loading $TABLE"
  bq load --source_format=AVRO \
    --use_avro_logical_types=true \
    "${DEST_PROJECT}:${DEST_DATASET}.${TABLE}" \
    "${BUCKET}/${TABLE}/*.avro"
done < <(tail -n +2 "$IN/ddl/tables_list.csv" | tr -d '"')

# Read the saved view definitions and recreate them one by one.
echo "3) Recreating views (from JSON, preserving multiline DDL)..."
VIEWS_JSON="$IN/ddl/views.json"
COUNT=$(jq 'length' "$VIEWS_JSON")

for i in $(seq 0 $((COUNT - 1))); do
  TABLE_NAME=$(jq -r ".[$i].table_name" "$VIEWS_JSON")
  DDL=$(jq -r ".[$i].ddl" "$VIEWS_JSON")

  # Rewrite source project and dataset references to the destination values.
  DDL=$(echo "$DDL" | sed "s/\`${SRC_PROJECT}\.${SRC_DATASET}\./\`${DEST_PROJECT}.${DEST_DATASET}./g; s/${SRC_PROJECT}:${SRC_DATASET}\./${DEST_PROJECT}:${DEST_DATASET}./g")

  echo "   -> Running view: $TABLE_NAME"
  bq query --use_legacy_sql=false "$DDL"
done

echo "Restore complete."