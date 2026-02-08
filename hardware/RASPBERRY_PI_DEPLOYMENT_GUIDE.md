# ClassPulse Raspberry Pi Server Deployment Guide

## Overview
This guide provides step-by-step instructions for deploying the ClassPulse hardware server on a Raspberry Pi for integration with the Flutter attendance app.

## Hardware Requirements
- **Raspberry Pi 4** (recommended) or Raspberry Pi 3B+
- **Camera Module** (for headcount detection)
- **Bluetooth Adapter** (built-in Bluetooth recommended)
- **SD Card** (minimum 16GB, Class 10)
- **Power Supply** (5V/3A for Pi 4, 5V/2.5A for Pi 3)
- **Network Connection** (Ethernet or WiFi)

## Software Prerequisites
- **Raspberry Pi OS** (64-bit recommended)
- **Python 3.7+**
- **Camera enabled** in raspi-config
- **Bluetooth enabled** in raspi-config

## Installation Steps

### 1. Prepare the Raspberry Pi

```bash
# Update system packages
sudo apt-get update
sudo apt-get upgrade -y

# Install required system packages
sudo apt-get install -y python3-venv python3-pip libatlas-base-dev \
    libbluetooth-dev bluetooth bluez libsqlite3-dev libopencv-dev \
    pkg-config curl git
```

### 2. Run the Setup Script

```bash
# Navigate to hardware directory
cd /path/to/classpulse/hardware

# Execute the setup script
bash setup_server.sh
```

The script will automatically:
- Create server directory structure in `~/classpulse/server`
- Set up Python virtual environment
- Install Python dependencies (Flask, OpenCV, BLE libraries)
- Create SQLite database with attendance schema
- Download Haar cascade for face detection
- Generate Flask application files
- Create configuration files
- Set up environment variables

### 3. Configure Network Settings

Edit the instance configuration file:

```bash
nano ~/classpulse/server/instance/config.py
```

Update the following settings as needed:
- `BLE_BEACON_UUID`: Bluetooth beacon identifier
- `REGISTRATION_API_TOKEN`: Authentication token for Flutter app
- `CAMERA_INTERVAL_MINUTES`: Camera headcount check frequency
- `SYNC_INTERVAL_MINUTES`: Data synchronization frequency

### 4. Set Environment Variables

```bash
# Set permanent environment variables
echo 'export CLASSPULSE_REGISTRATION_TOKEN=HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM' >> ~/.bashrc
echo 'export CLASSPULSE_BLE_UUID=aea91077-00fb-4345-b748-bd35c153c3a6' >> ~/.bashrc

# Reload bash configuration
source ~/.bashrc
```

## Server Components

### Flask API Endpoints

The server provides the following REST API endpoints for Flutter app integration:

#### Health Check
- **GET** `/healthz`
- Returns server status and timestamp

#### Student Registration
- **POST** `/api/register`
- Headers: `X-Auth-Token: HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM`
- Body: `{"uuid": "device_id", "name": "Student Name", "rollNumber": "ROLL001", "year": "2024", "department": "CSE", "section": "A"}`

#### Heartbeat Updates
- **POST** `/api/heartbeat`
- Headers: `X-Auth-Token: HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM`
- Body: `{"uuid": "device_id", "metrics": {"rssi": -45, "wifi_ssid": "ClassPulseLab", "geofence_state": "INSIDE"}}`

#### Student List
- **GET** `/api/students`
- Headers: `X-Auth-Token: HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM`
- Returns list of registered students with attendance status

### Dashboard Interface

- **Web Dashboard**: `http://raspberry_pi_ip:5000/dashboard`
- Real-time student attendance status
- Camera headcount vs connected students
- Individual student metrics (RSSI, WiFi, geofence)

## Starting the Server

### Development Mode
```bash
cd ~/classpulse/server
source .venv/bin/activate
python run.py
```

### Production Mode (Recommended)
```bash
cd ~/classpulse/server
source .venv/bin/activate
gunicorn --config gunicorn_config.py run:app
```

### System Service (Auto-start)
```bash
# Create systemd service file
sudo nano /etc/systemd/system/classpulse.service
```

Add the following content:
```ini
[Unit]
Description=ClassPulse Attendance Server
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/classpulse/server
Environment=PATH=/home/pi/classpulse/server/.venv/bin
ExecStart=/home/pi/classpulse/server/.venv/bin/gunicorn --config gunicorn_config.py run:app
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start the service
sudo systemctl enable classpulse
sudo systemctl start classpulse

# Check status
sudo systemctl status classpulse
```

## Flutter App Integration

### Configuration
The Flutter app expects the server at:
- **Default IP**: `192.168.0.10`
- **Port**: `5000`
- **Protocol**: `http`

Update these settings in the Flutter app's remote config if using a different IP.

### BLE Beacon
The server broadcasts a BLE beacon with:
- **UUID**: `aea91077-00fb-4345-b748-bd35c153c3a6`
- **Major**: `1`
- **Minor**: `1`
- **TX Power**: `-59 dBm`

### API Token
All Flutter app requests must include:
```
X-Auth-Token: HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM
```

## Testing Integration

### 1. Server Health Check
```bash
curl http://localhost:5000/healthz
# Expected: {"status":"ok","time":"2024-01-01T12:00:00.000000"}
```

### 2. Student Registration
```bash
curl -X POST http://localhost:5000/api/register \
  -H "X-Auth-Token: HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM" \
  -H "Content-Type: application/json" \
  -d '{"uuid":"test-device-001","name":"Test Student","rollNumber":"T001","year":"2024","department":"CSE","section":"A"}'
```

### 3. Heartbeat Update
```bash
curl -X POST http://localhost:5000/api/heartbeat \
  -H "X-Auth-Token: HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM" \
  -H "Content-Type: application/json" \
  -d '{"uuid":"test-device-001","metrics":{"rssi":-45,"wifi_ssid":"ClassPulseLab","geofence_state":"INSIDE"}}'
```

### 4. Dashboard Access
Open `http://raspberry_pi_ip:5000/dashboard` in a web browser to view the attendance dashboard.

## Troubleshooting

### Common Issues

1. **Camera not detected**
   - Ensure camera is enabled in `raspi-config`
   - Check camera connection and permissions

2. **Bluetooth beacon not working**
   - Verify Bluetooth is enabled in `raspi-config`
   - Check BLE compatibility of Bluetooth adapter

3. **Flutter app connection failed**
   - Verify server IP and port configuration
   - Check API token matches between server and app
   - Ensure firewall allows connections on port 5000

4. **Database errors**
   - Check file permissions in `~/classpulse/server/instance/`
   - Verify SQLite database integrity

### Logs
- Application logs: `~/classpulse/server/logs/`
- System logs: `sudo journalctl -u classpulse -f`

## Security Considerations

1. **Change default API token** in production
2. **Configure firewall** to restrict access to port 5000
3. **Use HTTPS** in production environment
4. **Regularly update** Raspberry Pi OS and Python packages

## Performance Optimization

1. **Camera Settings**: Adjust `CAMERA_INTERVAL_MINUTES` based on requirements
2. **BLE Power**: Modify `BLE_TX_POWER` for optimal beacon range
3. **Database Maintenance**: Implement regular cleanup of old attendance records
4. **System Resources**: Monitor CPU and memory usage

## Support

For issues specific to the ClassPulse system:
1. Check the setup script logs in `~/classpulse/server/logs/`
2. Verify all dependencies are installed correctly
3. Test individual components (camera, BLE, database) separately
4. Check Flutter app configuration matches server settings