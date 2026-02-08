# 📊 ClassPulse System Architecture & Flow

## 🏗️ System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLASSPULSE SYSTEM                          │
│                    Automated Attendance Tracking                   │
└─────────────────────────────────────────────────────────────────────┘

     📱 STUDENT APP                🍓 RASPBERRY PI              ☁️ FIREBASE
┌──────────────────┐         ┌─────────────────────┐       ┌──────────────┐
│  Flutter Mobile  │◄───────►│   Flask Server      │◄─────►│  Firestore   │
│                  │  REST    │   (Port 5000)       │ Sync  │  Database    │
│  • Registration  │  API     │                     │       │              │
│  • BLE Scanning  │          │  • REST API         │       │  • Sessions  │
│  • WiFi Check    │          │  • BLE Beacon       │       │  • Students  │
│  • GPS Track     │          │  • Camera Capture   │       │  • Metrics   │
│  • Heartbeat     │          │  • SQLite DB        │       │              │
└──────────────────┘          │  • Dashboard        │       └──────────────┘
                              └─────────────────────┘
                                        │
                                        ▼
                              ┌─────────────────────┐
                              │  📸 Pi Camera        │
                              │  Face Detection     │
                              │  (Headcount)        │
                              └─────────────────────┘
                                        │
                                        ▼
                              ┌─────────────────────┐
                              │  🖥️ Teacher         │
                              │  Web Dashboard      │
                              │  (Browser)          │
                              └─────────────────────┘
```

---

## 🔄 Attendance Tracking Flow

### **Phase 1: Student Registration**

```
┌─────────┐                                      ┌─────────────┐
│ Student │                                      │ Raspberry   │
│ Opens   │  1. Fill CBIT Details                │ Pi Server   │
│ App     │  ─────────────────────────────────►  │             │
│         │                                      │             │
│         │  Name: Faisal Tabrez                 │             │
│         │  Roll: 160120733001                  │             │
│         │  Year: 3rd Year                      │             │
│         │  Dept: CSE                           │ 2. Store in │
│         │  Section: A                          │ SQLite DB   │
│         │                                      │             │
│         │  ◄─────────────────────────────────  │             │
│         │  3. Registration Success             │             │
│         │     (UUID assigned)                  │             │
└─────────┘                                      └─────────────┘
```

### **Phase 2: Class Session - Live Tracking**

```
         CLASSROOM ENVIRONMENT
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   📱 Student Phone          🍓 Raspberry Pi                │
│   ┌──────────────┐         ┌─────────────┐                │
│   │              │         │             │                │
│   │ 1. BLE Scan  │────────►│ Broadcasting│                │
│   │    Detects   │  Finds  │ BLE Beacon  │                │
│   │    Beacon    │  UUID   │             │                │
│   │              │         │ UUID: 1234  │                │
│   └──────────────┘         └─────────────┘                │
│          │                        ▲                        │
│          │ 2. WiFi Check          │                        │
│          │    (network_info_plus) │                        │
│          │    "CBIT_Classroom_5"  │                        │
│          │                        │                        │
│          │ 3. GPS Check           │                        │
│          │    (geolocator)        │                        │
│          │    Inside Geofence ✓   │                        │
│          │                        │                        │
│          │ 4. Send Heartbeat      │                        │
│          └────────────────────────┘                        │
│                 (Every 30 sec)                             │
│                                                            │
│   POST /api/heartbeat                                      │
│   {                                                        │
│     "uuid": "abc123...",                                   │
│     "metrics": {                                           │
│       "rssi": -65,           // Signal strength            │
│       "wifi_ssid": "CBIT_Classroom_5",                     │
│       "geofence_state": "INSIDE",                          │
│       "distance_meters": 5.2                               │
│     }                                                      │
│   }                                                        │
│                                                            │
│   📸 Pi Camera (Every 10 min)                              │
│   ┌─────────────────────────┐                              │
│   │ Capture → Detect Faces  │                              │
│   │ Count: 58 students      │                              │
│   │ Connected: 60 devices   │                              │
│   │ ⚠️ Mismatch Alert!       │                              │
│   └─────────────────────────┘                              │
└────────────────────────────────────────────────────────────┘
```

### **Phase 3: Server Processing**

```
                RASPBERRY PI SERVER
