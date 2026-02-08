#!/usr/bin/env bash
# ClassPulse Raspberry Pi server bootstrap script. Builds the full server codebase per PLAN.md.

set -euo pipefail

PROJECT_ROOT="${HOME}/classpulse/server"
PYTHON_BIN="python3"
APT_PACKAGES=(
  python3-venv
  libatlas-base-dev
  libbluetooth-dev
  bluetooth
  bluez
  libsqlite3-dev
  libopencv-dev
  pkg-config
  curl
  git
)

log() {
  printf '[setup] %s\n' "$1"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Error: missing required command "%s". Install it first.\n' "$1" >&2
    exit 1
  fi
}

log 'Verifying base dependencies (python3, pip3, sqlite3, systemctl)'
require_cmd "$PYTHON_BIN"
require_cmd pip3
require_cmd sqlite3
require_cmd systemctl

log 'Updating apt packages and installing OS-level prerequisites (may prompt for sudo password)'
sudo apt-get update
sudo apt-get install -y "${APT_PACKAGES[@]}"

log "Creating project directory structure under ${PROJECT_ROOT}"
mkdir -p "${PROJECT_ROOT}/app"
mkdir -p "${PROJECT_ROOT}/instance"
mkdir -p "${PROJECT_ROOT}/haars"
mkdir -p "${PROJECT_ROOT}/logs"
mkdir -p "${PROJECT_ROOT}/templates"

log 'Setting up Python virtual environment'
cd "${PROJECT_ROOT}"
$PYTHON_BIN -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate

log 'Upgrading pip and wheel'
pip install --upgrade pip wheel

log 'Writing requirements.txt with locked versions per PLAN.md'
cat <<'EOF' > requirements.txt
Flask==3.0.3
gunicorn==22.0.0
PyBluez==0.23
opencv-python==4.10.0.84
sqlite-utils==3.36
firebase-admin==6.6.0
python-dotenv==1.0.1
requests==2.32.3
flask-limiter==3.5.0
schedule==1.2.2
itsdangerous==2.2.0
EOF

log 'Installing Python dependencies'
pip install -r requirements.txt

log 'Creating initial SQLite schema with live status tracking'
cat <<'SQL' | sqlite3 instance/attendance.db
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS students (
  uuid TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  roll_no TEXT NOT NULL,
  year TEXT NOT NULL,
  department TEXT NOT NULL,
  section TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'DISCONNECTED',
  last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_rssi INTEGER,
  wifi_ssid TEXT,
  geofence_state TEXT,
  last_metrics TEXT,
  attendance_final TEXT
);

CREATE TABLE IF NOT EXISTS system_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_students_status ON students(status);
CREATE INDEX IF NOT EXISTS idx_students_last_seen ON students(last_seen);
SQL

log 'Fetching Haar cascade for camera headcount'
curl -fsSL -o haars/haarcascade_frontalface_default.xml \
  https://raw.githubusercontent.com/opencv/opencv/master/data/haarcascades/haarcascade_frontalface_default.xml

log 'Creating Flask application package with production-ready modules'
cat <<'EOF' > app/__init__.py
"""Flask application factory for the ClassPulse Pi server."""
from __future__ import annotations

import os
from flask import Flask

from .api import api_bp
from .dashboard import dashboard_bp
from .database import init_app_database
from .scheduler import start_background_tasks
from .ble import start_beacon


def create_app() -> Flask:
    app = Flask(__name__, instance_relative_config=True)

    # Sensible defaults that align with PLAN.md. Instance config overrides them.
    app.config.from_mapping(
        DATABASE_FILENAME='attendance.db',
        REGISTRATION_API_TOKEN='HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM',
        BLE_BEACON_UUID='aea91077-00fb-4345-b748-bd35c153c3a6',
        BLE_MAJOR=1,
        BLE_MINOR=1,
        BLE_TX_POWER=-59,
        CAMERA_INTERVAL_MINUTES=10,
        SYNC_INTERVAL_MINUTES=15,
        SESSION_REQUIRED_MINUTES=45,
        HEARTBEAT_STALE_SECONDS=120,
        FIREBASE_CREDENTIALS='',
        FIREBASE_COLLECTION='attendance_sessions',
    )

    os.makedirs(app.instance_path, exist_ok=True)
    app.config.from_pyfile('config.py', silent=True)
    app.config['DATABASE_PATH'] = os.path.join(app.instance_path, app.config['DATABASE_FILENAME'])

    init_app_database(app)

    app.register_blueprint(api_bp)
    app.register_blueprint(dashboard_bp)

    @app.before_first_request
    def _bootstrap_background_workers() -> None:
        start_beacon(app.config)
        start_background_tasks(app)

    return app
