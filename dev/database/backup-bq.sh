#!/bin/bash
set -e

PROJECT="fcsp-azure-dev"
DATASET="colt_mwc_2026_bgd_dev"
OUT="./backup_${DATASET}"
BUCKET="gs://colt-mwc-2026-gcs-poc/backup_${DATASET}"

mkdir -p "$OUT/schemas" "$OUT/ddl"

# Store view DDL as JSON because the DDL text can span multiple lines.
echo "1) Exporting VIEW DDL (as JSON to preserve multiline text)..."
bq query --use_legacy_sql=false --format=json \
  "SELECT table_name, ddl FROM \`${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLES\`
   WHERE table_type = 'VIEW'" \
  > "$OUT/ddl/views.json"

# The CSV header is skipped later when we iterate over the real tables.
echo "2) Exporting list of base TABLES..."
bq query --use_legacy_sql=false --format=csv \
  "SELECT table_name FROM \`${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLES\`
   WHERE table_type = 'BASE TABLE'" \
  > "$OUT/ddl/tables_list.csv"

# Routine export is optional because some datasets do not define routines.
echo "3) Exporting ROUTINE DDL (functions/procedures), if any exist..."
bq query --use_legacy_sql=false --format=json \
  "SELECT routine_name, ddl FROM \`${PROJECT}.${DATASET}.INFORMATION_SCHEMA.ROUTINES\`" \
  > "$OUT/ddl/routines.json" 2>/dev/null || echo "   (no routines or ignored error)"

# Export each table to AVRO and save the matching schema for restore time.
echo "4) Exporting each table to AVRO and saving its schema..."
while read -r TABLE; do
  [ -z "$TABLE" ] && continue
  echo "   -> Exporting $TABLE..."
  bq extract --destination_format=AVRO \
    "${PROJECT}:${DATASET}.${TABLE}" \
    "${BUCKET}/${TABLE}/*.avro"

  bq show --schema --format=prettyjson "${PROJECT}:${DATASET}.${TABLE}" \
    > "$OUT/schemas/${TABLE}.json"
done < <(tail -n +2 "$OUT/ddl/tables_list.csv" | tr -d '"')

echo "Backup complete. Local folder: $OUT  |  Data in: $BUCKET"