┌────────────────────────────────────────────────────┐
│                                                    │
│  1. Receive Heartbeat                              │
│     ↓                                              │
│  2. Update SQLite Database                         │
│     • status = "CONNECTED"                         │
│     • last_seen = NOW()                            │
│     • last_rssi = -65                              │
│     • wifi_ssid = "CBIT_Classroom_5"               │
│     • geofence_state = "INSIDE"                    │
│     ↓                                              │
│  3. Check Stale Connections                        │
│     • If no heartbeat for 120 sec → DISCONNECTED   │
│     ↓                                              │
│  4. Calculate Connected Duration                   │
│     • Start: first_seen timestamp                  │
│     • End: last_seen timestamp                     │
│     • Duration = End - Start                       │
│     ↓                                              │
│  5. Finalize Attendance                            │
│     • If duration >= 45 min → PRESENT ✓            │
│     • If duration < 45 min → ABSENT ✗              │
│     ↓                                              │
│  6. Camera Verification                            │
│     • Compare headcount vs connected               │
│     • If headcount < connected → PROXY_RISK ⚠️     │
│     ↓                                              │
│  7. Sync to Firebase (Every 15 min)                │
│     • Upload session data to Firestore             │
│     • Backup attendance records                    │
│                                                    │
└────────────────────────────────────────────────────┘
```

### **Phase 4: Teacher Dashboard View**

```
           🖥️ TEACHER WEB DASHBOARD
    http://192.168.1.100:5000/dashboard
┌──────────────────────────────────────────────────┐
│  ClassPulse - Live Attendance Dashboard          │
│  Date: Oct 20, 2025 | Time: 10:30 AM             │
├──────────────────────────────────────────────────┤
│                                                  │
│  📊 Session Statistics                           │
│  ┌────────────┬────────────┬────────────┐        │
│  │ Connected  │ Proxy Risk │Disconnected│        │
│  │    58      │     2      │     0      │        │
│  └────────────┴────────────┴────────────┘        │
│                                                  │
│  ┌────────────┬────────────┐                     │
│  │  Present   │   Absent   │                     │
│  │     56     │      4     │                     │
│  └────────────┴────────────┘                     │
│                                                  │
│  📸 Camera Verification                          │
│  Last Capture: 10:20 AM                          │
│  Headcount: 58 students                          │
│  Status: ✓ Matches connected devices             │
│                                                  │
├──────────────────────────────────────────────────┤
│  👥 Student Details (Live)                       │
├─────┬──────────┬──────┬─────────┬────────┬──────┤
│Name │Roll No   │Status│Last Seen│  RSSI  │Final │
├─────┼──────────┼──────┼─────────┼────────┼──────┤
│Faisal│733001   │🟢 CON│10:30:15 │  -65dB │PRES. │
│Rahul │733002   │🟢 CON│10:30:10 │  -72dB │PRES. │
│Priya │733003   │⚠️ PRX│10:29:45 │  -55dB │PEND. │
│Amit  │733004   │🔴 DIS│10:15:22 │  N/A   │ABS.  │
├─────┴──────────┴──────┴─────────┴────────┴──────┤
│  Auto-refreshes every 5 seconds                  │
└──────────────────────────────────────────────────┘

Legend:
🟢 CONNECTED    - Currently in class
⚠️ PROXY_RISK   - Camera mismatch detected
🔴 DISCONNECTED - Left class or lost signal
PRESENT        - Met 45-min requirement
ABSENT         - Did not meet requirement
PENDING        - Still in session
```

---

## 🎯 4-Layer Verification System

### **Layer 1: BLE (Bluetooth Low Energy)**
```
Pi Broadcasts    ─────►    Student Phone Scans    ─────►    Send Heartbeat
UUID: 1234-5678         Detects Beacon                     Every 30 sec
TX Power: -59dB         Distance: ~10m                     RSSI: -65dB
```

**Why?** Proves student's phone is physically near Pi in classroom

### **Layer 2: WiFi Network**
```
Student Phone    ─────►    Check Connected WiFi    ─────►    Verify Network
network_info_plus         SSID: "CBIT_Classroom_5"         Match = Valid ✓
```

**Why?** Ensures student connected to classroom WiFi (can't fake from outside)

### **Layer 3: GPS Geofence**
```
Student Phone    ─────►    GPS Coordinates    ─────►    Inside Geofence?
geolocator              (17.385044, 78.486671)         Radius: 50m ✓
```

**Why?** Double-checks student is physically inside classroom location

### **Layer 4: Camera Headcount**
```
Pi Camera        ─────►    OpenCV Face Detection    ─────►    Compare Counts
Capture Photo            Count Faces: 58                   Connected: 60
Every 10 min             Haar Cascade                      Mismatch = Alert ⚠️
```

**Why?** Prevents phone sharing (proxy attendance) - camera sees real people

---

## 📊 Attendance Decision Logic

```
START SESSION
     │
     ▼
┌────────────────────┐
│ Student Connects   │
│ BLE + WiFi + GPS   │
└────────────────────┘
     │
     ▼
┌────────────────────┐       ┌──────────────────┐
│ Send Heartbeat     │◄──────┤ Every 30 seconds │
│ (Every 30 sec)     │       └──────────────────┘
└────────────────────┘
     │
     ▼
┌────────────────────┐
│ Server Updates DB  │
│ • status = CONN    │
│ • last_seen = NOW  │
└────────────────────┘
     │
     ▼