EOF

cat <<'EOF' > app/api.py
"""REST API surface consumed by the Flutter client."""
from __future__ import annotations

import json
from datetime import datetime, timezone

from flask import Blueprint, current_app, jsonify, request
from werkzeug.exceptions import BadRequest, Unauthorized

from .database import (
    finalize_attendance_records,
    list_students,
    register_student,
    update_heartbeat,
)

api_bp = Blueprint('api', __name__)


def _require_token() -> None:
    expected = current_app.config.get('REGISTRATION_API_TOKEN')
    provided = request.headers.get('X-Auth-Token')
    if not expected or provided != expected:
        raise Unauthorized('Invalid or missing X-Auth-Token header.')


@api_bp.get('/healthz')
def health_check():
    return jsonify(status='ok', time=datetime.utcnow().isoformat()), 200


@api_bp.post('/api/register')
def register():
    _require_token()
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        raise BadRequest('Expected JSON payload.')

    required_fields = {'uuid', 'name', 'rollNumber', 'year', 'department', 'section'}
    missing = required_fields - payload.keys()
    if missing:
        raise BadRequest(f'Missing fields: {", ".join(sorted(missing))}')

    register_student(
        uuid=payload['uuid'],
        name=payload['name'],
        roll_no=payload['rollNumber'],
        year=payload['year'],
        department=payload['department'],
        section=payload['section'],
    )

    return jsonify(status='registered'), 201


@api_bp.post('/api/heartbeat')
def heartbeat():
    _require_token()
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        raise BadRequest('Expected JSON payload.')

    uuid = payload.get('uuid')
    metrics = payload.get('metrics', {})
    if not uuid:
        raise BadRequest('Missing uuid field.')
    if not isinstance(metrics, dict):
        raise BadRequest('metrics must be an object.')

    update_heartbeat(
        uuid=uuid,
        metrics=json.dumps(metrics),
        rssi=metrics.get('rssi'),
        wifi_ssid=metrics.get('wifi_ssid'),
        geofence_state=metrics.get('geofence_state'),
    )

    finalize_attendance_records(
        stale_after_seconds=current_app.config.get('HEARTBEAT_STALE_SECONDS', 120),
        required_minutes=current_app.config.get('SESSION_REQUIRED_MINUTES', 45),
    )

    return jsonify(status='acknowledged', processed_at=datetime.now(timezone.utc).isoformat())


@api_bp.get('/api/students')
def students():
    _require_token()
    rows = list_students()
    return jsonify(students=rows)
EOF

cat <<'EOF' > app/dashboard.py
"""Teacher-facing dashboard blueprint."""
from __future__ import annotations

from datetime import datetime

from flask import Blueprint, redirect, render_template, url_for

from .database import get_system_state, list_students


dashboard_bp = Blueprint('dashboard', __name__)


@dashboard_bp.route('/')
def index():
    return redirect(url_for('dashboard.view_dashboard'))


@dashboard_bp.route('/dashboard')
def view_dashboard():
    students = list_students()
    headcount = int(get_system_state('last_camera_headcount') or 0)
    last_capture = get_system_state('last_camera_capture_ts')
    camera_error = get_system_state('camera_last_error')

    summary = {
        'connected': sum(1 for row in students if row['status'] == 'CONNECTED'),
        'proxy_risk': sum(1 for row in students if row['status'] == 'PROXY_RISK'),
        'disconnected': sum(1 for row in students if row['status'] == 'DISCONNECTED'),
        'present': sum(1 for row in students if row['attendance_final'] == 'PRESENT'),
        'absent': sum(1 for row in students if row['attendance_final'] == 'ABSENT'),
    }

    return render_template(
        'dashboard.html',
        students=students,
        headcount=headcount,
        last_capture=datetime.fromisoformat(last_capture) if last_capture else None,
        camera_error=camera_error,
        summary=summary,
    )
