import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Request all required permissions for ClassPulse to function
  Future<bool> requestAllPermissions(BuildContext context) async {
    final permissions = <Permission>[
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.locationWhenInUse,
    ];

    // Check current status
    Map<Permission, PermissionStatus> statuses = {};
    for (var permission in permissions) {
      statuses[permission] = await permission.status;
    }

    // Filter out already granted permissions
    final needRequest = permissions.where((p) => !statuses[p]!.isGranted).toList();

    if (needRequest.isEmpty) {
      return true; // All permissions already granted
    }

    // Show explanation dialog before requesting
    final shouldProceed = await _showPermissionExplanationDialog(context);
    if (!shouldProceed) {
      return false;
    }

    // Request permissions
    final results = await needRequest.request();

    // Check if all required permissions were granted
    final allGranted = results.values.every((status) => status.isGranted);

    if (!allGranted) {
      final permanentlyDenied = results.values.any((status) => status.isPermanentlyDenied);
      if (permanentlyDenied) {
        await _showOpenSettingsDialog(context);
      } else {
        await _showPermissionDeniedDialog(context);
      }
      return false;
    }

    return true;
  }

  Future<bool> _showPermissionExplanationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 12),
            Text('Permissions Required'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ClassPulse needs the following permissions to track attendance:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            _PermissionItem(
              icon: Icons.bluetooth,
              title: 'Bluetooth',
              description: 'To detect classroom beacon',
            ),
            SizedBox(height: 12),
            _PermissionItem(
              icon: Icons.location_on,
              title: 'Location',
              description: 'To verify you\'re in the classroom',
            ),
            SizedBox(height: 16),
            Text(
              'Your data is stored securely on your device and never shared without your consent.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Grant Permissions'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _showPermissionDeniedDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 12),
            Text('Permissions Denied'),
          ],
        ),
        content: const Text(
          'ClassPulse cannot function without the required permissions. '
          'Please grant all permissions to use the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOpenSettingsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.blue),
            SizedBox(width: 12),
            Text('Open Settings'),
          ],
        ),
        content: const Text(
          'Some permissions were permanently denied. '
          'Please enable them in app settings to use ClassPulse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Text(
                description,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
