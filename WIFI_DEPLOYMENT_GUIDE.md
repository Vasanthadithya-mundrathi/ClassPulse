# ClassPulse - WiFi Detection System Deployment Guide

## 🎯 Simplified System Overview

This version uses **WiFi-based detection** instead of Bluetooth for simpler setup and better reliability.

### Key Features:
- ✅ WiFi network detection
- ✅ JSON file storage (no database)
- ✅ Optional IP camera support
- ✅ GPS geofencing
- ✅ No cloud dependencies
- ✅ Bluetooth-ready for future

---

## 📋 Prerequisites

### Hardware:
- ✅ Raspberry Pi 4 (2GB+ RAM)
- ✅ MicroSD Card (16GB+)
- ✅ WiFi router (for classroom network)
- ✅ Android phones (Android 6.0+)
- ✅ (Optional) IP camera for headcount verification

### Software:
- Raspberry Pi OS (Bullseye or later)
- Internet connection for initial setup

---

## 🚀 Part 1: Raspberry Pi Setup

### Step 1: Prepare Raspberry Pi

```bash
# 1. Flash Raspberry Pi OS to SD card
# 2. Boot and SSH into Pi
ssh pi@raspberrypi.local

# 3. Update system
sudo apt update && sudo apt upgrade -y
```

### Step 2: Copy and Run Setup Script

```bash
# Transfer setup_server_simplified.sh to Pi
# Then:
cd ~
chmod +x setup_server_simplified.sh
./setup_server_simplified.sh

# Wait 5-10 minutes for installation...
```

### Step 3: Configure Network

```bash
# Find Pi's IP address
hostname -I
# Example output: 192.168.0.10

# Note this IP - students will connect to it
```

### Step 4: Start the Server

```bash
cd ~/classpulse/server
source .venv/bin/activate
gunicorn -c gunicorn_config.py run:app

# Server starts on: http://0.0.0.0:5000
```

### Step 5: Set Up Auto-Start

```bash
sudo nano /etc/systemd/system/classpulse.service
```

Paste this:
```ini
[Unit]
Description=ClassPulse WiFi Attendance Server
After=network.target

[Service]
Type=notify
User=pi
WorkingDirectory=/home/pi/classpulse/server
Environment="PATH=/home/pi/classpulse/server/.venv/bin"
ExecStart=/home/pi/classpulse/server/.venv/bin/gunicorn -c gunicorn_config.py run:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable classpulse.service
sudo systemctl start classpulse.service
sudo systemctl status classpulse.service
```

### Step 6: Access Dashboard and Configure

```bash
# Open in browser:
http://192.168.0.10:5000/dashboard

# Set classroom location:
1. Enter latitude and longitude
2. Click "Set Location"
3. Students' apps will use this for geofencing
```

---

## 📷 Optional: IP Camera Setup

If you want headcount verification:

### Step 1: Set Up IP Camera

Use any IP camera or phone app like "IP Webcam" for Android.

Example camera URL format:
```
http://192.168.0.100:8080/video
```

### Step 2: Enable Camera in Pi

```bash
cd ~/classpulse/server
nano .env

# Change these lines:
CLASSPULSE_CAMERA_ENABLED=true
CLASSPULSE_CAMERA_URL=http://192.168.0.100:8080/video

# Save and restart
sudo systemctl restart classpulse.service
```

### Step 3: Verify Camera

Dashboard will show:
- Camera headcount
- Last check timestamp
- Proxy risk warnings (if headcount < connected students)

---

## 📱 Part 2: Flutter App Configuration

### Update App Configuration

The app needs to be updated to use WiFi detection. Here are the key changes:

#### 1. Update `remote_config_service.dart`

Already updated with production credentials:
```dart
'registration_api_token': 'HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM'
'pi_ip': '192.168.0.10'  // Change to your Pi's IP
```

#### 2. WiFi Detection Service

New `network_detection_service.dart` provides:
- Current WiFi SSID detection
- IP address retrieval
- Pi server info fetching
- Connection testing

#### 3. Updated Heartbeat Service

Sends comprehensive metrics:
- WiFi SSID and connection status
- GPS location and geofence state
- Device IP address
- (Optional) Bluetooth beacon data

### Build Updated App

```bash
cd "c:\Volume D\classpulse\software\classpulse_app_new"
C:/flutter/bin/flutter.bat clean
C:/flutter/bin/flutter.bat build apk --release
```

