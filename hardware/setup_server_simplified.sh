#!/usr/bin/env bash
# ClassPulse Raspberry Pi Server - Simplified Setup Script
# WiFi-based detection with JSON storage (no camera, no cloud dependencies)

set -euo pipefail

PROJECT_ROOT="${HOME}/classpulse/server"
PYTHON_BIN="python3"
APT_PACKAGES=(
  python3-venv
  curl
  git
  hostapd
  dnsmasq
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

log 'Verifying base dependencies (python3, pip3, systemctl)'
require_cmd "$PYTHON_BIN"
require_cmd pip3
require_cmd systemctl

log 'Updating apt packages and installing OS-level prerequisites'
sudo apt-get update
sudo apt-get install -y "${APT_PACKAGES[@]}"

log "Creating project directory structure under ${PROJECT_ROOT}"
mkdir -p "${PROJECT_ROOT}/app"
mkdir -p "${PROJECT_ROOT}/instance"
mkdir -p "${PROJECT_ROOT}/data"
mkdir -p "${PROJECT_ROOT}/logs"
mkdir -p "${PROJECT_ROOT}/templates"

log 'Setting up Python virtual environment'
cd "${PROJECT_ROOT}"
$PYTHON_BIN -m venv .venv
source .venv/bin/activate

log 'Upgrading pip and wheel'
pip install --upgrade pip wheel

log 'Writing requirements.txt (lightweight, no cloud dependencies)'
cat > requirements.txt << 'EOF'
Flask==3.0.3
gunicorn==22.0.0
python-dotenv==1.0.1
requests==2.32.3
flask-limiter==3.5.0
schedule==1.2.2
itsdangerous==2.2.0
netifaces==0.11.0
opencv-python-headless==4.10.0.84
Pillow==10.4.0
EOF

log 'Installing Python dependencies'
pip install -r requirements.txt

log 'Creating initial JSON data structure'
cat > data/students.json << 'EOF'
{
  "students": [],
  "system_state": {
    "last_sync": null,
    "pi_location": {
      "latitude": null,
      "longitude": null,
      "set_manually": false
        },
        "wifi_ssid": null,
        "connected_devices": [],
        "camera_headcount": 0,
        "last_camera_check": null,
        "camera_error": null,
        "attendance_threshold_percent": 75
  }
}
EOF

log 'Creating Flask application with WiFi-based detection'

cat > app/__init__.py << 'EOF'
"""Flask application factory for ClassPulse Pi server - WiFi detection mode."""
from __future__ import annotations

import os
from flask import Flask

from .api import api_bp
from .dashboard import dashboard_bp
from .data_store import init_data_store
from .scheduler import start_background_tasks


def create_app() -> Flask:
    app = Flask(__name__, instance_relative_config=True)

    # Configuration - WiFi detection mode
    app.config.from_mapping(
        DATA_FILE='../data/students.json',
        REGISTRATION_API_TOKEN='HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM',
        SESSION_REQUIRED_MINUTES=45,
        ATTENDANCE_THRESHOLD_PERCENT=75,  # Dynamic attendance threshold (% of session time)
        HEARTBEAT_STALE_SECONDS=120,
        WIFI_DETECTION_INTERVAL=30,  # Check WiFi every 30 seconds
        GEOFENCE_RADIUS_METERS=50,
        PI_WIFI_SSID='',  # Will be auto-detected
        # Optional IP Camera settings
        IP_CAMERA_ENABLED=False,
        IP_CAMERA_URL='',  # e.g., 'http://192.168.0.100:8080/video'
        CAMERA_CHECK_INTERVAL=10,  # Check every 10 minutes
    )

    os.makedirs(app.instance_path, exist_ok=True)
    app.config.from_pyfile('config.py', silent=True)
    
    # Initialize data store
    init_data_store(app)

    app.register_blueprint(api_bp)
    app.register_blueprint(dashboard_bp)

    # Start background monitoring
    with app.app_context():
        start_background_tasks(app)

    return app
EOF

cat > app/api.py << 'EOF'
"""REST API for student registration and heartbeat."""
from __future__ import annotations

from datetime import datetime, timezone
from flask import Blueprint, current_app, jsonify, request
from werkzeug.exceptions import BadRequest, Unauthorized

from .data_store import (
    register_student,
    update_heartbeat,
    list_students,
    finalize_attendance,
    get_student_by_uuid,
)

api_bp = Blueprint('api', __name__)


def _require_token() -> None:
    expected = current_app.config.get('REGISTRATION_API_TOKEN')
    provided = request.headers.get('X-Auth-Token')
    if not expected or provided != expected:
        raise Unauthorized('Invalid or missing X-Auth-Token header.')


@api_bp.get('/healthz')
def health_check():
    """Health check endpoint."""
    return jsonify(status='ok', time=datetime.utcnow().isoformat()), 200


@api_bp.post('/api/register')
def register():
    """Register a new student or update existing."""
    _require_token()
    payload = request.get_json(silent=True)
    
    print(f"📥 Registration request from {request.remote_addr}")
    print(f"📦 Payload: {payload}")
    
    if not isinstance(payload, dict):
        raise BadRequest('Expected JSON payload.')

    required_fields = {'uuid', 'name', 'rollNumber', 'year', 'department', 'section'}
    missing = required_fields - payload.keys()
    if missing:
        print(f"❌ Missing fields: {missing}")
        raise BadRequest(f'Missing fields: {", ".join(sorted(missing))}')

    # Get device info for WiFi detection
    device_info = {
        'mac_address': request.headers.get('X-Device-MAC', ''),
        'ip_address': request.remote_addr,
        'wifi_ssid': payload.get('wifiSSID', ''),
        'wifi_canonical': payload.get('wifiSSIDCanonical', ''),
    }

    print(f"💾 Registering student: {payload['name']} (UUID: {payload['uuid']})")
    print(f"📡 Device info: {device_info}")

    register_student(
        uuid=payload['uuid'],
        name=payload['name'],
        roll_no=payload['rollNumber'],
        year=payload['year'],
        department=payload['department'],
        section=payload['section'],
        device_info=device_info,
    )

    print(f"✅ Student registered successfully!")
    return jsonify(status='registered', uuid=payload['uuid']), 201


@api_bp.post('/api/heartbeat')
def heartbeat():
    """Receive heartbeat from student app."""
    _require_token()
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        raise BadRequest('Expected JSON payload.')

    uuid = payload.get('uuid')
    metrics = payload.get('metrics', {})
    profile_payload = payload.get('profile') if isinstance(payload, dict) else None
    
    print(f"💓 Heartbeat from UUID: {uuid}")
    
    if not uuid:
        raise BadRequest('Missing uuid field.')
    if not isinstance(metrics, dict):
        raise BadRequest('metrics must be an object.')

    # Attempt to upsert student details if profile payload present
    if isinstance(profile_payload, dict):
        required_profile_fields = {'uuid', 'name', 'rollNumber', 'year', 'department', 'section'}
        missing_profile_fields = required_profile_fields - set(profile_payload.keys())
        if missing_profile_fields:
            print(f"⚠️ Profile payload missing fields: {missing_profile_fields}. Skipping auto-upsert.")
        else:
            print(f"🧾 Heartbeat included profile for {profile_payload.get('name')} - ensuring student record exists")
            profile_device_info = {
                'mac_address': request.headers.get('X-Device-MAC', ''),
                'ip_address': request.remote_addr,
                'wifi_ssid': profile_payload.get('wifiSSID') or payload.get('wifiSSID') or metrics.get('wifi_ssid', ''),
                'wifi_canonical': profile_payload.get('wifiSSIDCanonical') or payload.get('wifiSSIDCanonical') or metrics.get('wifi_canonical', ''),
            }
            register_student(
                uuid=profile_payload['uuid'],
                name=profile_payload['name'],
                roll_no=profile_payload['rollNumber'],
                year=profile_payload['year'],
                department=profile_payload['department'],
                section=profile_payload['section'],
                device_info=profile_device_info,
            )

    # Check if student exists after potential upsert
    student = get_student_by_uuid(uuid)
    if not student:
        print(f"❌ UUID {uuid} not found in database even after profile upsert!")
        print(f"📋 Instructing app to register...")
        return jsonify({
            'error': 'Student not found',
            'message': 'UUID not registered on this Pi',
            'uuid': uuid,
            'should_register': True
        }), 404

    print(f"✅ Student found: {student.get('name')} ({student.get('roll_no')})")

    # Add device detection info
    metrics['ip_address'] = request.remote_addr
    metrics['mac_address'] = request.headers.get('X-Device-MAC', '')
    if 'wifi_canonical' not in metrics or not metrics['wifi_canonical']:
        metrics['wifi_canonical'] = payload.get('wifiSSIDCanonical', '')
    if 'wifi_ssid' not in metrics or not metrics['wifi_ssid']:
        metrics['wifi_ssid'] = payload.get('wifiSSID', '')

    # Determine expected WiFi identifier for logging
    expected_canonical = metrics.get('wifi_expected_canonical')
    if not expected_canonical:
        expected_canonical = student.get('device_info', {}).get('wifi_canonical')
        if expected_canonical:
            metrics['wifi_expected_canonical'] = expected_canonical
    expected_ssid = metrics.get('wifi_expected')
    if not expected_ssid:
        expected_ssid = student.get('device_info', {}).get('wifi_ssid')
        if expected_ssid:
            metrics['wifi_expected'] = expected_ssid

    actual_canonical = metrics.get('wifi_canonical')
    print(f"📶 WiFi check → expected: {expected_canonical or 'unknown'} | actual: {actual_canonical or 'unknown'}")
    if expected_canonical and actual_canonical and expected_canonical != actual_canonical:
        print(f"⚠️ WiFi mismatch for {student.get('name')} - expected {expected_canonical}, got {actual_canonical}")
    
    update_heartbeat(uuid=uuid, metrics=metrics)
    
    print(f"💾 Heartbeat saved for {student.get('name')}")
    
    # Finalize attendance based on time thresholds
    finalize_attendance(
        stale_seconds=current_app.config.get('HEARTBEAT_STALE_SECONDS', 120),
        required_minutes=current_app.config.get('SESSION_REQUIRED_MINUTES', 45),
        threshold_percent=current_app.config.get('ATTENDANCE_THRESHOLD_PERCENT', 75),
    )

    return jsonify(
        status='acknowledged',
        processed_at=datetime.now(timezone.utc).isoformat()
    )


@api_bp.get('/api/students')
def students():
    """List all registered students."""
    _require_token()
    return jsonify(students=list_students())


@api_bp.get('/api/debug/count')
def debug_count():
    """Debug endpoint - get student count (no auth required)."""
    students_list = list_students()
    return jsonify({
        'total_students': len(students_list),
        'connected': sum(1 for s in students_list if s['status'] == 'CONNECTED'),
        'disconnected': sum(1 for s in students_list if s['status'] == 'DISCONNECTED'),
        'students': [{'name': s['name'], 'roll_no': s['roll_no'], 'uuid': s['uuid'][:8]} for s in students_list]
    })


@api_bp.get('/api/pi-info')
def pi_info():
    """Get Pi location and WiFi info for student app configuration."""
    from .network import get_pi_location, get_wifi_ssid
    
    location = get_pi_location()
    wifi = get_wifi_ssid()
    
    return jsonify(
        location=location,
        wifi_ssid=wifi,
        geofence_radius=current_app.config.get('GEOFENCE_RADIUS_METERS', 50)
    )
EOF

cat > app/data_store.py << 'EOF'
"""JSON-based data storage for students and system state."""
from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import Lock
from typing import Any, Dict, List, Optional

from flask import current_app

_data_lock = Lock()
_data_file_path: Optional[Path] = None


def init_data_store(app) -> None:
    """Initialize the JSON data store."""
    global _data_file_path
    data_file = app.config.get('DATA_FILE', '../data/students.json')
    _data_file_path = Path(app.root_path) / data_file
    _data_file_path.parent.mkdir(parents=True, exist_ok=True)
    
    # Create initial file if it doesn't exist
    if not _data_file_path.exists():
        _write_data({
            'students': [],
            'system_state': {
                'last_sync': None,
                'pi_location': {'latitude': None, 'longitude': None},
                'wifi_ssid': None,
                'connected_devices': []
                'camera_headcount': 0,
                'last_camera_check': None,
                'camera_error': None,
                'attendance_threshold_percent': app.config.get('ATTENDANCE_THRESHOLD_PERCENT', 75),
            }
        })

    # Ensure required keys exist (for upgrades)
    data = _read_data()
    system_state = data.setdefault('system_state', {})
    if 'attendance_threshold_percent' not in system_state:
        system_state['attendance_threshold_percent'] = app.config.get('ATTENDANCE_THRESHOLD_PERCENT', 75)
        _write_data(data)


def _read_data() -> Dict[str, Any]:
    """Read data from JSON file."""
    with _data_lock:
        if not _data_file_path.exists():
            return {
                'students': [],
                'system_state': {
                    'last_sync': None,
                    'pi_location': {'latitude': None, 'longitude': None},
                    'wifi_ssid': None,
                    'connected_devices': [],
                    'camera_headcount': 0,
                    'last_camera_check': None,
                    'camera_error': None,
                    'attendance_threshold_percent': 75,
                }
            }
        with open(_data_file_path, 'r') as f:
            return json.load(f)


def _write_data(data: Dict[str, Any]) -> None:
    """Write data to JSON file."""
    with _data_lock:
        with open(_data_file_path, 'w') as f:
            json.dump(data, f, indent=2)


def register_student(
    uuid: str,
    name: str,
    roll_no: str,
    year: str,
    department: str,
    section: str,
    device_info: Dict[str, str]
) -> None:
    """Register a new student or update existing."""
    print(f"🔍 Loading student database...")
    data = _read_data()
    print(f"📊 Current database has {len(data['students'])} students")
    
    # Find existing student
    student = None
    for s in data['students']:
        if s['uuid'] == uuid:
            student = s
            break
    
    if student:
        # Update existing
        print(f"🔄 Updating existing student: {name}")
        student.update({
            'name': name,
            'roll_no': roll_no,
            'year': year,
            'department': department,
            'section': section,
            'device_info': device_info,
        })
    else:
        # Add new
        print(f"➕ Adding new student: {name}")
        new_student = {
            'uuid': uuid,
            'name': name,
            'roll_no': roll_no,
            'year': year,
            'department': department,
            'section': section,
            'device_info': device_info,
            'status': 'DISCONNECTED',
            'last_seen': None,
            'metrics': {},
            'attendance_final': None,
            'session_start': None,
            'total_time_minutes': 0,
        }
        data['students'].append(new_student)
        print(f"📝 Student object: {new_student}")
    
    print(f"💾 Writing to disk at: {_data_file_path}")
    _write_data(data)
    print(f"✅ Data saved! Total students now: {len(data['students'])}")


def update_heartbeat(uuid: str, metrics: Dict[str, Any]) -> None:
    """Update student heartbeat and connection status."""
    data = _read_data()
    now = datetime.now(timezone.utc).isoformat()
    
    for student in data['students']:
        if student['uuid'] == uuid:
            previous_status = student.get('status')
            student['status'] = 'CONNECTED'
            student['last_seen'] = now
            student['metrics'] = metrics

            device_info = student.setdefault('device_info', {})
            if metrics.get('wifi_ssid'):
                device_info['wifi_ssid'] = metrics['wifi_ssid']
            if metrics.get('wifi_canonical'):
                device_info['wifi_canonical'] = metrics['wifi_canonical']
            if metrics.get('ip_address'):
                device_info['ip_address'] = metrics['ip_address']
            if metrics.get('mac_address'):
                device_info['mac_address'] = metrics['mac_address']
            
            # Track session start time
            if previous_status != 'CONNECTED':
                student['session_start'] = now
            
            # Calculate cumulative time
            if student.get('session_start'):
                start = datetime.fromisoformat(student['session_start'])
                elapsed = (datetime.now(timezone.utc) - start).total_seconds() / 60
                student['total_time_minutes'] = elapsed
            
            break
    
    _write_data(data)


def list_students() -> List[Dict[str, Any]]:
    """Get list of all students."""
    data = _read_data()
    return data['students']


def get_student_by_uuid(uuid: str) -> Optional[Dict[str, Any]]:
    """Get student by UUID."""
    data = _read_data()
    for student in data['students']:
        if student['uuid'] == uuid:
            return student
    return None


def finalize_attendance(stale_seconds: int, required_minutes: int, threshold_percent: int = 75) -> None:
    """
    Finalize attendance based on connection time and dynamic threshold.
    
    Args:
        stale_seconds: Seconds before marking student as disconnected
        required_minutes: Total session duration in minutes
        threshold_percent: Percentage of session time required for PRESENT (default 75%)
    """
    data = _read_data()
    now = datetime.now(timezone.utc)
    stale_cutoff = now - timedelta(seconds=stale_seconds)
    
    # Calculate dynamic threshold (percentage of required session time)
    threshold_minutes = (required_minutes * threshold_percent) / 100
    
    print(f"🎯 Attendance threshold: {threshold_minutes:.1f} min ({threshold_percent}% of {required_minutes} min session)")
    
    for student in data['students']:
        last_seen = student.get('last_seen')
        
        # Mark as disconnected if stale
        if last_seen:
            last_seen_dt = datetime.fromisoformat(last_seen)
            if last_seen_dt < stale_cutoff:
                student['status'] = 'DISCONNECTED'
        
        # Determine final attendance using dynamic threshold
        total_time = student.get('total_time_minutes', 0)
        if total_time >= threshold_minutes:
            student['attendance_final'] = 'PRESENT'
            print(f"✅ {student['name']}: PRESENT ({total_time:.1f} min >= {threshold_minutes:.1f} min)")
        else:
            student['attendance_final'] = 'ABSENT'
            print(f"❌ {student['name']}: ABSENT ({total_time:.1f} min < {threshold_minutes:.1f} min)")
    
    _write_data(data)


def get_system_state(key: str) -> Any:
    """Get system state value."""
    data = _read_data()
    return data['system_state'].get(key)


def set_system_state(key: str, value: Any) -> None:
    """Set system state value."""
    data = _read_data()
    data['system_state'][key] = value
    _write_data(data)


def mark_proxy_risk() -> None:
    """Mark all connected students as potential proxy risk."""
    data = _read_data()
    for student in data['students']:
        if student['status'] == 'CONNECTED':
            student['proxy_risk'] = True
    _write_data(data)
EOF

cat > app/network.py << 'EOF'
"""Network utilities for WiFi detection and Pi location."""
from __future__ import annotations

import subprocess
from typing import Dict, Optional

import netifaces


def get_wifi_ssid() -> Optional[str]:
    """Get the WiFi SSID that Pi is connected to."""
    try:
        # Try iwgetid command
        result = subprocess.run(
            ['iwgetid', '-r'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    
    return None


def get_pi_ip() -> Optional[str]:
    """Get Pi's IP address."""
    try:
        # Get all interfaces
        for interface in netifaces.interfaces():
            if interface.startswith('wlan') or interface.startswith('eth'):
                addrs = netifaces.ifaddresses(interface)
                if netifaces.AF_INET in addrs:
                    return addrs[netifaces.AF_INET][0]['addr']
    except Exception:
        pass
    
    return None


def get_connected_devices() -> list:
    """Get list of devices connected to the same network."""
    try:
        # Use arp-scan or nmap to detect devices
        result = subprocess.run(
            ['arp', '-a'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        devices = []
        for line in result.stdout.split('\n'):
            if '(' in line and ')' in line:
                # Parse IP and MAC from arp output
                parts = line.split()
                if len(parts) >= 4:
                    ip = parts[1].strip('()')
                    mac = parts[3] if len(parts) > 3 else ''
                    devices.append({'ip': ip, 'mac': mac})
        
        return devices
    except Exception:
        return []


def get_pi_location() -> Dict[str, Optional[float]]:
    """Get Pi's GPS coordinates (manual or auto-detected)."""
    from .data_store import get_system_state
    
    location = get_system_state('pi_location')
    if location and location.get('latitude') and location.get('longitude'):
        return location
    
    # Default location if not set
    return {
        'latitude': None,
        'longitude': None,
        'set_manually': False
    }


def set_pi_location(latitude: float, longitude: float) -> None:
    """Manually set Pi's location."""
    from .data_store import set_system_state
    
    set_system_state('pi_location', {
        'latitude': latitude,
        'longitude': longitude,
        'set_manually': True
    })
EOF

cat > app/dashboard.py << 'EOF'
"""Teacher-facing dashboard."""
from __future__ import annotations

from flask import Blueprint, redirect, render_template, request, url_for, jsonify, current_app

from .data_store import list_students, set_system_state
from .network import get_wifi_ssid, get_pi_ip, get_pi_location, set_pi_location

dashboard_bp = Blueprint('dashboard', __name__)


@dashboard_bp.route('/')
def index():
    return redirect(url_for('dashboard.view_dashboard'))


@dashboard_bp.route('/dashboard')
def view_dashboard():
    """Main dashboard view."""
    students = list_students()
    pi_ip = get_pi_ip()
    wifi_ssid = get_wifi_ssid()
    location = get_pi_location()
    
    from .data_store import get_system_state
    camera_headcount = get_system_state('camera_headcount') or 0
    last_camera_check = get_system_state('last_camera_check')
    camera_error = get_system_state('camera_error')
    threshold_override = get_system_state('attendance_threshold_percent')
    threshold_value = threshold_override if isinstance(threshold_override, int) else current_app.config.get('ATTENDANCE_THRESHOLD_PERCENT', 75)
    current_app.config['ATTENDANCE_THRESHOLD_PERCENT'] = threshold_value
    
    summary = {
        'connected': sum(1 for s in students if s['status'] == 'CONNECTED'),
        'disconnected': sum(1 for s in students if s['status'] == 'DISCONNECTED'),
        'present': sum(1 for s in students if s.get('attendance_final') == 'PRESENT'),
        'absent': sum(1 for s in students if s.get('attendance_final') == 'ABSENT'),
        'total': len(students),
        'proxy_risk': sum(1 for s in students if s.get('proxy_risk', False)),
    }
    
    return render_template(
        'dashboard.html',
        students=students,
        summary=summary,
        pi_ip=pi_ip,
        wifi_ssid=wifi_ssid,
        location=location,
    threshold_percent=threshold_value,
        camera_enabled=current_app.config.get('IP_CAMERA_ENABLED'),
        camera_headcount=camera_headcount,
        last_camera_check=last_camera_check,
        camera_error=camera_error,
    )


@dashboard_bp.route('/api/set-location', methods=['POST'])
def set_location():
    """Set Pi's GPS location manually."""
    data = request.get_json()
    lat = data.get('latitude')
    lon = data.get('longitude')
    
    if lat is None or lon is None:
        return jsonify(error='Missing latitude or longitude'), 400
    
    try:
        set_pi_location(float(lat), float(lon))
        return jsonify(success=True)
    except ValueError:
        return jsonify(error='Invalid coordinates'), 400


@dashboard_bp.route('/api/set-threshold', methods=['POST'])
def set_threshold():
    """Update attendance threshold percentage dynamically."""
    data = request.get_json()
    threshold = data.get('threshold')
    
    if threshold is None:
        return jsonify(error='Missing threshold value'), 400
    
    try:
        threshold_value = int(threshold)
        if not 0 <= threshold_value <= 100:
            return jsonify(error='Threshold must be between 0 and 100'), 400
        
        # Update config in-memory (will persist until restart)
        from flask import current_app
        current_app.config['ATTENDANCE_THRESHOLD_PERCENT'] = threshold_value
        set_system_state('attendance_threshold_percent', threshold_value)
        
        return jsonify(
            success=True,
            threshold=threshold_value,
            message=f'Attendance threshold set to {threshold_value}%'
        )
    except ValueError:
        return jsonify(error='Invalid threshold value'), 400
EOF

cat > app/scheduler.py << 'EOF'
"""Background task scheduler for WiFi detection."""
from __future__ import annotations

import threading
import time

import schedule

from .data_store import set_system_state, finalize_attendance
from .network import get_wifi_ssid, get_connected_devices


def _wifi_detection_job(app) -> None:
    """Periodically check WiFi and connected devices."""
    with app.app_context():
        try:
            # Update WiFi SSID
            ssid = get_wifi_ssid()
            if ssid:
                set_system_state('wifi_ssid', ssid)
            
            # Update connected devices
            devices = get_connected_devices()
            set_system_state('connected_devices', devices)
            
            # Finalize attendance
            finalize_attendance(
                stale_seconds=app.config.get('HEARTBEAT_STALE_SECONDS', 120),
                required_minutes=app.config.get('SESSION_REQUIRED_MINUTES', 45),
                threshold_percent=app.config.get('ATTENDANCE_THRESHOLD_PERCENT', 75)
            )
        except Exception as e:
            print(f"WiFi detection error: {e}")


def _camera_check_job(app) -> None:
    """Periodically check IP camera for headcount (if enabled)."""
    with app.app_context():
        if not app.config.get('IP_CAMERA_ENABLED'):
            return
        
        try:
            from .camera import check_camera_headcount
            from .data_store import list_students
            
            students = list_students()
            connected_count = sum(1 for s in students if s['status'] == 'CONNECTED')
            
            headcount = check_camera_headcount(app.config.get('IP_CAMERA_URL'))
            
            if headcount is not None:
                set_system_state('camera_headcount', headcount)
                set_system_state('last_camera_check', time.time())
                set_system_state('camera_error', None)
                
                # Flag proxy risk if headcount < connected students
                if headcount < connected_count:
                    print(f"⚠️ Proxy risk detected: {connected_count} connected but only {headcount} faces detected")
                    from .data_store import mark_proxy_risk
                    mark_proxy_risk()
        except Exception as e:
            print(f"Camera check error: {e}")
            set_system_state('camera_error', str(e))


def start_background_tasks(app) -> None:
    """Start background monitoring tasks."""
    wifi_interval = app.config.get('WIFI_DETECTION_INTERVAL', 30)
    schedule.every(wifi_interval).seconds.do(_wifi_detection_job, app)
    
    # Schedule camera checks if enabled
    if app.config.get('IP_CAMERA_ENABLED'):
        camera_interval = app.config.get('CAMERA_CHECK_INTERVAL', 10)
        schedule.every(camera_interval).minutes.do(_camera_check_job, app)
    
    def _runner() -> None:
        while True:
            schedule.run_pending()
            time.sleep(1)
    
    threading.Thread(target=_runner, name='SchedulerThread', daemon=True).start()
EOF

cat > app/camera.py << 'EOF'
"""Optional IP Camera integration for headcount verification."""
from __future__ import annotations

import cv2
import numpy as np
from typing import Optional
import urllib.request


def check_camera_headcount(camera_url: str) -> Optional[int]:
    """
    Check IP camera for face count.
    
    Args:
        camera_url: URL of IP camera stream (e.g., http://192.168.0.100:8080/video)
    
    Returns:
        Number of faces detected, or None if error
    """
    if not camera_url:
        return None
    
    try:
        # Read image from IP camera
        img_resp = urllib.request.urlopen(camera_url, timeout=5)
        img_array = np.array(bytearray(img_resp.read()), dtype=np.uint8)
        img = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
        
        if img is None:
            return None
        
        # Convert to grayscale
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Load Haar cascade for face detection
        face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
        
        # Detect faces
        faces = face_cascade.detectMultiScale(
            gray,
            scaleFactor=1.1,
            minNeighbors=5,
            minSize=(30, 30)
        )
        
        return len(faces)
    
    except Exception as e:
        print(f"Camera error: {e}")
        return None
EOF

cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ClassPulse Dashboard - WiFi Detection Mode</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif; background: #f5f6fa; }
        header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: #fff; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        header h1 { font-size: 28px; margin-bottom: 8px; }
        header p { opacity: 0.9; font-size: 14px; }
        .container { max-width: 1400px; margin: 0 auto; padding: 24px; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 16px; margin-bottom: 24px; }
        .info-card { background: #fff; padding: 20px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); }
        .info-card h3 { font-size: 14px; color: #666; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px; }
        .info-card p { font-size: 24px; font-weight: 600; color: #333; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; margin-bottom: 24px; }
        .summary-card { background: #fff; padding: 20px; border-radius: 12px; text-align: center; box-shadow: 0 2px 8px rgba(0,0,0,0.05); }
        .summary-card .number { font-size: 36px; font-weight: 700; margin-bottom: 8px; }
        .summary-card .label { font-size: 14px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; }
        .summary-card.connected .number { color: #10b981; }
        .summary-card.disconnected .number { color: #ef4444; }
        .summary-card.present .number { color: #3b82f6; }
        .summary-card.absent .number { color: #f59e0b; }
        .table-container { background: #fff; border-radius: 12px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #e5e7eb; }
        th { background: #f9fafb; font-weight: 600; font-size: 13px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; }
        .status { padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600; display: inline-block; }
        .status-CONNECTED { background: #d1fae5; color: #065f46; }
        .status-DISCONNECTED { background: #fee2e2; color: #991b1b; }
        .attendance-PRESENT { color: #3b82f6; font-weight: 600; }
        .attendance-ABSENT { color: #f59e0b; font-weight: 600; }
        .location-setup { background: #fffbeb; border: 1px solid #fde68a; padding: 16px; border-radius: 8px; margin-bottom: 24px; }
        .location-setup h3 { color: #92400e; margin-bottom: 12px; }
        .location-form { display: flex; gap: 12px; align-items: end; flex-wrap: wrap; }
        .location-form input { padding: 8px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px; }
        .location-form button { background: #3b82f6; color: white; padding: 8px 20px; border: none; border-radius: 6px; cursor: pointer; font-weight: 600; }
        .location-form button:hover { background: #2563eb; }
        .location-editor { background: #fff; border: 1px solid #e5e7eb; padding: 16px; border-radius: 8px; margin-bottom: 24px; }
        .location-editor h3 { color: #333; margin-bottom: 12px; font-size: 16px; display: flex; align-items: center; gap: 8px; }
        .location-editor .current-location { background: #f0fdf4; border: 1px solid #bbf7d0; padding: 12px; border-radius: 6px; margin-bottom: 12px; }
        .location-editor .current-location p { font-size: 14px; color: #166534; margin: 4px 0; }
        .location-editor .edit-form { display: flex; gap: 12px; align-items: end; flex-wrap: wrap; }
        .location-editor .input-group { flex: 1; min-width: 150px; }
        .location-editor .input-group label { display: block; font-size: 12px; margin-bottom: 4px; color: #666; font-weight: 500; }
        .location-editor .input-group input { width: 100%; padding: 8px 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px; }
        .location-editor button { background: #3b82f6; color: white; padding: 8px 20px; border: none; border-radius: 6px; cursor: pointer; font-weight: 600; transition: background 0.2s; }
        .location-editor button:hover { background: #2563eb; }
        .location-editor .btn-get-location { background: #10b981; margin-left: 8px; }
        .location-editor .btn-get-location:hover { background: #059669; }
        .alert { padding: 12px 16px; border-radius: 6px; margin-bottom: 16px; font-size: 14px; }
        .alert-success { background: #d1fae5; border: 1px solid #6ee7b7; color: #065f46; }
        .alert-error { background: #fee2e2; border: 1px solid #fca5a5; color: #991b1b; }
        @media (max-width: 768px) {
            .info-grid, .summary { grid-template-columns: 1fr; }
            .location-editor .edit-form { flex-direction: column; }
            .location-editor .input-group { width: 100%; }
        }
    </style>
</head>
<body>
    <header>
        <h1>🎓 ClassPulse Attendance Dashboard</h1>
        <p>WiFi-Based Detection Mode</p>
    </header>
    
    <div class="container">
        <div id="alert-container"></div>
        
        <!-- Dynamic Location Editor - Always Visible -->
        <div class="location-editor">
            <h3>📍 Pi Location Management</h3>
            
            {% if location.latitude and location.longitude %}
            <div class="current-location">
                <p><strong>Current Location:</strong></p>
                <p>🌐 Latitude: <strong>{{ "%.6f"|format(location.latitude) }}</strong></p>
                <p>🌐 Longitude: <strong>{{ "%.6f"|format(location.longitude) }}</strong></p>
                <p style="font-size: 12px; margin-top: 8px; opacity: 0.8;">
                    {% if location.set_manually %}
                        ✏️ Set manually
                    {% else %}
                        🤖 Auto-detected
                    {% endif %}
                </p>
            </div>
            {% else %}
            <div class="current-location" style="background: #fef3c7; border-color: #fbbf24;">
                <p style="color: #92400e;">⚠️ <strong>Location not set!</strong> Geofencing will not work until you set the Pi's location.</p>
            </div>
            {% endif %}
            
            <div class="edit-form">
                <div class="input-group">
                    <label for="edit-latitude">Latitude</label>
                    <input type="number" step="0.000001" id="edit-latitude" placeholder="17.4027" 
                           value="{% if location.latitude %}{{ location.latitude }}{% endif %}">
                </div>
                <div class="input-group">
                    <label for="edit-longitude">Longitude</label>
                    <input type="number" step="0.000001" id="edit-longitude" placeholder="78.3398"
                           value="{% if location.longitude %}{{ location.longitude }}{% endif %}">
                </div>
                <div>
                    <button onclick="updateLocation()">💾 Update Location</button>
                    <button class="btn-get-location" onclick="getMyLocation()">📍 Use My Location</button>
                </div>
            </div>
            <p style="font-size: 12px; color: #666; margin-top: 12px;">
                💡 <strong>Tip:</strong> You can get coordinates from Google Maps by right-clicking on your classroom location.
            </p>
        </div>
        
        </div>
        
        <!-- Attendance Threshold Configuration -->
        <div class="location-editor" style="margin-top: 20px;">
            <h3>🎯 Attendance Threshold Configuration</h3>
            
            <div class="current-location">
                <p><strong>Current Threshold:</strong> <span id="current-threshold" data-threshold="{{ threshold_percent }}">{{ threshold_percent }}</span>% of session time</p>
                <p style="font-size: 12px; margin-top: 8px; opacity: 0.8;">
                    Students must be connected for at least this percentage of the total session duration to be marked PRESENT.
                </p>
            </div>
            
            <div class="edit-form">
                <div class="input-group">
                    <label for="threshold-slider">Attendance Threshold (%)</label>
                    <input type="range" id="threshold-slider" min="0" max="100" value="{{ threshold_percent }}" 
                           oninput="document.getElementById('threshold-value').textContent = this.value">
                    <span id="threshold-value" style="font-weight: bold; font-size: 20px; color: #2563eb;">{{ threshold_percent }}</span>%
                </div>
                <div style="margin-top: 15px;">
                    <button onclick="updateThreshold()">💾 Update Threshold</button>
                    <button class="btn-get-location" onclick="resetThreshold()">🔄 Reset to Default (75%)</button>
                </div>
                <div style="margin-top: 12px; padding: 10px; background: #f0f9ff; border-left: 3px solid #2563eb; font-size: 13px;">
                    <strong>Example:</strong> With a 45-minute session and 75% threshold, students need <strong>34 minutes</strong> of connection time to be marked PRESENT.
                </div>
            </div>
        </div>
        
        <div class="info-grid">
            <div class="info-card">
                <h3>Pi IP Address</h3>
                <p>{{ pi_ip or 'Not detected' }}</p>
            </div>
            <div class="info-card">
                <h3>WiFi SSID</h3>
                <p>{{ wifi_ssid or 'Not connected' }}</p>
            </div>
            <div class="info-card">
                <h3>Total Students</h3>
                <p>{{ summary.total }}</p>
            </div>
            <div class="info-card">
                <h3>Detection Method</h3>
                <p style="font-size: 16px;">WiFi Network</p>
            </div>
            {% if camera_enabled %}
            <div class="info-card">
                <h3>Camera Headcount</h3>
                <p>{{ camera_headcount }} faces</p>
                <small style="font-size: 11px; color: #666;">
                    {% if last_camera_check %}
                        Last check: {{ last_camera_check }}
                    {% endif %}
                </small>
            </div>
            {% endif %}
        </div>
        
        <div class="summary">
            <div class="summary-card connected">
                <div class="number">{{ summary.connected }}</div>
                <div class="label">Connected</div>
            </div>
            <div class="summary-card disconnected">
                <div class="number">{{ summary.disconnected }}</div>
                <div class="label">Disconnected</div>
            </div>
            <div class="summary-card present">
                <div class="number">{{ summary.present }}</div>
                <div class="label">Present</div>
            </div>
            <div class="summary-card absent">
                <div class="number">{{ summary.absent }}</div>
                <div class="label">Absent</div>
            </div>
            {% if summary.proxy_risk > 0 %}
            <div class="summary-card" style="border: 2px solid #f59e0b;">
                <div class="number" style="color: #f59e0b;">{{ summary.proxy_risk }}</div>
                <div class="label">⚠️ Proxy Risk</div>
            </div>
            {% endif %}
            <div class="summary-card">
                <div class="number">{{ summary.total }}</div>
                <div class="label">Total Students</div>
            </div>
        </div>
        
        <div class="table-container">
            <table>
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Roll Number</th>
                        <th>Year</th>
                        <th>Department</th>
                        <th>Status</th>
                        <th>Time (min)</th>
                        <th>Last Seen</th>
                        <th>IP Address</th>
                        <th>Final</th>
                    </tr>
                </thead>
                <tbody>
                    {% for student in students %}
                    <tr>
                        <td><strong>{{ student.name }}</strong></td>
                        <td>{{ student.roll_no }}</td>
                        <td>{{ student.year }}</td>
                        <td>{{ student.department }}</td>
                        <td><span class="status status-{{ student.status }}">{{ student.status }}</span></td>
                        <td>{{ "%.1f"|format(student.total_time_minutes or 0) }}</td>
                        <td style="font-size: 13px; color: #666;">
                            {% if student.last_seen %}
                                {{ student.last_seen[:19].replace('T', ' ') }}
                            {% else %}
                                Never
                            {% endif %}
                        </td>
                        <td style="font-size: 13px; color: #666;">{{ student.metrics.get('ip_address', '—') }}</td>
                        <td>
                            {% if student.attendance_final %}
                                <span class="attendance-{{ student.attendance_final }}">{{ student.attendance_final }}</span>
                            {% else %}
                                <span style="color: #9ca3af;">PENDING</span>
                            {% endif %}
                        </td>
                    </tr>
                    {% endfor %}
                    {% if not students %}
                    <tr>
                        <td colspan="9" style="text-align: center; padding: 40px; color: #9ca3af;">
                            No students registered yet. Students will appear here once they register via the app.
                        </td>
                    </tr>
                    {% endif %}
                </tbody>
            </table>
        </div>
    </div>
    
    <script>
        function showAlert(message, type = 'success') {
            const container = document.getElementById('alert-container');
            const alert = document.createElement('div');
            alert.className = `alert alert-${type}`;
            alert.textContent = message;
            container.appendChild(alert);
            setTimeout(() => alert.remove(), 5000);
        }
        
        document.addEventListener('DOMContentLoaded', () => {
            const current = document.getElementById('current-threshold');
            const slider = document.getElementById('threshold-slider');
            const value = document.getElementById('threshold-value');
            if (current && slider && value) {
                const threshold = parseInt(current.dataset.threshold || slider.value, 10);
                slider.value = threshold;
                value.textContent = threshold;
            }
        });

        function updateLocation() {
            const lat = document.getElementById('edit-latitude').value;
            const lon = document.getElementById('edit-longitude').value;
            
            if (!lat || !lon) {
                showAlert('Please enter both latitude and longitude', 'error');
                return;
            }
            
            fetch('/api/set-location', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({latitude: parseFloat(lat), longitude: parseFloat(lon)})
            })
            .then(r => r.json())
            .then(data => {
                if (data.success) {
                    showAlert('✅ Location updated successfully!', 'success');
                    setTimeout(() => location.reload(), 1500);
                } else {
                    showAlert('❌ Error: ' + data.error, 'error');
                }
            })
            .catch(e => showAlert('❌ Error updating location: ' + e, 'error'));
        }
        
        function getMyLocation() {
            if (!navigator.geolocation) {
                showAlert('❌ Geolocation is not supported by your browser', 'error');
                return;
            }
            
            showAlert('📍 Getting your location...', 'success');
            
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    document.getElementById('edit-latitude').value = position.coords.latitude.toFixed(6);
                    document.getElementById('edit-longitude').value = position.coords.longitude.toFixed(6);
                    showAlert('✅ Location detected! Click "Update Location" to save.', 'success');
                },
                (error) => {
                    showAlert('❌ Could not get your location: ' + error.message, 'error');
                }
            );
        }
        
        function updateThreshold() {
            const threshold = document.getElementById('threshold-slider').value;
            
            fetch('/api/set-threshold', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({threshold: parseInt(threshold)})
            })
            .then(r => r.json())
            .then(data => {
                if (data.success) {
                    showAlert('✅ Attendance threshold set to ' + data.threshold + '%', 'success');
                    document.getElementById('current-threshold').textContent = data.threshold;
                    document.getElementById('current-threshold').dataset.threshold = data.threshold;
                } else {
                    showAlert('❌ Error: ' + data.error, 'error');
                }
            })
            .catch(e => showAlert('❌ Error updating threshold: ' + e, 'error'));
        }
        
        function resetThreshold() {
            document.getElementById('threshold-slider').value = 75;
            document.getElementById('threshold-value').textContent = 75;
            updateThreshold();
        }
        
        // Legacy function for backward compatibility
        function setLocation() {
            updateLocation();
        }
        
        // Auto-refresh every 10 seconds
        setTimeout(() => location.reload(), 10000);
    </script>
</body>
</html>
EOF

cat > run.py << 'EOF'
from app import create_app

app = create_app()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

cat > gunicorn_config.py << 'EOF'
bind = '0.0.0.0:5000'
workers = 2
worker_class = 'sync'
timeout = 60
accesslog = 'logs/access.log'
errorlog = 'logs/error.log'
EOF

cat > instance/config.py << 'EOF'
"""Instance-specific configuration."""
import os

REGISTRATION_API_TOKEN = os.getenv('CLASSPULSE_REGISTRATION_TOKEN', 'HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM')
SESSION_REQUIRED_MINUTES = int(os.getenv('CLASSPULSE_SESSION_REQUIRED', '45'))
HEARTBEAT_STALE_SECONDS = int(os.getenv('CLASSPULSE_HEARTBEAT_STALE', '120'))
WIFI_DETECTION_INTERVAL = int(os.getenv('CLASSPULSE_WIFI_INTERVAL', '30'))
GEOFENCE_RADIUS_METERS = int(os.getenv('CLASSPULSE_GEOFENCE_RADIUS', '50'))

# Optional IP Camera Settings
IP_CAMERA_ENABLED = os.getenv('CLASSPULSE_CAMERA_ENABLED', 'false').lower() == 'true'
IP_CAMERA_URL = os.getenv('CLASSPULSE_CAMERA_URL', '')
CAMERA_CHECK_INTERVAL = int(os.getenv('CLASSPULSE_CAMERA_INTERVAL', '10'))
EOF

cat > .env << 'EOF'
CLASSPULSE_REGISTRATION_TOKEN=HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM
CLASSPULSE_SESSION_REQUIRED=45
CLASSPULSE_HEARTBEAT_STALE=120
CLASSPULSE_WIFI_INTERVAL=30
CLASSPULSE_GEOFENCE_RADIUS=50

# Optional IP Camera (set to 'true' to enable)
CLASSPULSE_CAMERA_ENABLED=false
CLASSPULSE_CAMERA_URL=
# Example: CLASSPULSE_CAMERA_URL=http://192.168.0.100:8080/video
CLASSPULSE_CAMERA_INTERVAL=10
EOF

log '✅ Setup complete!'
log ''
log 'Next steps:'
log '1. Find your Pi IP: hostname -I'
log '2. Start server: cd ${PROJECT_ROOT} && source .venv/bin/activate && gunicorn -c gunicorn_config.py run:app'
log '3. Access dashboard: http://YOUR_PI_IP:5000/dashboard'
log '4. Set Pi location on dashboard for geofencing'
log '5. (Optional) Enable IP camera in .env file'
log '6. Students can now register and connect via WiFi'
log ''
log '📱 Students must:'
log '  - Connect to same WiFi network as Pi'
log '  - Install and register via the app'
log '  - Keep app running in background'
log ''
log '📷 Optional IP Camera:'
log '  - Edit .env: Set CLASSPULSE_CAMERA_ENABLED=true'
log '  - Set CLASSPULSE_CAMERA_URL to your IP cam URL'
log '  - Example: http://192.168.0.100:8080/video'
log '  - Restart server to apply changes'
log ''
log '🎉 Your simplified ClassPulse system is ready!'
