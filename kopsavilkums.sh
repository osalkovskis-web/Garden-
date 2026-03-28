#!/data/data/com.termux/files/usr/bin/bash
# Parse today's CSV and print daily summary with flood/storm warnings

LOG_DIR="$HOME/storage/downloads"
DATE=$(date +%Y%m%d)
CSV="$LOG_DIR/darzs_log_${DATE}.csv"

echo ""
echo "📊 Dienas kopsavilkums — $(date +%d.%m.%Y)"
echo "============================================"

if [ ! -f "$CSV" ]; then
    echo "❌ Nav datu faila: $CSV"
    echo "   Vispirms palaid: bash darzs_log.sh"
    echo ""
    exit 1
fi

python3 - "$CSV" << 'PYEOF'
import sys, csv
from datetime import datetime

file = sys.argv[1]
rows = []

with open(file, encoding="utf-8-sig") as f:
    reader = csv.DictReader(f, delimiter=";")
    for row in reader:
        rows.append(row)

if not rows:
    print("❌ Fails ir tukšs — nav nolasījumu")
    sys.exit(1)

total = len(rows)
print(f"\n📋 Kopā nolasījumi: {total}")

# --- Barometric pressure ---
baros = []
for r in rows:
    try:
        v = float(r.get("baro_pressure_hpa",""))
        baros.append(v)
    except:
        pass

if baros:
    print(f"\n🌡️  Atmosfēras spiediens (hPa):")
    print(f"   Min:  {min(baros):.1f}")
    print(f"   Max:  {max(baros):.1f}")
    print(f"   Vid:  {sum(baros)/len(baros):.1f}")

    # Storm warning: pressure drop > 5 hPa between first and last reading
    if len(baros) >= 2:
        drop = baros[0] - baros[-1]
        if drop > 5:
            print(f"\n⚠️  VĒTRA: Spiediens kritis par {drop:.1f} hPa — iespējama vētra!")
        elif drop > 2:
            print(f"\n⚠️  Spiediens krītas ({drop:.1f} hPa) — mainīgs laiks")
        else:
            print(f"   ✅ Spiediens stabils (izmaiņas: {drop:+.1f} hPa)")

    # Flood risk based on absolute pressure
    avg_p = sum(baros)/len(baros)
    baro_alt = 44330 * (1 - (avg_p/1013.25)**(1/5.255))
    print(f"\n📏 Vidējais barometiskais augstums: {baro_alt:.1f} m")
    if baro_alt < 0.3:
        print("🚨 PLŪDU RISKS: Augstums zem 30cm — augsts plūdu risks!")
    elif baro_alt < 0.6:
        print("⚠️  UZMANĪBU: Augstums zem 60cm — paaugstināts plūdu risks")
    else:
        print("✅ Plūdu risks: zems")
else:
    print("\n⚠️  Nav spiediena datu")

# --- GPS altitude ---
alts = []
for r in rows:
    try:
        v = float(r.get("gps_altitude_m",""))
        alts.append(v)
    except:
        pass

if alts:
    print(f"\n📍 GPS augstums (m):")
    print(f"   Min:  {min(alts):.2f}")
    print(f"   Max:  {max(alts):.2f}")
    print(f"   Vid:  {sum(alts)/len(alts):.2f}")

# --- Anomaly detection ---
print("\n🔍 Anomāliju pārbaude:")
anomalies = 0
if len(baros) >= 4:
    for i in range(1, len(baros)):
        diff = abs(baros[i] - baros[i-1])
        if diff > 3:
            print(f"   ⚠️  Straujš spiediena lēciens: {baros[i-1]:.1f} → {baros[i]:.1f} hPa")
            anomalies += 1
if anomalies == 0:
    print("   ✅ Nav anomāliju")

# --- Time range ---
timestamps = [r.get("timestamp","") for r in rows if r.get("timestamp")]
if timestamps:
    print(f"\n⏱️  Periods: {timestamps[0]} → {timestamps[-1]}")

print("")
PYEOF