┌────────────────────┐
│ No Heartbeat for   │───► Mark DISCONNECTED
│ 120 seconds?       │
└────────────────────┘
     │ Continue receiving
     ▼
┌────────────────────┐
│ Calculate Duration │
│ first_seen → last  │
│ seen = Total Time  │
└────────────────────┘
     │
     ▼
┌────────────────────┐
│ Duration >= 45 min?│
└────────────────────┘
     │
     ├─► YES ─► Mark PRESENT ✓
     │
     └─► NO ──► Mark ABSENT ✗
          │
          ▼
     END SESSION
```

### **Examples:**

**Scenario 1: Full Attendance**
```
Student enters: 9:00 AM
Sends heartbeat: 9:00, 9:00:30, 9:01, ... 9:50
Last heartbeat: 9:50 AM
Duration: 50 minutes
Result: ✓ PRESENT
```

**Scenario 2: Partial Attendance**
```
Student enters: 9:00 AM
Sends heartbeat: 9:00, 9:00:30, ... 9:30
Leaves classroom: 9:30 AM
Duration: 30 minutes
Result: ✗ ABSENT (< 45 min)
```

**Scenario 3: Proxy Detected**
```
Connected devices: 60 students
Camera headcount: 58 faces
Mismatch: 2 students flagged
Status: ⚠️ PROXY_RISK
Action: Manual teacher verification
```

---

## 🔐 Security Measures

### **1. API Token Authentication**
```
All API requests require header:
X-Auth-Token: your-secret-token-min-32-chars

Prevents unauthorized registration/heartbeat
```

### **2. Rate Limiting**
```
Max 60 requests per minute per IP
Prevents DoS attacks
```

### **3. UUID-Based Identity**
```
Each student gets unique UUID
No PII in heartbeat requests
Privacy-focused design
```

### **4. Geofence Validation**
```
Server can cross-check GPS coordinates
Reject heartbeats from outside geofence
```

### **5. Camera Verification**
```
Physical headcount prevents:
• Phone sharing (proxy attendance)
• Multiple devices per student
• Ghost registrations
```

---

## 📈 Data Flow Summary

```
STUDENT PHONE                RASPBERRY PI                 FIREBASE
     │                            │                           │
     │  1. Register               │                           │
     ├────────────────────────────►                           │
     │                            │                           │
     │  2. Scan BLE Beacon        │                           │
     │◄───────────────────────────┤                           │
     │                            │                           │
     │  3. Send Heartbeat         │                           │
     ├────────────────────────────►                           │
     │    (Every 30 sec)          │                           │
     │                            │  4. Store in SQLite       │
     │                            │     (Real-time)           │
     │                            │                           │
     │                            │  5. Camera Capture        │
     │                            │     (Every 10 min)        │
     │                            │                           │
     │                            │  6. Finalize Attendance   │
     │                            │     (After 45 min)        │
     │                            │                           │
     │                            │  7. Sync to Cloud         │
     │                            ├───────────────────────────►
     │                            │    (Every 15 min)         │
     │                            │                           │
     │  8. View Dashboard         │                           │
     │◄───────────────────────────┤                           │
     │    (Browser)               │                           │
```

---

## 🎓 Complete System Requirements

### **Hardware:**
- ✅ Raspberry Pi 3B+ or 4
- ✅ Pi Camera Module
- ✅ Power supply (5V/2.5-3A)
- ✅ MicroSD card (32GB+)
- ✅ Classroom WiFi

### **Software:**
- ✅ Raspberry Pi OS (64-bit)
- ✅ Python 3.9+
- ✅ Flask + Gunicorn
- ✅ SQLite
- ✅ OpenCV
- ✅ PyBluez
- ✅ Firebase Admin SDK

### **Mobile App:**
- ✅ Flutter 3.24.3+
- ✅ Android 6.0+ (minSdk 23)
- ✅ Bluetooth permissions
- ✅ Location permissions
- ✅ Network permissions

### **Cloud Services:**
- ✅ Firebase Authentication
- ✅ Cloud Firestore
- ✅ Firebase Storage
- ✅ Remote Config

---

## 🚀 Quick Start Guide

1. **Setup Raspberry Pi** (20 min)
   ```bash
   ./setup_server.sh
   ```

2. **Configure Settings** (5 min)
   - Edit `instance/config.py`
   - Set API token
   - Add Firebase credentials

3. **Start Server** (1 min)
   ```bash
   sudo systemctl start classpulse
   ```

4. **Install App on Phones** (2 min per student)
   - Share `app-release.apk`
   - Install and register

5. **Open Teacher Dashboard** (30 sec)
   - Browser: `http://<pi-ip>:5000/dashboard`

6. **Start Class** ✓
   - Students automatically tracked!

---

## 📞 Need Help?

Refer to: **RASPBERRY_PI_COMPLETE_SETUP.md** for detailed instructions!