EOF

cat <<'EOF' > app/database.py
"""SQLite helpers for attendance persistence."""
from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

from flask import current_app, g


def init_app_database(app) -> None:
    db_path = Path(app.config['DATABASE_PATH'])
    db_path.parent.mkdir(parents=True, exist_ok=True)

    def get_db() -> sqlite3.Connection:
        if 'db_conn' not in g:
            g.db_conn = sqlite3.connect(db_path, detect_types=sqlite3.PARSE_DECLTYPES, check_same_thread=False)
            g.db_conn.row_factory = sqlite3.Row
        return g.db_conn

    @app.teardown_appcontext
    def close_db(_exception) -> None:
        db_conn = g.pop('db_conn', None)
        if db_conn is not None:
            db_conn.close()

    app.get_db = get_db  # type: ignore[attr-defined]


def _db() -> sqlite3.Connection:
    return current_app.get_db()  # type: ignore[attr-defined]


def register_student(uuid: str, name: str, roll_no: str, year: str, department: str, section: str) -> None:
    with closing(_db()) as conn:
        conn.execute(
            '''
            INSERT INTO students (uuid, name, roll_no, year, department, section, status)
            VALUES (?, ?, ?, ?, ?, ?, 'DISCONNECTED')
            ON CONFLICT(uuid) DO UPDATE SET
              name=excluded.name,
              roll_no=excluded.roll_no,
              year=excluded.year,
              department=excluded.department,
              section=excluded.section
            ''',
            (uuid, name, roll_no, year, department, section),
        )
        conn.commit()


def update_heartbeat(uuid: str, metrics: str, rssi: Optional[int], wifi_ssid: Optional[str], geofence_state: Optional[str]) -> None:
    now = datetime.now(timezone.utc)
    with closing(_db()) as conn:
        conn.execute(
            '''
            UPDATE students
            SET status='CONNECTED',
                last_seen=?,
                last_rssi=?,
                wifi_ssid=?,
                geofence_state=?,
                last_metrics=?
            WHERE uuid=?
            ''',
            (now.isoformat(), rssi, wifi_ssid, geofence_state, metrics, uuid),
        )
        conn.commit()


def list_students() -> List[Dict[str, Any]]:
    with closing(_db()) as conn:
        cursor = conn.execute(
            '''
            SELECT uuid, name, roll_no, year, department, section, status, last_seen,
                   last_rssi, wifi_ssid, geofence_state, last_metrics, attendance_final
            FROM students
            ORDER BY name
            ''',
        )
        rows = [dict(row) for row in cursor.fetchall()]
        for row in rows:
            if isinstance(row.get('last_metrics'), str):
                try:
                    row['last_metrics'] = json.loads(row['last_metrics'])
                except json.JSONDecodeError:
                    pass
        return rows


def get_system_state(key: str) -> Optional[str]:
    with closing(_db()) as conn:
        cursor = conn.execute('SELECT value FROM system_state WHERE key=?', (key,))
        result = cursor.fetchone()
        return result['value'] if result else None


def set_system_state(key: str, value: str) -> None:
    with closing(_db()) as conn:
        conn.execute(
            '''
            INSERT INTO system_state (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=CURRENT_TIMESTAMP
            ''',
            (key, value),
        )
        conn.commit()


def get_connected_students() -> List[Dict[str, Any]]:
    with closing(_db()) as conn:
        cursor = conn.execute('SELECT * FROM students WHERE status = "CONNECTED"')
        return [dict(row) for row in cursor.fetchall()]


def mark_status(uuids: Iterable[str], status: str) -> None:
    uuids = list(uuids)
    if not uuids:
        return
    with closing(_db()) as conn:
        conn.executemany('UPDATE students SET status=? WHERE uuid=?', [(status, uuid) for uuid in uuids])
        conn.commit()


