#!/data/data/com.termux/files/usr/bin/python3
# Garden monitoring web dashboard
# Serves on http://0.0.0.0:8080 — open from any device on same WiFi

import os, csv, json, subprocess, threading, time
from datetime import datetime
from flask import Flask, jsonify, Response

app = Flask(__name__)
LOG_DIR = os.path.expanduser("~/storage/downloads")
P0 = 1013.25

# --- Helpers ---

def today_csv():
    date = datetime.now().strftime("%Y%m%d")
    return os.path.join(LOG_DIR, f"darzs_log_{date}.csv")

def baro_alt(p):
    try:
        return round(44330 * (1 - (float(p) / P0) ** (1 / 5.255)), 2)
    except:
        return None

def read_csv_rows(path, limit=None):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            rows.append(row)
    return rows[-limit:] if limit else rows

def safe_float(val):
    try:
        return float(val)
    except:
        return None

def get_live_sensor():
    """Read one sensor sample right now via termux-api"""
    result = {}
    try:
        loc = subprocess.run(
            ["termux-location", "-p", "gps", "-r", "once"],
            capture_output=True, text=True, timeout=10
        )
        loc_data = json.loads(loc.stdout)
        result["latitude"] = loc_data.get("latitude")
        result["longitude"] = loc_data.get("longitude")
        result["gps_altitude"] = loc_data.get("altitude")
    except:
        pass
    try:
        baro = subprocess.run(
            ["termux-sensor", "-s", "pressure", "-n", "1"],
            capture_output=True, text=True, timeout=5
        )
        baro_data = json.loads(baro.stdout)
        p = baro_data.get("TYPE_PRESSURE", {}).get("values", [None])[0]
        result["pressure"] = p
        result["baro_altitude"] = baro_alt(p) if p else None
    except:
        pass
    try:
        bat = subprocess.run(
            ["termux-battery-status"],
            capture_output=True, text=True, timeout=5
        )
        bat_data = json.loads(bat.stdout)
        result["battery"] = bat_data.get("percentage")
    except:
        pass
    result["timestamp"] = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    return result

# --- API routes ---

@app.route("/api/live")
def api_live():
    return jsonify(get_live_sensor())

@app.route("/api/today")
def api_today():
    rows = read_csv_rows(today_csv())
    if not rows:
        return jsonify({"error": "Nav datu", "count": 0})

    baros = [safe_float(r.get("baro_pressure_hpa")) for r in rows]
    baros = [b for b in baros if b is not None]
    alts  = [safe_float(r.get("gps_altitude_m")) for r in rows]
    alts  = [a for a in alts if a is not None]

    summary = {
        "count": len(rows),
        "first_ts": rows[0].get("timestamp", ""),
        "last_ts": rows[-1].get("timestamp", ""),
        "pressure": {
            "min": round(min(baros), 1) if baros else None,
            "max": round(max(baros), 1) if baros else None,
            "avg": round(sum(baros)/len(baros), 1) if baros else None,
            "trend": round(baros[-1] - baros[0], 1) if len(baros) >= 2 else None,
        },
        "gps_altitude": {
            "min": round(min(alts), 2) if alts else None,
            "max": round(max(alts), 2) if alts else None,
            "avg": round(sum(alts)/len(alts), 2) if alts else None,
        },
        "flood_risk": _flood_risk(baros),
        "storm_warning": _storm_warning(baros),
    }
    return jsonify(summary)

@app.route("/api/chart")
def api_chart():
    rows = read_csv_rows(today_csv())
    labels, pressures, baro_alts = [], [], []
    for r in rows:
        ts = r.get("timestamp", "")
        p  = safe_float(r.get("baro_pressure_hpa"))
        if ts and p:
            labels.append(ts[11:16])  # HH:MM
            pressures.append(p)
            baro_alts.append(baro_alt(p))
    return jsonify({"labels": labels, "pressure": pressures, "baro_altitude": baro_alts})

@app.route("/api/photos")
def api_photos():
    csv_path = os.path.join(LOG_DIR, "foto_log.csv")
    rows = read_csv_rows(csv_path, limit=10)
    rows.reverse()
    return jsonify(rows)

def _flood_risk(baros):
    if not baros:
        return "unknown"
    avg_p = sum(baros) / len(baros)
    alt = baro_alt(avg_p)
    if alt is None:
        return "unknown"
    if alt < 0.3:
        return "high"
    if alt < 0.6:
        return "medium"
    return "low"

def _storm_warning(baros):
    if len(baros) < 2:
        return False
    return (baros[0] - baros[-1]) > 5

# --- Main HTML page ---

