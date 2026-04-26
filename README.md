# 🌱 Dārza monitors — Kazas sēklis, Lucavsala

Autonomous garden monitoring system for a 438m² plot on Kazas sēklis island, Lucavsala, Riga, Latvia (56.9°N, 24.1°E). Runs on a Pixel 9 phone via Termux. Monitors GPS, barometric pressure, elevation, light, and photos. Includes flood and storm warnings.

**[📱 Open Web Dashboard →](https://osalkovskis-web.github.io/Garden-/)**

> **IoT augsnes mitruma sensoru sistēma** (ESP32 + ESP-NOW + 4G + Home Assistant) → **[iot/README.md](iot/README.md)**

---

## Hardware

- **Device:** Pixel 9 (Android, Termux + Termux:API)
- **Location:** Kazas sēklis, Lucavsala, Rīga — elevation ~60cm, subject to spring flooding
- **Sensors:** GPS, barometer, accelerometer, light, magnetometer, humidity (via Termux:API)

---

## Setup

### 1. Install on phone (Termux)

```bash
pkg install git termux-api python jq -y
git clone git@github.com:osalkovskis-web/Garden-.git ~/Garden-
cd ~/Garden-
bash check_setup.sh
```

### 2. Set up home screen widgets (Termux:Widget)

```bash
bash setup_widgets.sh
```

Then long-press home screen → Widgets → Termux:Widget → drag to screen.

### 3. Open the web dashboard

Start the server:
```bash
bash web.sh
```

Then open **http://localhost:8080** on the phone, or the IP shown in terminal from another device on the same WiFi.

Or use the hosted PWA: **https://osalkovskis-web.github.io/Garden-/**

---

## Scripts

| Script | Description |
|---|---|
| `start.sh` | Main menu launcher (Latvian UI) |
| `check_setup.sh` | Checks and auto-installs all dependencies |
| `darzs_log.sh` | Continuous sensor logging every 30s → CSV |
| `augstuma_karte.sh` | Interactive elevation survey (10 GPS readings/point) |
| `foto_log.sh` | Watches DCIM, logs GPS + metadata for each photo |
| `kopsavilkums.sh` | Daily summary — pressure stats, flood risk, storm warnings |
| `web.sh` | Starts Flask web dashboard on port 8080 |
| `setup_widgets.sh` | Installs home screen widget shortcuts |

## Home screen widgets

| Widget | Action |
|---|---|
| `Sakt_logging` | 📡 Start sensor recording in background |
| `Atvērt_dashboard` | 🌐 Start server + open browser |
| `Foto_logging` | 📸 Watch camera roll, log GPS per photo |
| `Kopsavilkums` | 📊 Today's summary as notification |
| `Apturet_visu` | ⏹ Stop all background processes |

---

## Data files

All saved to `~/storage/downloads/`:

| File | Contents |
|---|---|
| `darzs_log_YYYYMMDD.csv` | Timestamped sensor readings (semicolon-separated, UTF-8 BOM) |
| `foto_log.csv` | Photo log with GPS coordinates |
| `survey_YYYYMMDD.json` | Elevation survey results per plot point |

CSV files open directly in Excel / LibreOffice.

---

## Flood & storm warnings

- Barometric altitude < 60cm → ⚠️ elevated flood risk
- Barometric altitude < 30cm → 🚨 high flood risk
- Pressure drop > 5 hPa → ⛈️ storm warning

Elevation formula: `h = 44330 × (1 − (P / 1013.25)^(1/5.255))`

---

## Web dashboard (PWA)

The dashboard is installable as a home screen app:

1. Open **https://osalkovskis-web.github.io/Garden-/** in Chrome
2. Tap **"Add to Home Screen"** when prompted
3. Start the local server: `bash ~/Garden-/web.sh`
4. The app connects to `localhost:8080` for live data

Features: live sensor readings, pressure/altitude chart, daily stats, flood risk badge, recent photos log.