APK location:
```
build\app\outputs\flutter-apk\app-release.apk
```

---

## 🎓 Part 3: Classroom Deployment

### For Students:

#### Step 1: Connect to Classroom WiFi
```
1. Go to phone Settings → WiFi
2. Connect to classroom WiFi network
3. Note the WiFi name (SSID)
```

#### Step 2: Install and Register

```
1. Install ClassPulse APK
2. Grant ALL permissions:
   ✅ Location
   ✅ Bluetooth (for future use)
   ✅ Network access
3. Fill registration form
4. Tap "Register"
```

#### Step 3: Verify Connection

```
1. Check "Connected" status in app
2. Teacher should see student on dashboard
3. Keep app running in background
```

### For Teachers:

#### Dashboard URL:
```
http://192.168.0.10:5000/dashboard
```

#### What You See:
- **Connected**: Students currently on WiFi
- **Disconnected**: Students who left/offline
- **Present**: Students with 45+ minutes
- **Absent**: Students with < 45 minutes
- **Proxy Risk**: Camera detects fewer people than connected devices
- **Camera Headcount**: Number of faces (if camera enabled)

---

## 🔧 Configuration Options

### Server Configuration

Edit `~/classpulse/server/.env`:

```bash
# API Token (matches app)
CLASSPULSE_REGISTRATION_TOKEN=HxKaTtDA0p6c1RFiInRFCWZC9aJWCqAEUMRz93HP1VM

# Attendance thresholds
CLASSPULSE_SESSION_REQUIRED=45          # Minutes for PRESENT
CLASSPULSE_HEARTBEAT_STALE=120          # Seconds before DISCONNECTED

# Detection intervals
CLASSPULSE_WIFI_INTERVAL=30             # WiFi scan interval (seconds)
CLASSPULSE_GEOFENCE_RADIUS=50           # Geofence radius (meters)

# Optional camera
CLASSPULSE_CAMERA_ENABLED=false
CLASSPULSE_CAMERA_URL=
CLASSPULSE_CAMERA_INTERVAL=10           # Camera check interval (minutes)
```

After changes:
```bash
sudo systemctl restart classpulse.service
```

---

## 🔍 How It Works

### WiFi Detection Mode:

```
1. Student connects to classroom WiFi
   └─> Phone gets IP address (e.g., 192.168.0.25)

2. App sends heartbeat to Pi every 30 seconds
   └─> Includes: WiFi SSID, IP, GPS, timestamp

3. Pi checks WiFi network for connected devices
   └─> Uses ARP table to list all devices

4. Pi tracks connection time for each student
   └─> Session time = continuous connection duration

5. Attendance finalized based on time threshold
   └─> 45+ minutes = PRESENT
   └─> < 45 minutes = ABSENT

6. (Optional) Camera checks headcount
   └─> If camera_count < connected_count = PROXY RISK
```

### Data Storage:

All data in `/home/pi/classpulse/server/data/students.json`:

```json
{
  "students": [
    {
      "uuid": "...",
      "name": "Student Name",
      "roll_no": "123456",
      "status": "CONNECTED",
      "last_seen": "2025-10-24T10:30:00Z",
      "total_time_minutes": 47,
      "attendance_final": "PRESENT",
      "metrics": {
        "wifi_ssid": "ClassroomWiFi",
        "ip_address": "192.168.0.25",
        "geofence_state": "INSIDE"
      }
    }
  ],
  "system_state": {
    "pi_location": {
      "latitude": 17.4027,
      "longitude": 78.3398
    },
    "wifi_ssid": "ClassroomWiFi",
    "camera_headcount": 25
  }
}
```

---

## 🐛 Troubleshooting

### Issue: Students can't connect

**Check:**
```bash
# 1. Pi is on network
ping 192.168.0.10

# 2. Server is running
sudo systemctl status classpulse.service

# 3. Firewall allows port 5000
sudo ufw allow 5000/tcp

# 4. Test from browser
curl http://192.168.0.10:5000/healthz
```

### Issue: WiFi detection not working

**Check:**
```bash
# 1. Pi can see connected devices
arp -a

# 2. Student phone has correct IP
# Check on phone: Settings → WiFi → Advanced

# 3. Check server logs
sudo journalctl -u classpulse.service -f
```

### Issue: Geofencing not working