def finalize_attendance_records(stale_after_seconds: int, required_minutes: int) -> None:
    now = datetime.now(timezone.utc)
    stale_cutoff = now - timedelta(seconds=stale_after_seconds)

    with closing(_db()) as conn:
        conn.execute(
            '''
            UPDATE students
            SET status='DISCONNECTED'
            WHERE status='CONNECTED' AND (last_seen IS NULL OR last_seen < ?)
            ''',
            (stale_cutoff.isoformat(),),
        )

        cursor = conn.execute('SELECT uuid, last_seen, attendance_final FROM students')
        updates: List[tuple[str, str]] = []
        for row in cursor.fetchall():
            last_seen = row['last_seen']
            attendance_final = row['attendance_final']
            if not last_seen:
                updates.append(('ABSENT', row['uuid']))
                continue
            last_seen_dt = datetime.fromisoformat(last_seen)
            if now - last_seen_dt >= timedelta(minutes=required_minutes):
                final_status = 'PRESENT'
            else:
                final_status = 'ABSENT'
            if attendance_final != final_status:
                updates.append((final_status, row['uuid']))

        if updates:
            conn.executemany('UPDATE students SET attendance_final=? WHERE uuid=?', updates)

        conn.commit()


def record_proxy_risk(uuids: Iterable[str]) -> None:
    mark_status(uuids, 'PROXY_RISK')
EOF

cat <<'EOF' > app/ble.py
"""Bluetooth Low Energy beacon broadcasting."""
from __future__ import annotations

import threading
import time

try:
    from bluetooth.ble import BeaconService
except ImportError:  # pragma: no cover - handled gracefully at runtime
    BeaconService = None

_ble_thread = None


def start_beacon(config) -> None:
    global _ble_thread
    if BeaconService is None:
        return
    if _ble_thread and _ble_thread.is_alive():
        return

    uuid = config.get('BLE_BEACON_UUID')
    major = int(config.get('BLE_MAJOR', 1))
    minor = int(config.get('BLE_MINOR', 1))
    tx_power = int(config.get('BLE_TX_POWER', -59))

    def _broadcast() -> None:
        service = BeaconService()
        service.start_advertising(uuid, major, minor, tx_power)
        try:
            while True:
                time.sleep(30)
        finally:
            service.stop_advertising()

    _ble_thread = threading.Thread(target=_broadcast, name='BleBeaconThread', daemon=True)
    _ble_thread.start()
EOF

cat <<'EOF' > app/camera.py
"""Camera-powered headcount using OpenCV."""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import cv2

from .database import record_proxy_risk, set_system_state


def capture_headcount(haarcascade_path: Path) -> int:
    classifier = cv2.CascadeClassifier(str(haarcascade_path))
    capture = cv2.VideoCapture(0)
    if not capture.isOpened():
        raise RuntimeError('Unable to access camera.')

    success, frame = capture.read()
    capture.release()
    if not success:
        raise RuntimeError('Failed to capture frame from camera.')

    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    faces = classifier.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(50, 50))
    return len(faces)


def evaluate_headcount(config, connected_students: Iterable[dict]) -> None:
    cascade_path = Path(config['HAAR_PATH'])
    count = capture_headcount(cascade_path)
    set_system_state('last_camera_headcount', str(count))
    set_system_state('last_camera_capture_ts', datetime.now(timezone.utc).isoformat())

    connected_students = list(connected_students)
    if count < len(connected_students):
        record_proxy_risk(student['uuid'] for student in connected_students)
EOF

cat <<'EOF' > app/scheduler.py
"""Background schedulers for camera checks and Firestore sync."""
from __future__ import annotations

import threading
import time

import schedule

from . import camera
from .database import (
    finalize_attendance_records,
    get_connected_students,
    set_system_state,
)
from .sync import push_attendance_snapshot


def _camera_job(app) -> None:
    with app.app_context():
        try:
            connected = get_connected_students()
            camera.evaluate_headcount({'HAAR_PATH': app.config.get('HAAR_PATH')}, connected)
        except Exception as exc:  # pragma: no cover
            set_system_state('camera_last_error', str(exc))


