import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';

class RedesignBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onMoneyLongPress;
  final ValueChanged<Rect>? onProfileLongPressAt;

  const RedesignBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onMoneyLongPress,
    this.onProfileLongPressAt,
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
              activeIcon: AppIcons.home_filled,
              inactiveIcon: AppIcons.home_outlined,
              isActive: currentIndex == 0,
              onTap: () => onTap(0),
            ),
            _NavItem(
              label: 'Money',
              activeIcon: AppIcons.account_balance_wallet,
              inactiveIcon: AppIcons.account_balance_wallet_outlined,
              isActive: currentIndex == 1,
              onTap: () => onTap(1),
              onLongPress: onMoneyLongPress,
            ),
            _NavItem(
              label: 'Budget',
              activeIcon: AppIcons.savings,
              inactiveIcon: AppIcons.savings_outlined,
              isActive: currentIndex == 2,
              onTap: () => onTap(2),
            ),
            _NavItem(
              label: 'Tools',
              activeIcon: AppIcons.grid_view_rounded,
              inactiveIcon: AppIcons.grid_view_outlined,
              isActive: currentIndex == 3,
              onTap: () => onTap(3),
            ),
            _NavItem(
              label: 'Profile',
              activeIcon: AppIcons.person,
              inactiveIcon: AppIcons.person_outline,
              isActive: currentIndex == 4,
              onTap: () => onTap(4),
              onLongPressAt: onProfileLongPressAt,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final String label;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<Rect>? onLongPressAt;

  const _NavItem({
    required this.label,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
    this.onLongPressAt,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    // Compress → overshoot → settle
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.78)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.78, end: 1.10)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.10, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? AppColors.primaryLight
        : AppColors.textTertiary(context);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        onLongPress: widget.onLongPress ??
            (widget.onLongPressAt == null
                ? null
                : () {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final topLeft = box.localToGlobal(Offset.zero);
                    widget.onLongPressAt!(Rect.fromLTWH(
                      topLeft.dx,
                      topLeft.dy,
                      box.size.width,
                      box.size.height,
                    ));
                  }),
        child: ScaleTransition(
          scale: _scale,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cross-fade between outline and filled icon
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Icon(
                    widget.isActive ? widget.activeIcon : widget.inactiveIcon,
                    key: ValueKey(widget.isActive),
                    size: 22,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                  child: Text(widget.label),
                ),
                const SizedBox(height: 3),
                // Active indicator pill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  width: widget.isActive ? 16 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? AppColors.primaryLight
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
