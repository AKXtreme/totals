import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/providers/theme_provider.dart';

class RedesignPlaceholderPage extends StatefulWidget {
  final String title;
  final bool showRedesignToggle;

  const RedesignPlaceholderPage({
    super.key,
    required this.title,
    this.showRedesignToggle = false,
  });

  @override
  State<RedesignPlaceholderPage> createState() =>
      _RedesignPlaceholderPageState();
}

class _RedesignPlaceholderPageState extends State<RedesignPlaceholderPage> {
  bool _useRedesign = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.showRedesignToggle) _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _useRedesign = prefs.getBool('use_redesign') ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleRedesign(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_redesign', value);
    setState(() => _useRedesign = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Restart the app to apply the new design.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Preferences & settings.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 20),

              // Dark Mode toggle
              _SettingTile(
                icon: Icons.dark_mode_outlined,
                iconColor: AppColors.primaryLight,
                title: 'Dark Mode',
                subtitle: 'Switch between light and dark theme',
                trailing: Switch(
                  value: isDark,
                  onChanged: (_) => themeProvider.toggleTheme(),
                  activeColor: AppColors.primaryLight,
                ),
              ),

              // Redesign toggle
              if (widget.showRedesignToggle && !_isLoading)
                _SettingTile(
                  icon: Icons.palette_rounded,
                  iconColor: AppColors.amber,
                  title: 'Use Redesign',
                  subtitle: 'Switch to the new design system',
                  trailing: Switch(
                    value: _useRedesign,
                    onChanged: _toggleRedesign,
                    activeColor: AppColors.primaryLight,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderColor(context)),
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
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
