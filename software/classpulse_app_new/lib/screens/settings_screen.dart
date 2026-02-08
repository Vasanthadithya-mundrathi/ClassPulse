import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';

import '../providers/app_configuration_provider.dart';
import '../providers/auth_provider.dart';
import '../services/secure_storage_service.dart';
import '../widgets/primary_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = SecureStorageService();
  bool _piEnabled = false;
  bool _loading = true;
  String? _connectionStatus;

  @override
  void initState() {
    super.initState();
    _loadPiStatus();
  }

  Future<void> _loadPiStatus() async {
    final enabled = await _storage.readSetting('pi_enabled') == 'true';
    setState(() {
      _piEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _togglePiConnection(bool value) async {
    setState(() => _loading = true);
    
    if (value) {
      // Test connection to Pi
      final status = await _testPiConnection();
      if (status == null) {
        // Connection successful
        await _storage.writeSetting('pi_enabled', 'true');
        setState(() {
          _piEnabled = true;
          _connectionStatus = 'Connected to Raspberry Pi ✓';
        });

        // Attempt automatic registration once connected
        await _attemptAutoRegistration();
      } else {
        // Connection failed
        setState(() {
          _piEnabled = false;
          _connectionStatus = 'Failed: $status';
        });
      }
    } else {
      // Disable Pi connection
      await _storage.writeSetting('pi_enabled', 'false');
      setState(() {
        _piEnabled = false;
        _connectionStatus = 'Offline mode - App works without Pi';
      });
    }
    
    setState(() => _loading = false);
  }

  Future<String?> _testPiConnection() async {
    try {
      final config = context.read<AppConfigurationProvider>();
      final scheme = config.getString('pi_scheme', fallback: 'http');
      final host = config.getString('pi_ip', fallback: '192.168.0.10');
      final port = config.getInt('pi_port', fallback: 5000);
      
      final uri = Uri(scheme: scheme, host: host, port: port, path: '/healthz');
      
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(uri);
      final response = await request.close();
      
      if (response.statusCode == 200) {
        return null; // Success
      } else {
        return 'Server returned ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfigurationProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
              Theme.of(context).colorScheme.secondary.withOpacity(0.1),
            ],
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Raspberry Pi Connection Section
                  FadeInDown(
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _piEnabled 
                                      ? Colors.green.withOpacity(0.2)
                                      : Colors.grey.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _piEnabled ? Icons.router : Icons.router_outlined,
                                  color: _piEnabled ? Colors.green : Colors.grey,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Raspberry Pi Connection',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _piEnabled
                                          ? 'Attendance synced with classroom server'
                                          : 'Offline mode - Local tracking only',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Colors.grey.shade600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _piEnabled,
                                onChanged: _togglePiConnection,
                                activeColor: Colors.green,
                              ),
                            ],
                          ),
                          if (_connectionStatus != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _piEnabled
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _piEnabled ? Colors.green : Colors.orange,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _piEnabled ? Icons.check_circle : Icons.info,
                                    color: _piEnabled ? Colors.green : Colors.orange,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _connectionStatus!,
                                      style: TextStyle(
                                        color: _piEnabled ? Colors.green.shade700 : Colors.orange.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'How it works:',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          _buildHowItWorksItem(
                            '🔴 Offline Mode',
                            'App tracks attendance locally on your phone. Works anywhere, anytime.',
                          ),
                          const SizedBox(height: 8),
                          _buildHowItWorksItem(
                            '🟢 Pi Connected',
                            'App syncs with classroom server. Attendance sent to teacher dashboard in real-time.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Server Configuration Section
                  FadeInUp(
                    delay: const Duration(milliseconds: 200),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                Icons.settings_ethernet,
                                color: Theme.of(context).colorScheme.primary,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Server Configuration',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildConfigItem(
                            context,
                            'Server IP',
                            config.getString('pi_ip', fallback: '192.168.0.10'),
                            Icons.computer,
                          ),
                          _buildConfigItem(
                            context,
                            'Port',
                            config.getString('pi_port', fallback: '5000'),
                            Icons.power,
                          ),
                          _buildConfigItem(
                            context,
                            'Protocol',
                            config.getString('pi_scheme', fallback: 'http'),
                            Icons.http,
                          ),
                          const SizedBox(height: 16),
                          PrimaryButton(
                            text: 'Test Connection',
                            onPressed: () => _testAndShowResult(),
                          ),
                          const SizedBox(height: 12),
                          PrimaryButton(
                            text: 'Register to Pi',
                            onPressed: () => _forceRegisterToPi(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ),

                  const SizedBox(height: 20),

                  // Advanced Settings Section
                  FadeInUp(
                    delay: const Duration(milliseconds: 400),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ExpansionTile(
                        leading: Icon(
                          Icons.tune,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          'Advanced Configuration',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        subtitle: const Text('Modify server and tracking parameters'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Text(
                                  'Override Firebase Remote Config values for testing. Changes are stored locally.',
                                  style: TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                ...config.effectiveConfig.entries.map(
                                  (entry) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      title: Text(
                                        entry.key,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        entry.value.toString(),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.edit, size: 20),
                                        onPressed: () => _openEditDialog(
                                          context,
                                          entry.key,
                                          entry.value.toString(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                PrimaryButton(
                                  text: 'Reset All Overrides',
                                  onPressed: config.clearOverrides,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Project Details Section
                  FadeInUp(
                    delay: const Duration(milliseconds: 600),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Project Details',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ClassPulse',
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Smart Attendance System',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey.shade700,
                                        ),
                                  ),
                                  const SizedBox(height: 20),
                                  const Divider(),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Developed By:',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildDeveloperItem('Vasanthadithya', '160123749049'),
                                  _buildDeveloperItem('Shaguftha', '160123749307'),
                                  _buildDeveloperItem('Meghana', '160123749306'),
                                  _buildDeveloperItem('P. Nagesh', '160123749056'),
                                  const SizedBox(height: 20),
                                  const Divider(),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Under Guidance of:',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.school,
                                        size: 20,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'N. Sujata Gupta',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 28),
                                    child: Text(
                                      'Department of CET',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
      ),
    );
  }

  Widget _buildDeveloperItem(String name, String rollNumber) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            Icons.person,
            size: 20,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                Text(
                  rollNumber,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksItem(String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testAndShowResult() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Testing connection...'),
          ],
        ),
      ),
    );

    final error = await _testPiConnection();
    Navigator.of(context).pop(); // Close loading dialog

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              error == null ? Icons.check_circle : Icons.error,
              color: error == null ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            Text(error == null ? 'Success!' : 'Connection Failed'),
          ],
        ),
        content: Text(
          error == null
              ? 'Successfully connected to Raspberry Pi server!'
              : 'Could not connect to server:\n$error',
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

  Future<void> _openEditDialog(
    BuildContext context,
    String key,
    String currentValue,
  ) async {
    final controller = TextEditingController(text: currentValue);
    final provider = context.read<AppConfigurationProvider>();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Override $key'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Value',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await provider.persistOverride(key, result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated $key to $result')),
      );
    }
  }

  Future<void> _forceRegisterToPi() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Sending registration...'),
          ],
        ),
      ),
    );

    try {
      final auth = context.read<AuthProvider>();
      final config = context.read<AppConfigurationProvider>();
      await config.ensureLoaded();

      // Try to load stored profile from auth provider or secure storage
      final storedProfile = auth.profile;
      if (storedProfile == null) {
        // Try storage fallback
        final storage = SecureStorageService();
        final profile = await storage.readProfile();
        Navigator.of(context).pop();
        if (profile == null) {
          showDialog(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('No profile'),
              content: const Text('No student profile found on this device. Please register a student first.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK')),
              ],
            ),
          );
          return;
        }

        // If we got here we have a profile from storage
        final result = await auth.sendRegistrationToPi(profile: profile, config: config.effectiveConfig);
        if (result == null) {
          showDialog(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Success'),
              content: const Text('Registration sent to Pi successfully.'),
              actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK'))],
            ),
          );
        } else {
          showDialog(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Registration Failed'),
              content: Text(result),
              actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK'))],
            ),
          );
        }
        return;
      }

      // Have profile from auth provider
      final result = await auth.sendRegistrationToPi(profile: storedProfile, config: config.effectiveConfig);
      Navigator.of(context).pop();
      if (result == null) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Success'),
            content: const Text('Registration sent to Pi successfully.'),
            actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK'))],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Registration Failed'),
            content: Text(result),
            actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _attemptAutoRegistration() async {
    final auth = context.read<AuthProvider>();
    final configProvider = context.read<AppConfigurationProvider>();
    await configProvider.ensureLoaded();

    final profile = auth.profile ?? await SecureStorageService().readProfile();
    if (profile == null) {
      return;
    }

    final result = await auth.sendRegistrationToPi(
      profile: profile,
      config: configProvider.effectiveConfig,
    );

    if (!mounted) return;

    setState(() {
      if (result == null) {
        _connectionStatus = 'Connected and registered with Raspberry Pi ✓';
      } else {
        _connectionStatus = 'Connected but registration failed: $result';
      }
    });
  }
}
