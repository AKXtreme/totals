import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';

class RedesignBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const RedesignBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          border: Border(top: BorderSide(color: AppColors.borderColor(context))),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _NavItem(
              label: 'Home',
              activeIcon: Icons.home_filled,
              inactiveIcon: Icons.home_outlined,
              isActive: currentIndex == 0,
              onTap: () => onTap(0),
            ),
            _NavItem(
              label: 'Money',
              activeIcon: Icons.account_balance_wallet,
              inactiveIcon: Icons.account_balance_wallet_outlined,
              isActive: currentIndex == 1,
              onTap: () => onTap(1),
            ),
            _NavItem(
              label: 'Budget',
              activeIcon: Icons.savings,
              inactiveIcon: Icons.savings_outlined,
              isActive: currentIndex == 2,
              onTap: () => onTap(2),
            ),
            _NavItem(
              label: 'Tools',
              activeIcon: Icons.grid_view_rounded,
              inactiveIcon: Icons.grid_view_outlined,
              isActive: currentIndex == 3,
              onTap: () => onTap(3),
            ),
            _NavItem(
              label: 'Profile',
              activeIcon: Icons.person,
              inactiveIcon: Icons.person_outline,
              isActive: currentIndex == 4,
              onTap: () => onTap(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? AppColors.primaryLight
        : AppColors.textTertiary(context);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isActive ? activeIcon : inactiveIcon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
