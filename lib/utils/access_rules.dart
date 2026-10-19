import '../models/employee.dart';

/// Role and page-access rules mirrored from the web HRIS, for showing or
/// hiding navigation only. They are NOT a security boundary: the backend
/// must authorise every request (Phase 4).

/// `pages.component_identifier` of the General "Attendance" page
/// (frontend route `/attendance-user-state`).
const String attendancePageId = 'attendance-user-state';

/// Web `Login.jsx` `navigateToDashboard`: staff go to `/home`; superadmin,
/// administrator and technical go to `/admin-home`.
enum DashboardKind { employee, admin }

DashboardKind dashboardFor(UserRole role) =>
    role == UserRole.staff ? DashboardKind.employee : DashboardKind.admin;

/// Web `Sidebar.jsx` `bypassPageAccessRoles`.
const _bypassPageAccessRoles = {UserRole.superadmin, UserRole.technical};

/// Web `Sidebar.jsx` `shouldShowMenuItem`: Home and Profile are always shown;
/// superadmin and technical see every page; other roles need a `page_access`
/// grant for the page.
bool canSeePage(Employee employee, String componentIdentifier) {
  if (_bypassPageAccessRoles.contains(employee.role)) return true;
  return employee.pageAccess.contains(componentIdentifier);
}

bool canSeeAttendance(Employee employee) =>
    canSeePage(employee, attendancePageId);