HTML = """<!DOCTYPE html>
<html lang="lv">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>🌱 Dārza monitors</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
<style>
  :root {
    --green: #2d7a3a; --green-light: #e8f5e9; --yellow: #f9a825;
    --red: #c62828; --blue: #1565c0; --gray: #555; --card-bg: #fff;
    --bg: #f1f8f1;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: var(--bg); color: #222; }
  header { background: var(--green); color: #fff; padding: 1rem 1.5rem; }
  header h1 { font-size: 1.3rem; }
  header p  { font-size: 0.85rem; opacity: 0.85; margin-top: 2px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
          gap: 0.75rem; padding: 1rem; }
  .card { background: var(--card-bg); border-radius: 12px; padding: 1rem;
          box-shadow: 0 1px 4px rgba(0,0,0,.1); }
  .card .label { font-size: 0.72rem; color: var(--gray); text-transform: uppercase;
                 letter-spacing: .05em; margin-bottom: 4px; }
  .card .value { font-size: 1.6rem; font-weight: 700; color: var(--green); }
  .card .unit  { font-size: 0.75rem; color: var(--gray); }
  .card.warn   { border-left: 4px solid var(--yellow); }
  .card.danger { border-left: 4px solid var(--red); }
  .card.ok     { border-left: 4px solid var(--green); }
  .section { padding: 0 1rem 1rem; }
  .section h2 { font-size: 0.9rem; color: var(--gray); text-transform: uppercase;
                letter-spacing: .07em; margin-bottom: 0.5rem; }
  .chart-box { background: var(--card-bg); border-radius: 12px; padding: 1rem;
               box-shadow: 0 1px 4px rgba(0,0,0,.1); }
  .badge { display: inline-block; padding: 2px 10px; border-radius: 99px;
           font-size: 0.8rem; font-weight: 600; }
  .badge.low    { background: #c8e6c9; color: #1b5e20; }
  .badge.medium { background: #fff9c4; color: #f57f17; }
  .badge.high   { background: #ffcdd2; color: #b71c1c; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
  td, th { padding: 6px 8px; border-bottom: 1px solid #eee; text-align: left; }
  th { color: var(--gray); font-weight: 600; }
  .ts { color: #aaa; font-size: 0.75rem; text-align: right; padding: 0.5rem 1rem; }
  .btn { background: var(--green); color: #fff; border: none; border-radius: 8px;
         padding: 0.5rem 1.2rem; font-size: 0.9rem; cursor: pointer; margin: 0 1rem 1rem; }
  .btn:active { opacity: 0.8; }
</style>
</head>
<body>
<header>
  <h1>🌱 Dārza monitors</h1>
  <p>Kazas sēklis, Lucavsala, Rīga — 56.9°N 24.1°E</p>
</header>

<div id="alert-box"></div>

<div id="live-grid" class="grid"></div>

<div class="section">
  <h2>📊 Šodienas kopsavilkums</h2>
  <div class="chart-box">
    <canvas id="pressureChart" height="180"></canvas>
  </div>
</div>

<div class="section" style="margin-top:0.75rem">
  <h2>📋 Statistika</h2>
  <div class="card" id="stats-card">Ielādē...</div>
</div>

<div class="section" style="margin-top:0.75rem">
  <h2>📸 Pēdējie foto</h2>
  <div class="card"><table id="photo-table"><tr><td>Ielādē...</td></tr></table></div>
</div>

<button class="btn" onclick="refreshAll()">🔄 Atjaunināt</button>
<div class="ts" id="last-update"></div>

<script>
let chart = null;

function fmt(v, dec=1) {
  return (v !== null && v !== undefined) ? Number(v).toFixed(dec) : '—';
}

function riskBadge(risk) {
  const labels = {low:'✅ Zems', medium:'⚠️ Vidējs', high:'🚨 Augsts', unknown:'❓'};
  return `<span class="badge ${risk}">${labels[risk]||risk}</span>`;
}

async function loadLive() {
  try {
    const d = await fetch('/api/live').then(r=>r.json());
    const cards = [
      { label:'Spiediens', value: fmt(d.pressure), unit:'hPa', cls: '' },
      { label:'Baro augstums', value: fmt(d.baro_altitude), unit:'m', cls: '' },
      { label:'GPS augstums', value: fmt(d.gps_altitude), unit:'m', cls: '' },
      { label:'Platums', value: d.latitude ? Number(d.latitude).toFixed(5) : '—', unit:'°N', cls: '' },
      { label:'Garums', value: d.longitude ? Number(d.longitude).toFixed(5) : '—', unit:'°E', cls: '' },
      { label:'Akumulators', value: d.battery ?? '—', unit:'%', cls: d.battery < 20 ? 'warn' : '' },
    ];
    document.getElementById('live-grid').innerHTML = cards.map(c =>
      `<div class="card ${c.cls}">
        <div class="label">${c.label}</div>
        <div class="value">${c.value} <span class="unit">${c.unit}</span></div>
      </div>`
    ).join('');
  } catch(e) {
    document.getElementById('live-grid').innerHTML = '<div class="card">❌ Nav savienojuma ar sensoriem</div>';
  }
}

async function loadChart() {
  try {
    const d = await fetch('/api/chart').then(r=>r.json());
    const ctx = document.getElementById('pressureChart').getContext('2d');
    if (chart) chart.destroy();
    chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: d.labels,
        datasets: [
          { label: 'Spiediens (hPa)', data: d.pressure, borderColor: '#2d7a3a',
            backgroundColor: 'rgba(45,122,58,.08)', tension: 0.3, yAxisID: 'y1' },
          { label: 'Baro augstums (m)', data: d.baro_altitude, borderColor: '#1565c0',
            backgroundColor: 'rgba(21,101,192,.06)', tension: 0.3, yAxisID: 'y2',
            borderDash: [4,3] },
        ]
      },
      options: {
        responsive: true,
        interaction: { mode: 'index', intersect: false },
        scales: {
          y1: { type:'linear', position:'left', title:{ display:true, text:'hPa' } },
          y2: { type:'linear', position:'right', title:{ display:true, text:'m' },
                grid:{ drawOnChartArea:false } }
        },
        plugins: { legend: { position:'bottom' } }
      }
    });
  } catch(e) {}
}

async function loadStats() {
  try {
    const d = await fetch('/api/today').then(r=>r.json());
    if (d.error) { document.getElementById('stats-card').innerHTML = '📭 '+d.error; return; }
    const stormTxt = d.storm_warning
      ? '<p style="color:#c62828;font-weight:600">⚠️ Vētras brīdinājums! Spiediens krītas strauji.</p>' : '';
    document.getElementById('stats-card').innerHTML = `
      ${stormTxt}
      <table>
        <tr><th>Parametrs</th><th>Min</th><th>Vid</th><th>Max</th></tr>
        <tr><td>Spiediens (hPa)</td><td>${fmt(d.pressure.min)}</td>
            <td>${fmt(d.pressure.avg)}</td><td>${fmt(d.pressure.max)}</td></tr>
        <tr><td>GPS augstums (m)</td><td>${fmt(d.gps_altitude.min,2)}</td>
            <td>${fmt(d.gps_altitude.avg,2)}</td><td>${fmt(d.gps_altitude.max,2)}</td></tr>
      </table>
      <div style="margin-top:.75rem;display:flex;gap:.5rem;align-items:center">
        <span style="font-size:.85rem;color:#555">Plūdu risks:</span>
        ${riskBadge(d.flood_risk)}
        <span style="font-size:.8rem;color:#aaa;margin-left:auto">${d.count} nolasījumi</span>
      </div>`;
  } catch(e) {}
}

async function loadPhotos() {
  try {
    const rows = await fetch('/api/photos').then(r=>r.json());
    if (!rows.length) { document.getElementById('photo-table').innerHTML = '<tr><td>Nav foto</td></tr>'; return; }
    const head = '<tr><th>Fails</th><th>Laiks</th><th>GPS</th><th>KB</th></tr>';
    const body = rows.map(r =>
      `<tr><td>${r.filename||'—'}</td><td>${(r.timestamp||'').slice(11,19)}</td>
       <td>${r.latitude ? Number(r.latitude).toFixed(4)+', '+Number(r.longitude).toFixed(4) : '—'}</td>
       <td>${r.filesize_kb||'—'}</td></tr>`
    ).join('');
    document.getElementById('photo-table').innerHTML = head + body;
  } catch(e) {}
}

async function refreshAll() {
  await Promise.all([loadLive(), loadChart(), loadStats(), loadPhotos()]);
  document.getElementById('last-update').textContent =
    'Atjaunināts: ' + new Date().toLocaleTimeString('lv-LV');
}

// Auto-refresh every 60s
refreshAll();
setInterval(refreshAll, 60000);
</script>
</body>
</html>"""

@app.route("/")
def index():
    return Response(HTML, mimetype="text/html")

if __name__ == "__main__":
    import socket
    # Find local IP to show user
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except:
        local_ip = "localhost"

    print()
    print("🌱 Dārza web monitors palaists!")
    print("================================")
    print(f"📱 Telefonā:   http://localhost:8080")
    print(f"💻 MacBook/PC: http://{local_ip}:8080")
    print()
    print("Nospied Ctrl+C lai apturētu")
    print()
    app.run(host="0.0.0.0", port=8080, debug=False)
