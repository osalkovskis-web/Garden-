#!/data/data/com.termux/files/usr/bin/bash
# Continuous sensor logging every 30 seconds to daily CSV file

INTERVAL=30
P0=1013.25  # Sea-level reference pressure hPa
LOG_DIR="$HOME/storage/downloads"
DATE=$(date +%Y%m%d)
CSV="$LOG_DIR/darzs_log_${DATE}.csv"

# UTF-8 BOM + header for Excel compatibility
BOM=$'\xEF\xBB\xBF'
HEADER="timestamp;latitude;longitude;gps_altitude_m;baro_pressure_hpa;baro_altitude_m;light_lux;accelerometer_x;accelerometer_y;accelerometer_z;magnetic_x;magnetic_y;magnetic_z;humidity_pct;battery_pct"

echo ""
echo "🌱 Dārza datu reģistrētājs"
echo "=========================="
echo "📁 Fails: $CSV"
echo "⏱️  Intervāls: ${INTERVAL}s"
echo "Nospied Ctrl+C lai apturētu"
echo ""

# Write header if file is new
if [ ! -f "$CSV" ]; then
    printf "%s" "$BOM" > "$CSV"
    echo "$HEADER" >> "$CSV"
    echo "📄 Jauns fails izveidots"
fi

# Barometric altitude formula: h = 44330 * (1 - (P/P0)^(1/5.255))
baro_altitude() {
    local p=$1
    python3 -c "print(round(44330 * (1 - ($p/$P0)**(1/5.255)), 2))" 2>/dev/null || echo ""
}

# Get GPS with retry (max 3 attempts)
get_gps() {
    local attempt=1
    while [ $attempt -le 3 ]; do
        local result
        result=$(termux-location -p gps -r once 2>/dev/null)
        local lat lon alt
        lat=$(echo "$result" | jq -r '.latitude // empty' 2>/dev/null)
        lon=$(echo "$result" | jq -r '.longitude // empty' 2>/dev/null)
        alt=$(echo "$result" | jq -r '.altitude // empty' 2>/dev/null)
        if [ -n "$lat" ] && [ "$lat" != "null" ]; then
            echo "$lat;$lon;$alt"
            return
        fi
        echo "⏳ GPS meklē fiksāciju ($attempt/3)..." >&2
        sleep 5
        ((attempt++))
    done
    echo ";;"  # empty fields if no fix
}

# Get barometer reading
get_baro() {
    local result
    result=$(termux-sensor -s "pressure" -n 1 2>/dev/null)
    echo "$result" | jq -r '.["TYPE_PRESSURE"].values[0] // empty' 2>/dev/null || echo ""
}

# Get light sensor
get_light() {
    local result
    result=$(termux-sensor -s "light" -n 1 2>/dev/null)
    echo "$result" | jq -r '.["TYPE_LIGHT"].values[0] // empty' 2>/dev/null || echo ""
}

# Get accelerometer
get_accel() {
    local result
    result=$(termux-sensor -s "accelerometer" -n 1 2>/dev/null)
    local x y z
    x=$(echo "$result" | jq -r '.["TYPE_ACCELEROMETER"].values[0] // empty' 2>/dev/null)
    y=$(echo "$result" | jq -r '.["TYPE_ACCELEROMETER"].values[1] // empty' 2>/dev/null)
    z=$(echo "$result" | jq -r '.["TYPE_ACCELEROMETER"].values[2] // empty' 2>/dev/null)
    echo "$x;$y;$z"
}

# Get magnetometer
get_mag() {
    local result
    result=$(termux-sensor -s "magnetic" -n 1 2>/dev/null)
    local x y z
    x=$(echo "$result" | jq -r '.["TYPE_MAGNETIC_FIELD"].values[0] // empty' 2>/dev/null)
    y=$(echo "$result" | jq -r '.["TYPE_MAGNETIC_FIELD"].values[1] // empty' 2>/dev/null)
    z=$(echo "$result" | jq -r '.["TYPE_MAGNETIC_FIELD"].values[2] // empty' 2>/dev/null)
    echo "$x;$y;$z"
}

# Get humidity
get_humidity() {
    local result
    result=$(termux-sensor -s "humidity" -n 1 2>/dev/null)
    echo "$result" | jq -r '.["TYPE_RELATIVE_HUMIDITY"].values[0] // empty' 2>/dev/null || echo ""
}

# Get battery
get_battery() {
    termux-battery-status 2>/dev/null | jq -r '.percentage // empty' 2>/dev/null || echo ""
}

trap 'echo ""; echo "⏹️  Apturēts. Dati saglabāti: $CSV"; exit 0' INT TERM

reading=0
while true; do
    ((reading++))
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo -n "📡 [$TIMESTAMP] Nolasa sensorus..."

    GPS=$(get_gps)
    BARO=$(get_baro)
    BARO_ALT=""
    [ -n "$BARO" ] && BARO_ALT=$(baro_altitude "$BARO")
    LIGHT=$(get_light)
    ACCEL=$(get_accel)
    MAG=$(get_mag)
    HUMID=$(get_humidity)
    BATT=$(get_battery)

    ROW="${TIMESTAMP};${GPS};${BARO};${BARO_ALT};${LIGHT};${ACCEL};${MAG};${HUMID};${BATT}"
    echo "$ROW" >> "$CSV"

    # Status line
    LAT=$(echo "$GPS" | cut -d';' -f1)
    echo " ✅"
    echo "   📍 GPS: ${LAT:-nav fiksācijas}  🌡️  Spiediens: ${BARO:-?} hPa  📏 Augstums: ${BARO_ALT:-?}m  🔋 ${BATT:-?}%"
    echo "   (#$reading — nākamais pēc ${INTERVAL}s)"
    echo ""

    sleep "$INTERVAL"
done