**Check:**
```bash
# 1. Pi location is set
# Dashboard should show coordinates

# 2. Student app has location permission
# Settings → Apps → ClassPulse → Permissions → Location → Always

# 3. GPS is enabled on phone
```

### Issue: Camera not detecting

**Check:**
```bash
# 1. Camera is accessible
curl http://192.168.0.100:8080/video

# 2. Camera URL is correct in .env
cat ~/classpulse/server/.env | grep CAMERA

# 3. Camera is enabled
# CLASSPULSE_CAMERA_ENABLED=true

# 4. Check error in dashboard
```

---

## 📊 System Monitoring

### View Logs

```bash
# Real-time logs
sudo journalctl -u classpulse.service -f

# Last 50 lines
sudo journalctl -u classpulse.service -n 50

# Errors only
sudo journalctl -u classpulse.service -p err
```

### Check Data File

```bash
# View students data
cat ~/classpulse/server/data/students.json | python3 -m json.tool

# Backup data
cp ~/classpulse/server/data/students.json ~/backup_$(date +%Y%m%d).json
```

### Monitor Resources

```bash
# CPU/Memory
htop

# Disk space
df -h

# Network connections
ss -tuln | grep 5000
```

---

## 🔒 Security Considerations

### 1. Network Security

```bash
# Use WPA2/WPA3 WiFi encryption
# Hide SSID if possible
# MAC address filtering for student devices
```

### 2. API Token

```
- Token embedded in app and server
- Keep APK secure
- Only distribute to authorized students
- Regenerate token if compromised
```

### 3. Data Privacy

```bash
# Restrict dashboard access
sudo ufw allow from 192.168.0.0/24 to any port 5000

# Regular backups
crontab -e
# Add: 0 0 * * * cp ~/classpulse/server/data/students.json ~/backups/students_$(date +\%Y\%m\%d).json
```

---

## 📈 Advantages of WiFi Detection

✅ **No Bluetooth Issues**: More reliable than BLE beacons  
✅ **Simple Setup**: No beacon hardware needed  
✅ **Better Range**: WiFi covers entire classroom  
✅ **Accurate Detection**: Direct IP tracking  
✅ **No Battery Drain**: WiFi already active on phones  
✅ **Easy Debugging**: Can see all connected devices  

---

## 🔄 Future Enhancements

### Add Bluetooth Detection:

The app already has Bluetooth code ready. To enable:

1. Set up Bluetooth beacon on Pi
2. Update app config with beacon UUID
3. Heartbeat will include both WiFi and Bluetooth data
4. Dual verification for better accuracy

### Add QR Code Check-in:

Generate daily QR codes on dashboard for manual verification.

### Add Firebase Sync:

Optional cloud backup of attendance data.

---

## ✅ Deployment Checklist

### Raspberry Pi:
- [ ] Pi OS installed and updated
- [ ] Static IP configured
- [ ] Setup script executed successfully
- [ ] Server running on port 5000
- [ ] Systemd service enabled
- [ ] Dashboard accessible
- [ ] Location set on dashboard
- [ ] (Optional) IP camera configured

### Android App:
- [ ] APK built with WiFi detection
- [ ] Distributed to students
- [ ] Students connected to WiFi
- [ ] All permissions granted
- [ ] Registration successful
- [ ] Students appear on dashboard

### Testing:
- [ ] Student connects to WiFi → Shows CONNECTED
- [ ] Student stays 45+ minutes → Shows PRESENT
- [ ] Student disconnects → Shows DISCONNECTED
- [ ] Geofencing validates location
- [ ] (Optional) Camera counts faces
- [ ] Dashboard updates in real-time

---

## 🎉 You're Ready!

Your WiFi-based ClassPulse attendance system is now fully operational!

**Next Steps:**
1. Test with a few students first
2. Monitor dashboard during first class
3. Adjust thresholds as needed
4. (Optional) Enable camera after testing

**Support:**
- Check logs: `sudo journalctl -u classpulse.service -f`
- View data: `cat ~/classpulse/server/data/students.json`
- Test connection: `curl http://YOUR_PI_IP:5000/healthz`

---

**Developed By:**
- Vasanthadithya - 160123749049
- Shaguftha - 160123749307
- Meghana - 160123749306
- P. Nagesh - 160123749056

**Under Guidance of:** N. Sujata Gupta, Dept of CET

---

*Last updated: October 24, 2025*
