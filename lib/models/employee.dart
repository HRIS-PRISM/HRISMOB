/// HRIS user roles, exactly as stored in `users.role`
/// (`enum('superadmin','administrator','staff','technical')`).
///
/// `technical` is the developers' account. It is a separate role from
/// `administrator` and `superadmin` and follows only the web HRIS rules for
/// that role (the `/admin-home` dashboard and the page-access bypass). The
/// mobile app adds no developer-only features or extra privileges for it.
enum UserRole {
  superadmin('superadmin', 'Superadmin'),
  administrator('administrator', 'Administrator'),
  staff('staff', 'Staff'),
  technical('technical', 'Technical');

  const UserRole(this.value, this.label);

  /// Value stored in the database and carried in the web JWT.
  final String value;
  final String label;

  static UserRole? fromValue(String? value) {
    final v = value?.trim().toLowerCase();
    for (final role in values) {
      if (role.value == v) return role;
    }
    return null;
  }
}

/// The signed-in employee.
///
/// Fields follow the `user` object from the web API
/// `GET /users/:employeeNumber` (backend/routes/users.js), which only returns
/// the caller's own record. Government IDs, birth details and addresses are
/// deliberately not part of the mobile model.
class Employee {
  const Employee({
    required this.employeeNumber,
    required this.role,
    this.pageAccess = const {},
    this.firstName,
    this.middleName,
    this.lastName,
    this.nameExtension,
    this.email,
    this.employmentCategory,
    this.departmentCode,
    this.departmentName,
    this.isJobOrder = false,
  });

  final String employeeNumber;
  final UserRole role;

  /// Page `component_identifier`s granted in `page_access`.
  final Set<String> pageAccess;

  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? nameExtension;
  final String? email;

  /// Label such as "Non-Academic · General Administration": the web header
  /// shows `categoryLabel` with " | " replaced by " · ", hiding "Unassigned".
  final String? employmentCategory;

  final String? departmentCode;
  final String? departmentName;

  /// Job Order / Contract of Service: the web `useIsJobOrder` hook
  /// (`noLeaveBenefits` from the leave calendar API). The web Home shows
  /// Job Orders "Time Logs" and "Up Next" instead of the leave-based cards.
  final bool isJobOrder;

  factory Employee.fromAuthJson(Map<String, Object?> json) {
    final employeeNumber = _requiredString(json, 'employeeNumber');
    final rawRole = json['role'];
    if (rawRole is! String) throw const FormatException('Invalid role');
    final role = UserRole.fromValue(rawRole);
    if (role == null) throw const FormatException('Invalid role');
    return Employee(
      employeeNumber: employeeNumber,
      role: role,
      firstName: _string(json['firstName']),
      middleName: _string(json['middleName']),
      lastName: _string(json['lastName']),
      nameExtension: _string(json['nameExtension']),
      email: _string(json['email']),
    );
  }

  factory Employee.fromStoredJson(Map<String, Object?> json) =>
      Employee.fromAuthJson(json);

  Map<String, Object?> toStoredJson() => {
    'employeeNumber': employeeNumber,
    'role': role.value,
    'firstName': firstName,
    'middleName': middleName,
    'lastName': lastName,
    'nameExtension': nameExtension,
    'email': email,
  };

  /// Web greeting order: first, middle, last, extension.
  String get fullName {
    final name = [firstName, middleName, lastName, nameExtension]
        .whereType<String>()
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .join(' ');
    return name.isEmpty ? employeeNumber : name;
  }

  String get initials {
    final f = firstName?.trim() ?? '';
    final l = lastName?.trim() ?? '';
    final s = '${f.isEmpty ? '' : f[0]}${l.isEmpty ? '' : l[0]}';
    return s.isEmpty ? '?' : s.toUpperCase();
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = _string(json[key]);
    if (value == null) throw FormatException('Missing $key');
    return value;
  }

  static String? _string(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
