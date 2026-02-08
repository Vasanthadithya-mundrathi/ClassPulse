import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:animate_do/animate_do.dart';

import '../main.dart';
import '../models/student_profile.dart';
import '../models/cbit_data.dart';
import '../providers/app_configuration_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/primary_button.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _rollController = TextEditingController();

  String _selectedYear = CbitData.studentYears[0];
  String _selectedDepartment = CbitData.departments[4]; // CSE by default
  String _selectedSection = '1';

  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _rollController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _submitting = true);

    final profile = StudentProfile(
      uuid: const Uuid().v4(),
      name: _nameController.text.trim(),
      rollNumber: _rollController.text.trim(),
      year: _selectedYear,
      department: _selectedDepartment,
      section: _selectedSection,
    );

    final configProvider = context.read<AppConfigurationProvider>();
    await configProvider.ensureLoaded();

    try {
      await context.read<AuthProvider>().registerStudent(
            profile,
            configProvider.effectiveConfig,
          );

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RootPage()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: $error'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  const SizedBox(height: 20),
                  FadeInDown(
                    child: Icon(
                      Icons.person_add_rounded,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeInDown(
                    delay: const Duration(milliseconds: 200),
                    child: Text(
                      'Welcome to ClassPulse',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeInDown(
                    delay: const Duration(milliseconds: 300),
                    child: Text(
                      'Complete your registration to get started',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  FadeInLeft(
                    delay: const Duration(milliseconds: 400),
                    child: _buildTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      icon: Icons.person_outline,
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter your name'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeInRight(
                    delay: const Duration(milliseconds: 500),
                    child: _buildTextField(
                      controller: _rollController,
                      label: 'Roll Number',
                      icon: Icons.badge_outlined,
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter your roll number'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeInLeft(
                    delay: const Duration(milliseconds: 600),
                    child: _buildDropdown(
                      label: 'Year',
                      value: _selectedYear,
                      icon: Icons.calendar_today_outlined,
                      onChanged: (value) =>
                          setState(() => _selectedYear = value ?? _selectedYear),
                      items: CbitData.studentYears,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeInRight(
                    delay: const Duration(milliseconds: 700),
                    child: _buildDropdown(
                      label: 'Department',
                      value: _selectedDepartment,
                      icon: Icons.school_outlined,
                      onChanged: (value) => setState(
                          () => _selectedDepartment = value ?? _selectedDepartment),
                      items: CbitData.departments,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeInLeft(
                    delay: const Duration(milliseconds: 800),
                    child: _buildDropdown(
                      label: 'Section',
                      value: _selectedSection,
                      icon: Icons.group_outlined,
                      onChanged: (value) => setState(
                          () => _selectedSection = value ?? _selectedSection),
                      items: const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
                    ),
                  ),
                  const SizedBox(height: 40),
                  FadeInUp(
                    delay: const Duration(milliseconds: 900),
                    child: PrimaryButton(
                      text: _submitting ? 'Registering…' : 'Complete Registration',
                      onPressed: _submitting ? null : _submit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
