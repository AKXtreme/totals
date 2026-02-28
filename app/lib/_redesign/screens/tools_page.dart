import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/redesign_shell.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/screens/accounts_page.dart';
import 'package:totals/screens/verify_payments_page.dart';
import 'package:totals/screens/web_page.dart';

class RedesignToolsPage extends StatelessWidget {
  const RedesignToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.slate50,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tools',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.slate900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Handy utilities at your fingertips.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.slate500,
                ),
              ),
              const SizedBox(height: 20),
              _ToolTile(
                icon: Icons.dashboard_outlined,
                iconColor: AppColors.primaryLight,
                title: 'Web Dashboard',
                subtitle: 'View your finances in a browser',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WebPage()),
                ),
              ),
              _ToolTile(
                icon: Icons.account_balance_outlined,
                iconColor: AppColors.blue,
                title: 'Quick Accounts',
                subtitle: 'Manage linked bank accounts',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountsPage()),
                ),
              ),
              _ToolTile(
                icon: Icons.qr_code_scanner_rounded,
                iconColor: AppColors.incomeSuccess,
                title: 'Verify Payments',
                subtitle: 'Scan and verify transaction receipts',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const VerifyPaymentsPage()),
                ),
              ),
              _ToolTile(
                icon: Icons.lock_outline_rounded,
                iconColor: AppColors.amber,
                title: 'Lock App',
                subtitle: 'Require authentication to access',
                onTap: () {
                  final shell = context
                      .findAncestorStateOfType<RedesignShellState>();
                  shell?.lockApp();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.slate900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.slate400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
