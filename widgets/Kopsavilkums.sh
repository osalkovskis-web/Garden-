#!/data/data/com.termux/files/usr/bin/bash
# Widget: Show today's summary as Android notification

REPO="$HOME/Garden-"
LOG_DIR="$HOME/storage/downloads"
DATE=$(date +%Y%m%d)
CSV="$LOG_DIR/darzs_log_${DATE}.csv"

if [ ! -f "$CSV" ]; then
    termux-toast -s "📭 Nav datu šodienai. Vispirms palaid logging!"
    exit 0
fi

# Build summary text
SUMMARY=$(python3 - "$CSV" << 'PYEOF'
import sys, csv

rows = []
with open(sys.argv[1], encoding="utf-8-sig") as f:
    for row in csv.DictReader(f, delimiter=";"):
        rows.append(row)

if not rows:
    print("Nav datu")
    sys.exit()

baros = []
for r in rows:
    try: baros.append(float(r["baro_pressure_hpa"]))
    except: pass

P0 = 1013.25
lines = [f"Nolasījumi: {len(rows)}"]

if baros:
    avg_p = sum(baros)/len(baros)
    alt = round(44330 * (1 - (avg_p/P0)**(1/5.255)), 1)
    trend = round(baros[-1]-baros[0], 1) if len(baros)>1 else 0
    lines.append(f"Spiediens: {round(avg_p,1)} hPa")
    lines.append(f"Augstums: {alt} m")
    trend_sym = "↓" if trend < -2 else ("↑" if trend > 2 else "→")
    lines.append(f"Tendence: {trend_sym} {trend:+.1f} hPa")
    if alt < 0.3:
        lines.append("🚨 PLŪDU RISKS: AUGSTS")
    elif alt < 0.6:
        lines.append("⚠️ Plūdu risks: vidējs")
    else:
        lines.append("✅ Plūdu risks: zems")
    if trend < -5:
        lines.append("⛈️ VĒTRAS BRĪDINĀJUMS!")

print(" | ".join(lines))
PYEOF
)

termux-notification \
    --title "🌱 Dārza kopsavilkums — $(date +%d.%m.%Y)" \
    --content "$SUMMARY" \
    --id 42 \
    --priority high

termux-toast "$SUMMARY"