def _sync_job(app) -> None:
    with app.app_context():
        finalize_attendance_records(
            stale_after_seconds=app.config.get('HEARTBEAT_STALE_SECONDS', 120),
            required_minutes=app.config.get('SESSION_REQUIRED_MINUTES', 45),
        )
        push_attendance_snapshot()


def start_background_tasks(app) -> None:
    if not app.config.get('HAAR_PATH'):
        app.config['HAAR_PATH'] = f"{app.root_path}/../haars/haarcascade_frontalface_default.xml"

    schedule.every(app.config.get('CAMERA_INTERVAL_MINUTES', 10)).minutes.do(_camera_job, app)
    schedule.every(app.config.get('SYNC_INTERVAL_MINUTES', 15)).minutes.do(_sync_job, app)

    def _runner() -> None:
        while True:
            schedule.run_pending()
            time.sleep(1)

    threading.Thread(target=_runner, name='SchedulerThread', daemon=True).start()
EOF

cat <<'EOF' > app/sync.py
"""Firebase synchronization helpers."""
from __future__ import annotations

import os
from datetime import datetime, timezone

import firebase_admin
from firebase_admin import credentials, firestore
from flask import current_app

from .database import list_students

_firebase_app = None
_firestore_client = None


def _ensure_firestore():
        global _firebase_app, _firestore_client
        if _firestore_client is not None:
                return _firestore_client

        credentials_path = current_app.config.get('FIREBASE_CREDENTIALS')
        if not credentials_path:
                return None

        if not os.path.exists(credentials_path):
                raise FileNotFoundError(f'Firebase credentials not found: {credentials_path}')

        cred = credentials.Certificate(credentials_path)
        if _firebase_app is None:
                _firebase_app = firebase_admin.initialize_app(cred)

        _firestore_client = firestore.client(app=_firebase_app)
        return _firestore_client


def push_attendance_snapshot() -> None:
        client = _ensure_firestore()
        if client is None:
                return

        collection_name = current_app.config.get('FIREBASE_COLLECTION', 'attendance_sessions')
        payload = {
                'captured_at': datetime.now(timezone.utc).isoformat(),
                'students': list_students(),
                'pi_id': os.uname().nodename,
        }
        client.collection(collection_name).add(payload)
EOF

cat <<'EOF' > run.py
from app import create_app

app = create_app()
EOF

cat <<'EOF' > gunicorn_config.py
bind = '0.0.0.0:5000'
workers = 3
timeout = 60
EOF

