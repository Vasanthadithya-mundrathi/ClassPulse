/// CBIT Hyderabad specific data constants
/// Contains departments and student year information for the ClassPulse app

class CbitData {
  /// List of all departments at CBIT Hyderabad
  static const List<String> departments = [
    // Engineering and Technology Departments
    'Civil Engineering',
    'Mechanical/Production Engineering',
    'Electrical & Electronics Engineering',
    'Electronics & Communication Engineering',
    'Computer Science & Engineering',
    'CSE (Artificial Intelligence & Machine Learning)',
    'CSE (Internet of Things & Cyber Security including Blockchain Technology)',
    'Information Technology',
    'Artificial Intelligence & Data Science',
    'Chemical Engineering',
    'Biotechnology',
    // Other Major Departments
    'Master of Computer Applications (MCA)',
    'School of Management Studies (MBA)',
    // Supporting Science and Humanities Departments
    'Physics',
    'Chemistry',
    'Mathematics',
    'English',
    'Physical Education',
  ];

  /// List of all student years at CBIT Hyderabad
  static const List<String> studentYears = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
    'M.Tech (2 years)',
    'MCA (3 years)',
    'MBA (2 years)',
  ];

  /// Get engineering departments only (B.Tech programs)
  static List<String> get engineeringDepartments {
    return [
      'Civil Engineering',
      'Mechanical/Production Engineering',
      'Electrical & Electronics Engineering',
      'Electronics & Communication Engineering',
      'Computer Science & Engineering',
      'CSE (Artificial Intelligence & Machine Learning)',
      'CSE (Internet of Things & Cyber Security including Blockchain Technology)',
      'Information Technology',
      'Artificial Intelligence & Data Science',
      'Chemical Engineering',
      'Biotechnology',
    ];
  }

  /// Get science and humanities departments
  static List<String> get scienceAndHumanitiesDepartments {
    return [
      'Physics',
      'Chemistry',
      'Mathematics',
      'English',
      'Physical Education',
    ];
  }

  /// Get postgraduate departments
  static List<String> get postgraduateDepartments {
    return [
      'Master of Computer Applications (MCA)',
      'School of Management Studies (MBA)',
    ];
  }

  /// Get B.Tech years (1st to 4th year)
  static List<String> get btechYears {
    return [
      '1st Year',
      '2nd Year',
      '3rd Year',
      '4th Year',
    ];
  }

  /// Get postgraduate years (M.Tech, MCA, MBA)
  static List<String> get postgraduateYears {
    return [
      'M.Tech (2 years)',
      'MCA (3 years)',
      'MBA (2 years)',
    ];
  }
}