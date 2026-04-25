#!/usr/bin/env python3
"""
Kapacitīvā mitruma sensora kalibrācija caur seriālo portu.

Palaiž: python3 calibrate.py [PORT]
  PORT — seriālais ports, piem. /dev/ttyUSB0 vai COM3
         Ja netiek norādīts, meklē automātiski.

Pēc kalibrācijas saglabā EEPROM uz ESP32.
Protokols: ASCII komandas caur Serial 115200 baud.
Firmware (sensor_node) jāpievieno šis kalibrators_handler() — skat. zemāk.
"""

import sys
import time
import struct
import serial
import serial.tools.list_ports

BAUD = 115200
MAGIC = 0xCAFEBABE

# ── Seriālā porta atrašana ────────────────────────────────────────────────────
def find_port():
    ports = list(serial.tools.list_ports.comports())
    esp_ports = [p for p in ports if
                 "USB" in p.description or "CP210" in p.description or
                 "CH340" in p.description or "FTDI" in p.description]
    if not esp_ports:
        print("❌ Nav atrasts ESP32 seriālais ports.")
        print("   Pievienojiet ESP32 ar USB un mēģiniet vēlreiz.")
        print(f"   Pieejamie porti: {[p.device for p in ports] or 'nav'}")
        sys.exit(1)
    if len(esp_ports) == 1:
        return esp_ports[0].device
    print("Vairāki porti:")
    for i, p in enumerate(esp_ports):
        print(f"  {i+1}. {p.device} — {p.description}")
    n = int(input("Izvēlies numuru: ")) - 1
    return esp_ports[n].device

# ── ADC nolasīšana no ESP32 ───────────────────────────────────────────────────
def read_adc(ser, samples=20, delay_s=0.1):
    """Sūta 'READ' komandu, saņem ADC vērtības."""
    readings = []
    ser.write(b"CALIB_READ\n")
    deadline = time.time() + 5.0
    while len(readings) < samples and time.time() < deadline:
        line = ser.readline().decode("utf-8", errors="ignore").strip()
        if line.startswith("ADC:"):
            try:
                readings.append(int(line.split(":")[1]))
            except ValueError:
                pass
        time.sleep(delay_s)
    return readings

def median(vals):
    s = sorted(vals)
    n = len(s)
    return s[n//2] if n % 2 else (s[n//2-1] + s[n//2]) // 2

def write_calib(ser, dry, wet):
    """Sūta kalibrācijas vērtības uz ESP32 EEPROM."""
    cmd = f"CALIB_SAVE:{dry}:{wet}\n".encode()
    ser.write(cmd)
    deadline = time.time() + 3.0
    while time.time() < deadline:
        line = ser.readline().decode("utf-8", errors="ignore").strip()
        if "CALIB_OK" in line:
            return True
    return False

# ── Galvenā plūsma ────────────────────────────────────────────────────────────
def main():
    port = sys.argv[1] if len(sys.argv) > 1 else find_port()
    print(f"\n🌱 Mitruma sensora kalibrācija — {port}")
    print("=" * 45)
    print("Pārliecinies, ka sensor_node firmware ir uzlādēts")
    print("un ESP32 darbojas normāli (seriālais monitors atvērts).\n")

    try:
        ser = serial.Serial(port, BAUD, timeout=2)
    except serial.SerialException as e:
        print(f"❌ Nevar atvērt portu: {e}")
        sys.exit(1)

    time.sleep(2)  # ESP32 boot
    ser.reset_input_buffer()

    # ── SAUSAIS punkts ────────────────────────────────────────────────────────
    print("SOLIS 1/2 — Sauss sensors")
    print("-" * 30)
    input("  Izņem sensoru no augsnes (vai turi gaisā).\n"
          "  Kad gatavs, nospied ENTER...")
    print("  Mēra...", end="", flush=True)
    dry_readings = read_adc(ser)
    if not dry_readings:
        print("\n❌ Nav saņemtas ADC vērtības. Pārbaudi firmware.")
        ser.close()
        sys.exit(1)
    dry_val = median(dry_readings)
    print(f" ✅  Sauss ADC: {dry_val}  (no {len(dry_readings)} mērījumiem: {dry_readings})")

    # ── MITRAIS punkts ────────────────────────────────────────────────────────
    print("\nSOLIS 2/2 — Mitrs sensors")
    print("-" * 30)
    input("  Ieliec sensoru glāzē ar ūdeni (tieši līdz līnijai uz sensora).\n"
          "  Pagaidi 10 sekundes, tad nospied ENTER...")
    print("  Mēra...", end="", flush=True)
    wet_readings = read_adc(ser)
    if not wet_readings:
        print("\n❌ Nav saņemtas ADC vērtības.")
        ser.close()
        sys.exit(1)
    wet_val = median(wet_readings)
    print(f" ✅  Mitrs ADC: {wet_val}  (no {len(wet_readings)} mērījumiem: {wet_readings})")

    # ── Validācija ────────────────────────────────────────────────────────────
    print()
    if wet_val >= dry_val:
        print("⚠️  BRĪDINĀJUMS: mitrais ADC >= sauss ADC.")
        print("   Kapacitīviem sensoriem mitrā augsnē ADC jābūt MAZĀKAM.")
        print("   Pārbaudi pievienojumus vai sensoru.")
    elif (dry_val - wet_val) < 200:
        print("⚠️  BRĪDINĀJUMS: atšķirība < 200 ADC vienības. Sensors var būt bojāts.")
    else:
        print(f"✅  Kalibrācija OK  |  Sauss: {dry_val}  Mitrs: {wet_val}  "
              f"Diapazons: {dry_val - wet_val}")

    # ── Saglabāšana EEPROM ────────────────────────────────────────────────────
    print()
    save = input("Saglabāt kalibrāciju ESP32 EEPROM? [J/n]: ").strip().lower()
    if save in ("", "j", "y", "jā", "yes"):
        ok = write_calib(ser, dry_val, wet_val)
        if ok:
            print("✅  Kalibrācija saglabāta EEPROM!")
        else:
            print("❌  Kļūda saglabājot. Pārbaudi firmware vai pievienojumus.")
    else:
        print("ℹ️  Kalibrācija netika saglabāta.")

    # ── Procentu skala ────────────────────────────────────────────────────────
    print("\nProcentu skala (pēc kalibrācijas):")
    print(f"  {'ADC':>6}  {'Mitrums':>8}")
    print(f"  {'-'*6}  {'-'*8}")
    for pct in range(0, 101, 10):
        adc = int(dry_val - pct * (dry_val - wet_val) / 100)
        print(f"  {adc:>6}  {pct:>7}%")

    ser.close()
    print("\nPabeidzis. Aizver seriālo monitoru un atkārtoti uzlādē firmware.")

if __name__ == "__main__":
    main()