log 'Creating teacher dashboard template'
cat <<'EOF' > templates/dashboard.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>ClassPulse Attendance Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f5f6fa; margin: 0; padding: 0; }
        header { background: #303f9f; color: #fff; padding: 16px; }
        main { padding: 24px; }
        table { width: 100%; border-collapse: collapse; margin-top: 16px; }
        th, td { border: 1px solid #d1d5db; padding: 8px; text-align: left; }
        th { background: #e8eaf6; }
        .summary { display: flex; gap: 16px; flex-wrap: wrap; margin-top: 16px; }
        .summary div { background: #fff; border-radius: 8px; padding: 12px 16px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .status-CONNECTED { color: #1b5e20; font-weight: bold; }
        .status-DISCONNECTED { color: #b71c1c; font-weight: bold; }
        .status-PROXY_RISK { color: #e65100; font-weight: bold; }
    </style>
</head>
<body>
    <header>
        <h1>ClassPulse Attendance Dashboard</h1>
        <p>Live student presence vs camera headcount</p>
    </header>
    <main>
        <section class="summary">
            <div><strong>Connected:</strong> {{ summary.connected }}</div>
            <div><strong>Proxy Risk:</strong> {{ summary.proxy_risk }}</div>
            <div><strong>Disconnected:</strong> {{ summary.disconnected }}</div>
            <div><strong>Camera Headcount:</strong> {{ headcount }}</div>
            <div><strong>Present (final):</strong> {{ summary.present }}</div>
            <div><strong>Absent (final):</strong> {{ summary.absent }}</div>
        </section>

        {% if last_capture %}
            <p>Last camera capture: {{ last_capture.strftime('%Y-%m-%d %H:%M:%S') }}</p>
        {% endif %}

        {% if camera_error %}
            <p style="color:#b71c1c;">Camera error: {{ camera_error }}</p>
        {% endif %}

        <table>
            <thead>
            <tr>
                <th>Name</th>
                <th>Roll No</th>
                <th>Status</th>
                <th>Last Seen</th>
                <th>RSSI</th>
                <th>Wi-Fi</th>
                <th>Geofence</th>
                <th>Final</th>
            </tr>
            </thead>
            <tbody>
            {% for student in students %}
                <tr>
                    <td>{{ student.name }}</td>
                    <td>{{ student.roll_no }}</td>
                    <td class="status-{{ student.status }}">{{ student.status }}</td>
                    <td>{{ student.last_seen }}</td>
                    <td>{{ student.last_rssi if student.last_rssi is not none else '—' }}</td>
                    <td>{{ student.wifi_ssid or '—' }}</td>
                    <td>{{ student.geofence_state or '—' }}</td>
                    <td>{{ student.attendance_final or 'PENDING' }}</td>
                </tr>
            {% endfor %}
            </tbody>
        </table>
    </main>
</body>
</html>
EOF

log 'Ensuring instance config scaffold exists'
if [ ! -f instance/config.py ]; then
    cat <<'EOF' > instance/config.py
"""Instance-specific configuration for ClassPulse server."""
import os

REGISTRATION_API_TOKEN = os.getenv('CLASSPULSE_REGISTRATION_TOKEN', 'HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM')
BLE_BEACON_UUID = os.getenv('CLASSPULSE_BLE_UUID', 'aea91077-00fb-4345-b748-bd35c153c3a6')
BLE_MAJOR = int(os.getenv('CLASSPULSE_BLE_MAJOR', '1'))
BLE_MINOR = int(os.getenv('CLASSPULSE_BLE_MINOR', '1'))
BLE_TX_POWER = int(os.getenv('CLASSPULSE_BLE_TX_POWER', '-59'))
CAMERA_INTERVAL_MINUTES = int(os.getenv('CLASSPULSE_CAMERA_INTERVAL', '10'))
SYNC_INTERVAL_MINUTES = int(os.getenv('CLASSPULSE_SYNC_INTERVAL', '15'))
SESSION_REQUIRED_MINUTES = int(os.getenv('CLASSPULSE_SESSION_REQUIRED', '45'))
HEARTBEAT_STALE_SECONDS = int(os.getenv('CLASSPULSE_HEARTBEAT_STALE', '120'))
FIREBASE_CREDENTIALS = os.getenv('CLASSPULSE_FIREBASE_CREDENTIALS', '')
FIREBASE_COLLECTION = os.getenv('CLASSPULSE_FIREBASE_COLLECTION', 'attendance_sessions')
HAAR_PATH = os.getenv('CLASSPULSE_HAAR_PATH', os.path.join(os.path.dirname(__file__), '../haars/haarcascade_frontalface_default.xml'))
EOF
fi

log 'Creating production .env file with secure credentials'
cat <<'EOF' > .env
CLASSPULSE_REGISTRATION_TOKEN=HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM
CLASSPULSE_BLE_UUID=aea91077-00fb-4345-b748-bd35c153c3a6
CLASSPULSE_FIREBASE_CREDENTIALS=
# Add Firebase credentials path if using Firestore sync: /home/pi/classpulse/server/service_account.json
EOF

log 'Creating env template (.env.example) for reference'
cat <<'EOF' > .env.example
CLASSPULSE_REGISTRATION_TOKEN=HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM
CLASSPULSE_BLE_UUID=aea91077-00fb-4345-b748-bd35c153c3a6
CLASSPULSE_FIREBASE_CREDENTIALS=/home/pi/classpulse/server/service_account.json
CLASSPULSE_FIREBASE_COLLECTION=attendance_sessions
EOF

log 'Bootstrap complete. Activate with: source ${PROJECT_ROOT}/.venv/bin/activate'