import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/theme/app_colors.dart';

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

    return Scaffold(
      backgroundColor: AppColors.slate50,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate900,
                  ),
                ),
              ),
              if (widget.showRedesignToggle && !_isLoading) ...[
                const SizedBox(height: 24),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.palette_rounded,
                          size: 20, color: AppColors.slate700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Use Redesign',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate900,
                          ),
                        ),
                      ),
                      Switch(
                        value: _useRedesign,
                        onChanged: _toggleRedesign,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
