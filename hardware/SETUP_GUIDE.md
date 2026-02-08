# Raspberry Pi 3B+ Setup for ClassPulse

This guide follows `PLAN.md` exactly and prepares a Raspberry Pi 3B+ to host the Flask-based attendance server with BLE beaconing and camera verification.

## 1. Prerequisites

- Raspberry Pi 3B+ with Raspberry Pi OS (64-bit recommended)
- microSD card (32 GB class 10)
- USB keyboard, mouse, HDMI display (first boot)
- Official Raspberry Pi camera module
- Stable 5V/2.5A power supply
- Classroom Wi-Fi credentials with WPA2 security

## 2. Operating System Installation

1. Flash Raspberry Pi OS using Raspberry Pi Imager.
2. During imaging enable SSH and set a strong password.
3. Boot the Pi, connect to the display for initial configuration.
4. Run `sudo raspi-config` and:
   - Expand filesystem (if using legacy OS image).
   - Enable Camera (Interface Options > Legacy Camera).
   - Set locale, timezone, keyboard layout.
5. Update packages:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

## 3. Python Environment

1. Install prerequisites:

```bash
sudo apt install -y python3-pip python3-venv libatlas-base-dev libbluetooth-dev bluetooth bluez
```

2. Create project directory:

```bash
mkdir -p ~/classpulse/server
cd ~/classpulse/server
python3 -m venv .venv
source .venv/bin/activate
```

3. Upgrade pip and wheel:

```bash
pip install --upgrade pip wheel
```

## 4. Required Python Packages

Install the packages defined in `PLAN.md`:

```bash
pip install flask gunicorn pybluez opencv-python sqlite-utils firebase-admin python-dotenv requests
```

- `flask` serves REST endpoints (`/api/register`, `/api/heartbeat`).
- `gunicorn` provides a production WSGI server.
- `pybluez` manages BLE beacon broadcasting.
- `opencv-python` powers camera-based headcount using `haarcascade_frontalface_default.xml`.
- `sqlite-utils` simplifies local SQLite management.
- `firebase-admin` handles syncing final attendance records to Firestore.

## 5. Project Structure

```
~/classpulse/server
├── .venv/
├── app/
│   ├── __init__.py
│   ├── api.py
│   ├── ble.py
│   ├── camera.py
│   ├── database.py
│   ├── scheduler.py
│   └── sync.py
├── instance/
│   └── attendance.db
├── haars/
│   └── haarcascade_frontalface_default.xml
├── gunicorn_config.py
├── requirements.txt
└── run.py
```

Use this layout when porting the Flask implementation from the plan.

## 6. SQLite Database

Initialize the local database as described:

```bash
sqlite3 instance/attendance.db <<'SQL'
CREATE TABLE IF NOT EXISTS students (
  uuid TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  roll_no TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'DISCONNECTED',
  last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQL
```

## 7. BLE Beacon Broadcasting

- Ensure Bluetooth services are running: `sudo systemctl enable --now bluetooth`.
- Use `pybluez` within `app/ble.py` to start advertising the ClassPulse UUID.
- Keep transmit power conservative to reduce proxy risks.

## 8. Camera Headcount

- Connect the Raspberry Pi camera and confirm with `libcamera-still -o test.jpg`.
- Place the `haarcascade` XML file in `haars/` and load it from `app/camera.py` for face detection.
- Schedule periodic captures (e.g., every 10 minutes) via `scheduler.py` and compare counts to connected devices, tagging anomalies as `PROXY_RISK`.

## 9. Flask Application

- Implement REST endpoints per `PLAN.md`:
  - `POST /api/register` to store student profiles in SQLite.
  - `POST /api/heartbeat` to update `last_seen` and mark `CONNECTED`.
  - `GET /dashboard` to render the teacher dashboard with current statuses and camera mismatch alerts.
- Enforce input validation and authentication tokens for registration.
- Apply rate limiting (e.g., Flask-Limiter) to mitigate DoS attempts.

## 10. Gunicorn + Systemd Service

Create `/etc/systemd/system/classpulse.service`:

```
[Unit]
Description=ClassPulse Attendance Server
After=network.target bluetooth.service

[Service]
User=pi
WorkingDirectory=/home/pi/classpulse/server
Environment="PATH=/home/pi/classpulse/server/.venv/bin"
ExecStart=/home/pi/classpulse/server/.venv/bin/gunicorn \
  --workers 3 --bind 0.0.0.0:5000 \
  --config gunicorn_config.py run:app
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now classpulse.service
```

## 11. Security Hardening

- Disable Flask debug mode in production (`FLASK_ENV=production`).
- Configure UFW firewall:

```bash
sudo apt install -y ufw
sudo ufw allow 22/tcp
sudo ufw allow 5000/tcp
sudo ufw enable
```

- Rotate API tokens regularly and store them in `/home/pi/classpulse/server/.env`.
- Keep system packages patched (`sudo apt full-upgrade -y`).

## 12. Firebase Synchronization

- Create a Firebase service account key.
- Place the JSON key in `~/classpulse/server/` with restricted permissions (`chmod 600`).
- Use `firebase-admin` inside `app/sync.py` to push finalized attendance summaries to Firestore once the session ends (`status == PRESENT`).

## 13. Monitoring and Logs

- Inspect Gunicorn logs via `journalctl -u classpulse.service`.
- Expose a lightweight health endpoint (`GET /healthz`) for uptime monitoring.
- Track BLE and camera anomalies in a rolling log stored under `logs/` for audit.

Following these steps keeps the Raspberry Pi server implementation aligned with the system architecture defined in `PLAN.md`.
