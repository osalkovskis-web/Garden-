#!/data/data/com.termux/files/usr/bin/bash
# Interactive elevation survey — walk to each point, press ENTER, averages 10 GPS readings

P0=1013.25
READINGS=10
LOG_DIR="$HOME/storage/downloads"
DATE=$(date +%Y%m%d)
JSON_OUT="$LOG_DIR/survey_${DATE}.json"

# Pre-defined survey points (id, Latvian label)
declare -a POINT_IDS=("SW" "NW" "NE" "SE" "hugel" "majas" "plude")
declare -A POINT_LABELS=(
    ["SW"]="Dienvidrietumu stūris"
    ["NW"]="Ziemeļrietumu stūris"
    ["NE"]="Ziemeļaustrumu stūris"
    ["SE"]="Dienvidaustrumu stūris"
    ["hugel"]="Hugel gultne"
    ["majas"]="Māja / kabīne"
    ["plude"]="Plūdu atsauces punkts"
)

baro_altitude() {
    python3 -c "print(round(44330 * (1 - ($1/$P0)**(1/5.255)), 2))" 2>/dev/null || echo "N/A"
}

avg_values() {
    # avg of semicolon-separated space-separated list: "v1 v2 v3 ..."
    python3 -c "
vals=[float(x) for x in '$1'.split() if x]
print(round(sum(vals)/len(vals),4) if vals else '')
" 2>/dev/null
}

echo ""
echo "🗺️  Augstuma uzmērīšana — Kazas sēklis, Lucavsala"
echo "==================================================="
echo "Katrā punktā nospied ENTER, tad uzgaidi 10 GPS nolasījumus"
echo ""

# JSON accumulator
json_points="["
first=true

for pid in "${POINT_IDS[@]}"; do
    label="${POINT_LABELS[$pid]}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 Punkts: $label ($pid)"
    echo "   Dodies uz šo punktu un nospied ENTER..."
    read -r

    echo "   ⏳ Nolasa $READINGS GPS mērījumus, lūdzu uzgaidi..."

    lats="" lons="" alts="" baros=""
    i=1
    while [ $i -le $READINGS ]; do
        result=$(termux-location -p gps -r once 2>/dev/null)
        lat=$(echo "$result" | jq -r '.latitude // empty' 2>/dev/null)
        lon=$(echo "$result" | jq -r '.longitude // empty' 2>/dev/null)
        alt=$(echo "$result" | jq -r '.altitude // empty' 2>/dev/null)

        if [ -n "$lat" ] && [ "$lat" != "null" ]; then
            lats="$lats $lat"
            lons="$lons $lon"
            alts="$alts $alt"
            echo -n "   GPS $i/$READINGS ✅  "
        else
            echo -n "   GPS $i/$READINGS ⏳  "
        fi

        # Barometer reading
        baro_result=$(termux-sensor -s "pressure" -n 1 2>/dev/null)
        baro=$(echo "$baro_result" | jq -r '.["TYPE_PRESSURE"].values[0] // empty' 2>/dev/null)
        [ -n "$baro" ] && baros="$baros $baro"

        ((i++))
        sleep 2
    done
    echo ""

    # Calculate averages
    avg_lat=$(avg_values "$lats")
    avg_lon=$(avg_values "$lons")
    avg_alt=$(avg_values "$alts")
    avg_baro=$(avg_values "$baros")
    baro_alt=""
    [ -n "$avg_baro" ] && baro_alt=$(baro_altitude "$avg_baro")

    echo ""
    echo "   📊 Rezultāti:"
    echo "   Platuma gr.:    ${avg_lat:-N/A}"
    echo "   Garuma gr.:     ${avg_lon:-N/A}"
    echo "   GPS augstums:   ${avg_alt:-N/A} m"
    echo "   Barometrs:      ${avg_baro:-N/A} hPa"
    echo "   Baro augstums:  ${baro_alt:-N/A} m"
    echo ""

    # Build JSON entry
    $first || json_points+=","
    first=false
    json_points+="{
    \"id\": \"$pid\",
    \"label\": \"$label\",
    \"latitude\": ${avg_lat:-null},
    \"longitude\": ${avg_lon:-null},
    \"gps_altitude_m\": ${avg_alt:-null},
    \"baro_pressure_hpa\": ${avg_baro:-null},
    \"baro_altitude_m\": ${baro_alt:-null},
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }"
done

json_points+="]"

# Write JSON
cat > "$JSON_OUT" << JSONEOF
{
  "survey_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "location": "Kazas sēklis, Lucavsala, Rīga",
  "coordinates_wgs84": "56.9N, 24.1E",
  "points": $json_points
}
JSONEOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Uzmērīšana pabeigta!"
echo ""
echo "📋 Kopsavilkums:"
printf "%-6s %-28s %10s %10s %12s\n" "ID" "Nosaukums" "GPS alt(m)" "Baro(hPa)" "Baro alt(m)"
echo "------------------------------------------------------------------------"

# Print summary table by re-reading JSON
python3 - "$JSON_OUT" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for p in data["points"]:
    print(f"{p['id']:<6} {p['label']:<28} {str(p.get('gps_altitude_m','N/A')):>10} {str(p.get('baro_pressure_hpa','N/A')):>10} {str(p.get('baro_altitude_m','N/A')):>12}")
PYEOF

echo ""
echo "💾 JSON saglabāts: $JSON_OUT"
echo ""
