#!/data/data/com.termux/files/usr/bin/bash
# Watch DCIM for new photos, extract metadata, append to foto_log.csv

WATCH_DIR="$HOME/storage/dcim/Camera"
LOG_DIR="$HOME/storage/downloads"
CSV="$LOG_DIR/foto_log.csv"
BOM=$'\xEF\xBB\xBF'
HEADER="timestamp;filename;latitude;longitude;altitude_m;filesize_kb"
CHECK_INTERVAL=5

echo ""
echo "📸 Foto reģistrētājs"
echo "===================="
echo "👁️  Uzrauga: $WATCH_DIR"
echo "📁 Žurnāls: $CSV"
echo "Nospied Ctrl+C lai apturētu"
echo ""

# Write header if new file
if [ ! -f "$CSV" ]; then
    printf "%s" "$BOM" > "$CSV"
    echo "$HEADER" >> "$CSV"
fi

# Track already-seen files
declare -A seen_files

# Pre-populate seen files so we don't log existing photos on start
while IFS= read -r -d '' f; do
    seen_files["$f"]=1
done < <(find "$WATCH_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.mp4" -o -iname "*.dng" \) -print0 2>/dev/null)

echo "📋 Esošie faili ignorēti ($(${#seen_files[@]}) faili). Gaida jaunus..."
echo ""

extract_exif_gps() {
    # Try to extract GPS from EXIF using python
    local file="$1"
    python3 - "$file" << 'PYEOF' 2>/dev/null
import sys
try:
    # Try with Pillow if available
    from PIL import Image
    from PIL.ExifTags import TAGS, GPSTAGS
    img = Image.open(sys.argv[1])
    exif = img._getexif()
    if not exif:
        print(";;")
        sys.exit()
    gps_info = {}
    for tag, val in exif.items():
        if TAGS.get(tag) == "GPSInfo":
            for t, v in val.items():
                gps_info[GPSTAGS.get(t, t)] = v
    def to_deg(val):
        d, m, s = val
        return float(d) + float(m)/60 + float(s)/3600
    lat = to_deg(gps_info.get("GPSLatitude",(0,0,0)))
    if gps_info.get("GPSLatitudeRef","N") == "S": lat = -lat
    lon = to_deg(gps_info.get("GPSLongitude",(0,0,0)))
    if gps_info.get("GPSLongitudeRef","E") == "W": lon = -lon
    alt_raw = gps_info.get("GPSAltitude", 0)
    alt = float(alt_raw) if alt_raw else 0
    print(f"{lat};{lon};{alt}")
except Exception:
    print(";;")
PYEOF
}

trap 'echo ""; echo "⏹️  Apturēts."; exit 0' INT TERM

while true; do
    while IFS= read -r -d '' file; do
        if [ -z "${seen_files[$file]}" ]; then
            seen_files["$file"]=1

            filename=$(basename "$file")
            timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            filesize=$(du -k "$file" 2>/dev/null | cut -f1)
            gps=$(extract_exif_gps "$file")
            lat=$(echo "$gps" | cut -d';' -f1)
            lon=$(echo "$gps" | cut -d';' -f2)
            alt=$(echo "$gps" | cut -d';' -f3)

            echo "${timestamp};${filename};${lat};${lon};${alt};${filesize}" >> "$CSV"

            echo "📸 Foto saglabāts: $filename"
            echo "   🕐 Laiks:    $timestamp"
            echo "   📍 GPS:      ${lat:-nav} , ${lon:-nav}"
            echo "   📏 Augstums: ${alt:-nav} m"
            echo "   💾 Izmērs:   ${filesize} KB"
            echo ""
        fi
    done < <(find "$WATCH_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.mp4" -o -iname "*.dng" \) -print0 2>/dev/null)

    sleep "$CHECK_INTERVAL"
done
