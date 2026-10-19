import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/employee.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';

/// Read-only employee information: the web "Profile" page
/// (DASHBOARD/Profile.jsx), limited to identity and work details.
///
/// The web Profile also shows the full Personal Data Sheet (birth details,
/// government ID numbers, addresses, family, education). Those are sensitive
/// and are deliberately not shown in the mobile app.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<Employee>? _profile;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _profile ??= _load();
  }

  // Always the signed-in employee's own record.
  Future<Employee> _load() =>
      AppScope.of(context).repository
          .fetchEmployee(widget.employee.employeeNumber);

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _profile = next;
    });
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMock = AppScope.of(context).repository.isMock;
    return FutureBuilder<Employee>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingView(message: 'Loading...');
        }
        if (snapshot.hasError) {
          return CenteredScroll(
            child: MessageView(
              icon: Icons.error_outline,
              title: 'Failed to load profile.',
              color: AppColors.errorFg,
              action: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ),
          );
        }
        final e = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: Responsive.pagePadding(
              context,
              top: Responsive.gutter(context),
              bottom: AppSpacing.xl,
            ),
            children: [
              if (isMock) ...[
                const MockNotice(
                  message:
                      'Fictional sample employee. Not connected to the HRIS.',
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _ProfileHeader(employee: e),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Personal Information',
                icon: Icons.person_outline,
                child: Column(
                  children: [
                    InfoRow(label: 'First Name', value: orEmpty(e.firstName)),
                    InfoRow(label: 'Middle Name', value: orEmpty(e.middleName)),
                    InfoRow(label: 'Last Name', value: orEmpty(e.lastName)),
                    InfoRow(
                      label: 'Name Extension',
                      value: orEmpty(e.nameExtension),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Contact & Address',
                icon: Icons.contact_mail_outlined,
                child: InfoRow(label: 'Email Address', value: orEmpty(e.email)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Web Profile header: name, employee number and email, plus the employment
/// category and department shown in the web dashboard greeting.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final e = employee;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(Responsive.cardPadding(context)),
        child: Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.accent,
              child: Text(
                e.initials,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              e.fullName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Employee Profile',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            InfoRow(label: 'Employee Number', value: e.employeeNumber),
            InfoRow(
              label: 'Employment Category',
              value: orEmpty(e.employmentCategory),
            ),
            InfoRow(label: 'Department', value: orEmpty(e.departmentName)),
          ],
        ),
      ),
    );
  }
}
