import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Header used by both web dashboards (Home.jsx and HomeAdmin.jsx):
/// "Hello, {name}" with employee number • employment category • department,
/// leaving out anything that is not set.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key, required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final compact = Responsive.sizeOf(context) == WindowSize.compact;
    final details = <(IconData, String, bool)>[
      (Icons.badge_outlined, employee.employeeNumber, true),
      if ((employee.employmentCategory ?? '').trim().isNotEmpty)
        (Icons.work_outline, employee.employmentCategory!.trim(), false),
      if ((employee.departmentName ?? '').trim().isNotEmpty)
        (Icons.apartment_outlined, employee.departmentName!.trim(), false),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Responsive.cardPadding(context)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        gradient: const LinearGradient(
          colors: [Color(0xFF4A1113), AppColors.accent, AppColors.accentDark],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.wb_sunny,
                color: Color(0xFFFFF3CF),
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${employee.fullName}',
                  style: TextStyle(
                    fontSize: compact ? 16 : 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: 4,
                  children: [
                    for (final (icon, text, strong) in details)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 14,
                            color: strong
                                ? const Color(0xFFFFE0AA)
                                : Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              text,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: strong
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: strong
                                    ? const Color(0xFFFFE0AA)
                                    : Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
