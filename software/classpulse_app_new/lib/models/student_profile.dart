class StudentProfile {
  final String uuid;
  final String name;
  final String rollNumber;
  final String year;
  final String department;
  final String section;

  const StudentProfile({
    required this.uuid,
    required this.name,
    required this.rollNumber,
    required this.year,
    required this.department,
    required this.section,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    return StudentProfile(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      rollNumber: json['rollNumber'] as String,
      year: json['year'] as String,
      department: json['department'] as String,
      section: json['section'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'rollNumber': rollNumber,
      'year': year,
      'department': department,
      'section': section,
    };
  }
}
