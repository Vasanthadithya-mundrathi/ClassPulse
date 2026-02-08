# ClassPulse Flutter Client

This module houses the Flutter application described in `PLAN.md`. Follow the plan exactly when extending the codebase.

## Getting Started

1. Install Flutter (3.22 or newer) and the Dart SDK.
2. Enable Firebase for Android and iOS following the official setup guides.
3. From `software/classpulse_app`, run `flutter pub get`.
4. Configure Firebase (Android `google-services.json`, iOS `GoogleService-Info.plist`).
5. Use `flutter run` to launch the prototype on a connected device or emulator.

## Feature Roadmap (per PLAN.md)

- CBIT-specific registration with persistent UUID storage.
- Remote Config-driven developer overrides for all detection parameters.
- Timetable upload pipeline via Firebase Storage.
- Background services for BLE, Wi-Fi, geofence checks, and Raspberry Pi heartbeat.
- Secure communication layers and final attendance reporting.

Keep state management in Provider, leverage secure storage for identity persistence, and integrate Firebase services as outlined in the project plan.
