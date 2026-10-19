import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/employee.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/access_rules.dart';
import 'attendance_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';

/// Signed-in shell.
///
/// In the web HRIS, "General Panel" is a heading in the sidebar (Sidebar.jsx),
/// not a page. Of its items only Home and Attendance are in the mobile scope
/// (Attendance only when the role or page access allows it); Profile is
/// opened from the user header at the top of the web sidebar. On mobile these
/// destinations are the app's primary navigation: a bottom navigation bar on
/// phones, and a navigation rail on wide screens (landscape, foldables).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.employee});

  final Employee employee;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

enum _Tab { home, attendance, profile }

class _HomeShellState extends State<HomeShell> {
  _Tab _tab = _Tab.home;

  List<_Tab> get _tabs => [
    _Tab.home,
    if (canSeeAttendance(widget.employee)) _Tab.attendance,
    _Tab.profile,
  ];

  void _open(_Tab tab) {
    if (_tabs.contains(tab)) setState(() => _tab = tab);
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Do you want to sign out of HRIS Mobile?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await AppScope.of(context).session.signOut();
    }
  }

  static (IconData, IconData, String) _destination(_Tab tab) => switch (tab) {
    _Tab.home => (Icons.home_outlined, Icons.home, 'Home'),
    _Tab.attendance => (
      Icons.access_time,
      Icons.access_time_filled,
      'Attendance',
    ),
    _Tab.profile => (Icons.person_outline, Icons.person, 'Profile'),
  };

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final current = tabs.contains(_tab) ? _tab : _Tab.home;
    final employee = widget.employee;
    final wide = Responsive.sizeOf(context) == WindowSize.expanded;

    final Widget body = switch (current) {
      _Tab.home => DashboardScreen(
        employee: employee,
        // The Home card never grants the full Attendance page.
        onOpenAttendance: canSeeAttendance(employee)
            ? () => _open(_Tab.attendance)
            : null,
      ),
      _Tab.attendance => AttendanceScreen(
        employee: employee,
        onReturnHome: () => _open(_Tab.home),
      ),
      _Tab.profile => ProfileScreen(employee: employee),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (current) {
          _Tab.home => 'HRIS Mobile',
          _Tab.attendance => 'My Attendance Records',
          _Tab.profile => 'Profile',
        }),
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      // One Row in both layouts, with the page keyed, so rotating the phone
      // keeps the open page and its state (e.g. an applied filter).
      body: Row(
        children: [
          if (wide) ...[
            SafeArea(
              right: false,
              bottom: false,
              child: NavigationRail(
                selectedIndex: tabs.indexOf(current),
                onDestinationSelected: (i) => _open(tabs[i]),
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.white,
                indicatorColor: AppColors.accentBorder,
                selectedIconTheme: const IconThemeData(color: AppColors.accent),
                unselectedIconTheme: const IconThemeData(
                  color: AppColors.muted,
                ),
                selectedLabelTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
                unselectedLabelTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
                destinations: [
                  for (final tab in tabs)
                    NavigationRailDestination(
                      icon: Icon(_destination(tab).$1),
                      selectedIcon: Icon(_destination(tab).$2),
                      label: Text(_destination(tab).$3),
                    ),
                ],
              ),
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.accentBorder,
            ),
          ],
          Expanded(
            key: const ValueKey('page'),
            child: SafeArea(left: !wide, top: false, bottom: wide, child: body),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tabs.indexOf(current),
              onDestinationSelected: (i) => _open(tabs[i]),
              destinations: [
                for (final tab in tabs)
                  NavigationDestination(
                    icon: Icon(_destination(tab).$1),
                    selectedIcon: Icon(_destination(tab).$2),
                    label: _destination(tab).$3,
                  ),
              ],
            ),
    );
  }
}
