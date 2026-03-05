import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/screens/categories_page.dart';
import 'package:totals/screens/notification_settings_page.dart';
import 'package:totals/screens/profile_management_page.dart';
import 'package:totals/widgets/clear_database_dialog.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/services/notification_settings_service.dart';

// ── Support links ───────────────────────────────────────────────────────────
Future<void> _openSupportLink() async {
  final uri = Uri.parse('https://jami.bio/detached');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    await launchUrl(uri);
  }
}

Future<void> _openSupportChat() async {
  final uri = Uri.parse('https://t.me/totals_chat');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    await launchUrl(uri);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Settings Page
// ═════════════════════════════════════════════════════════════════════════════

class RedesignSettingsPage extends StatefulWidget {
  const RedesignSettingsPage({super.key});

  @override
  State<RedesignSettingsPage> createState() => _RedesignSettingsPageState();
}

class _RedesignSettingsPageState extends State<RedesignSettingsPage> {
  final ProfileRepository _profileRepo = ProfileRepository();
  final DataExportImportService _exportImportService =
      DataExportImportService();

  bool _useRedesign = true;
  bool _isLoadingRedesign = true;
  bool _autoCategorizeEnabled = false;
  bool _isLoadingAutoCategorize = true;
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadRedesignSetting();
    _loadAutoCategorizeSetting();
  }

  // ── Preferences loading ─────────────────────────────────────────────────

  Future<void> _loadRedesignSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _useRedesign = prefs.getBool('use_redesign') ?? true;
        _isLoadingRedesign = false;
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
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadAutoCategorizeSetting() async {
    final enabled = await NotificationSettingsService.instance
        .isAutoCategorizeByReceiverEnabled();
    if (mounted) {
      setState(() {
        _autoCategorizeEnabled = enabled;
        _isLoadingAutoCategorize = false;
      });
    }
  }

  Future<void> _toggleAutoCategorize(bool value) async {
    setState(() => _autoCategorizeEnabled = value);
    await NotificationSettingsService.instance
        .setAutoCategorizeByReceiverEnabled(value);

    if (value && mounted) {
      final applyToExisting = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardColor(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Auto-categorize by Receiver',
            style: TextStyle(color: AppColors.textPrimary(ctx)),
          ),
          content: Text(
            'This will automatically categorize transactions based on '
            'previously categorized receivers/creditors.\n\n'
            'Apply to existing uncategorized transactions?',
            style: TextStyle(color: AppColors.textSecondary(ctx)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'No',
                style: TextStyle(color: AppColors.textSecondary(ctx)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );

      if (applyToExisting == true && mounted) {
        final provider =
            Provider.of<TransactionProvider>(context, listen: false);
        final count = await provider.applyAutoCategorizationToExisting();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Applied auto-categorization to $count transactions',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  // ── Profile ─────────────────────────────────────────────────────────────

  String _getProfileInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name[0].toUpperCase();
  }

  Future<void> _navigateToManageProfiles() async {
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileManagementPage()),
    );
    if (result == true && mounted) {
      setState(() {});
      try {
        Provider.of<TransactionProvider>(context, listen: false).loadData();
      } catch (_) {}
    }
  }

  // ── Display size sheet ──────────────────────────────────────────────────

  String _scaleLabel(double scale) {
    final formatted = scale
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '${formatted}x';
  }

  int _closestScaleIndex(double value, List<double> options) {
    int bestIndex = 0;
    double bestDelta = (value - options.first).abs();
    for (int i = 1; i < options.length; i++) {
      final delta = (value - options[i]).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<void> _showFontSizeSheet(ThemeProvider themeProvider) async {
    final initialScale = themeProvider.uiScale;
    final options = themeProvider.availableUiScales;
    int selectedIndex = _closestScaleIndex(initialScale, options);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final selectedScale = options[selectedIndex];
          Future<void> updateScale(int index) async {
            if (index == selectedIndex) return;
            setSheetState(() => selectedIndex = index);
            await themeProvider.setUiScale(options[index]);
          }

          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardColor(sheetCtx),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.slate400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Display Size',
                  style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(sheetCtx),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Preview and choose your preferred interface size.',
                  style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(sheetCtx),
                      ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor(sheetCtx),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(sheetCtx)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview',
                        style: TextStyle(
                          fontSize: 16 * selectedScale,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(sheetCtx),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Transaction categorized successfully.',
                        style: TextStyle(
                          fontSize: 13 * selectedScale,
                          color: AppColors.textSecondary(sheetCtx),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Current size: ${_scaleLabel(selectedScale)}',
                        style: TextStyle(
                          fontSize: 12 * selectedScale,
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Slider(
                  value: selectedIndex.toDouble(),
                  min: 0,
                  max: (options.length - 1).toDouble(),
                  divisions: options.length - 1,
                  label: _scaleLabel(selectedScale),
                  activeColor: AppColors.primaryLight,
                  inactiveColor: AppColors.borderColor(sheetCtx),
                  onChanged: (v) => updateScale(v.round()),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < options.length; i++)
                      ChoiceChip(
                        label: Text(_scaleLabel(options[i])),
                        selected: i == selectedIndex,
                        selectedColor:
                            AppColors.primaryLight.withValues(alpha: 0.2),
                        side: BorderSide(
                          color: i == selectedIndex
                              ? AppColors.primaryLight
                              : AppColors.borderColor(sheetCtx),
                        ),
                        labelStyle: TextStyle(
                          color: i == selectedIndex
                              ? AppColors.primaryLight
                              : AppColors.textPrimary(sheetCtx),
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => updateScale(i),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: AppColors.borderColor(sheetCtx)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                              color: AppColors.textSecondary(sheetCtx)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: AppColors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Apply',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true && mounted) {
      await themeProvider.setUiScale(initialScale);
    }
  }

  // ── Export / Import ─────────────────────────────────────────────────────

  Future<void> _exportData() async {
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardColor(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Export Data',
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          'Choose how you want to export your data:',
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save to File'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'share'),
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
          ),
        ],
      ),
    );

    if (action == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      final jsonData = await _exportImportService.exportAllData();
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final fileName = 'totals_export_$timestamp.json';

      if (action == 'save') {
        if (Platform.isAndroid) {
          try {
            final directory = Directory('/storage/emulated/0/Download');
            if (await directory.exists()) {
              final file = File('${directory.path}/$fileName');
              await file.writeAsString(jsonData);
              if (mounted) _showSnack('Data saved to Downloads folder');
            } else {
              final appDir = await getApplicationDocumentsDirectory();
              final file = File('${appDir.path}/$fileName');
              await file.writeAsString(jsonData);
              if (mounted)
                _showSnack('Data saved to: ${appDir.path}/$fileName');
            }
          } catch (_) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/$fileName');
            await tempFile.writeAsString(jsonData);
            if (mounted) {
              await Share.shareXFiles(
                [XFile(tempFile.path)],
                text: 'Totals Data Export',
                subject: 'Totals Backup',
              );
              if (mounted) _showSnack('Use Share to save the file');
            }
          }
        } else {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$fileName');
          await tempFile.writeAsString(jsonData);
          if (!mounted) return;

          String? result;
          try {
            result = await FilePicker.platform.saveFile(
              dialogTitle: 'Save Export File',
              fileName: fileName,
              type: FileType.custom,
              allowedExtensions: ['json'],
            );
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            try {
              if (await tempFile.exists()) await tempFile.delete();
            } catch (_) {}
            if (mounted) _showErrorSnack('Failed to open file picker: $e');
            return;
          }

          if (!mounted) {
            try {
              if (await tempFile.exists()) await tempFile.delete();
            } catch (_) {}
            return;
          }

          if (result != null && result.isNotEmpty) {
            try {
              await tempFile.copy(result);
              try {
                if (await tempFile.exists()) await tempFile.delete();
              } catch (_) {}
              if (mounted) _showSnack('Data saved successfully');
            } catch (_) {
              try {
                await File(result).writeAsString(jsonData);
                try {
                  if (await tempFile.exists()) await tempFile.delete();
                } catch (_) {}
                if (mounted) _showSnack('Data saved successfully');
              } catch (writeErr) {
                try {
                  if (await tempFile.exists()) await tempFile.delete();
                } catch (_) {}
                if (mounted) _showErrorSnack('Failed to save file: $writeErr');
              }
            }
          } else {
            try {
              if (await tempFile.exists()) await tempFile.delete();
            } catch (_) {}
          }
        }
      } else {
        // Share
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsString(jsonData);
        if (!mounted) return;
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Totals Data Export',
          subject: 'Totals Backup',
        );
        if (mounted) _showSnack('Data exported successfully');
      }
    } catch (e) {
      if (mounted) _showErrorSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importData() async {
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonData = await file.readAsString();

        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardColor(ctx),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Import Data',
              style: TextStyle(color: AppColors.textPrimary(ctx)),
            ),
            content: Text(
              'This will add the imported data to your existing data. '
              'Duplicates will be skipped.',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary(ctx)),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Import'),
              ),
            ],
          ),
        );

        if (confirmed == true && mounted) {
          await _exportImportService.importAllData(jsonData);
          if (mounted) {
            Provider.of<TransactionProvider>(context, listen: false).loadData();
            _showSnack('Data imported successfully');
          }
        }
      }
    } catch (e) {
      if (mounted) _showErrorSnack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.phone_iphone_rounded;
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
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

              // ── Profile card ────────────────────────────────────────────
              FutureBuilder(
                future: _profileRepo.getActiveProfile(),
                builder: (context, snapshot) {
                  final name = snapshot.data?.name ?? 'Personal';
                  final initials = _getProfileInitials(name);
                  return _ProfileCard(
                    name: name,
                    initials: initials,
                    onTap: _navigateToManageProfiles,
                  );
                },
              ),
              const SizedBox(height: 24),

              // ── Preferences ─────────────────────────────────────────────
              _SectionHeader(label: 'Preferences'),
              const SizedBox(height: 10),

              _SettingTile(
                icon: Icons.palette_outlined,
                iconColor: AppColors.primaryLight,
                title: 'Theme',
                subtitle: 'Tap to cycle: System, Light, Dark',
                trailing: OutlinedButton.icon(
                  onPressed: themeProvider.cycleThemeMode,
                  icon: Icon(
                    _themeModeIcon(themeProvider.themeMode),
                    size: 16,
                    color: AppColors.primaryLight,
                  ),
                  label: Text(
                    themeProvider.themeModeLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 34),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    side: BorderSide(color: AppColors.borderColor(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                onTap: themeProvider.cycleThemeMode,
              ),

              _SettingTile(
                icon: Icons.zoom_out_map_rounded,
                iconColor: AppColors.incomeSuccess,
                title: 'Display Size',
                subtitle: 'Preview and adjust interface scale',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      themeProvider.uiScaleLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.textTertiary(context),
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => _showFontSizeSheet(themeProvider),
              ),

              // if (!_isLoadingRedesign)
              //   _SettingTile(
              //     icon: Icons.palette_rounded,
              //     iconColor: AppColors.amber,
              //     title: 'Use Redesign',
              //     subtitle: 'Switch to the new design system',
              //     trailing: Switch(
              //       value: _useRedesign,
              //       onChanged: _toggleRedesign,
              //       activeColor: AppColors.primaryLight,
              //     ),
              //   ),

              _SettingTile(
                icon: Icons.toc_rounded,
                iconColor: AppColors.blue,
                title: 'Categories',
                subtitle: 'Manage transaction categories',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CategoriesPage()),
                ),
              ),

              // if (!_isLoadingAutoCategorize)
              //   _SettingTile(
              //     icon: Icons.category,
              //     iconColor: const Color(0xFFEC4899),
              //     title: 'Auto-categorize',
              //     subtitle: 'Categorize by receiver automatically',
              //     trailing: Switch(
              //       value: _autoCategorizeEnabled,
              //       onChanged: _toggleAutoCategorize,
              //       activeColor: AppColors.primaryLight,
              //     ),
              //   ),

              _SettingTile(
                icon: Icons.notifications_outlined,
                iconColor: AppColors.amber,
                title: 'Notifications',
                subtitle: 'Daily summary and budget alerts',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsPage(),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Data ────────────────────────────────────────────────────
              _SectionHeader(label: 'Data'),
              const SizedBox(height: 10),

              _SettingTile(
                icon: Icons.upload_rounded,
                iconColor: AppColors.incomeSuccess,
                title: 'Export Data',
                subtitle: 'Save or share a backup',
                trailing: _isExporting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryLight,
                        ),
                      )
                    : null,
                onTap: _isExporting ? null : _exportData,
              ),

              _SettingTile(
                icon: Icons.download_rounded,
                iconColor: AppColors.blue,
                title: 'Import Data',
                subtitle: 'Restore from a backup file',
                trailing: _isImporting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryLight,
                        ),
                      )
                    : null,
                onTap: _isImporting ? null : _importData,
              ),

              _SettingTile(
                icon: Icons.delete_outline_rounded,
                iconColor: AppColors.red,
                title: 'Clear Data',
                subtitle: 'Delete selected app data',
                onTap: () => showClearDatabaseDialog(context),
              ),

              const SizedBox(height: 24),

              // ── Support ─────────────────────────────────────────────────
              _SectionHeader(label: 'Support'),
              const SizedBox(height: 10),

              _SettingTile(
                icon: Icons.info_outline_rounded,
                iconColor: AppColors.primaryLight,
                title: 'About',
                subtitle: 'Version, privacy and credits',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _RedesignAboutPage(),
                  ),
                ),
              ),

              _SettingTile(
                icon: Icons.help_outline_rounded,
                iconColor: AppColors.incomeSuccess,
                title: 'Help & FAQ',
                subtitle: 'Common questions answered',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _RedesignFAQPage(),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Support Developers ──────────────────────────────────────
              _SupportDevelopersCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.textTertiary(context),
            ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String initials;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.name,
    required this.initials,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage profiles',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary(context),
                size: 22,
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
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
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
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary(context),
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

class _SupportDevelopersCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _openSupportLink,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                AppColors.primaryDark.withValues(alpha: 0.12),
                AppColors.primaryLight.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: AppColors.primaryLight.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.favorite_rounded,
                color: AppColors.primaryLight,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Support the Developers',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// About Page
// ═════════════════════════════════════════════════════════════════════════════

class _RedesignAboutPage extends StatelessWidget {
  const _RedesignAboutPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'About',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          children: [
            // Hero card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.cardColor(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Column(
                children: [
                  Text(
                    'Totals',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Version 1.1.0',
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Image.asset(
                    'assets/images/detached_logo.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'by detached',
                    style: theme.textTheme.labelLarge?.copyWith(
                      letterSpacing: 1.0,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A personal finance tracker that keeps your bank '
                    'activity organized, searchable, and easy to understand.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary(context),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _FeatureChip(
                          icon: Icons.lock_outline_rounded, label: 'Private'),
                      _FeatureChip(icon: Icons.bolt_rounded, label: 'Fast'),
                      _FeatureChip(
                          icon: Icons.auto_graph_rounded, label: 'Insightful'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Support card
            Material(
              color: AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: _openSupportLink,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: AppColors.primaryLight,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Support the devs',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Help us keep improving Totals.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textTertiary(context),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primaryLight.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primaryLight),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FAQ Page
// ═════════════════════════════════════════════════════════════════════════════

class _RedesignFAQPage extends StatefulWidget {
  const _RedesignFAQPage();

  @override
  State<_RedesignFAQPage> createState() => _RedesignFAQPageState();
}

class _RedesignFAQPageState extends State<_RedesignFAQPage> {
  final Map<int, bool> _expanded = {};

  static const List<Map<String, String>> _faqs = [
    {
      'question': 'How do I export my data?',
      'answer':
          'Go to Settings > Export Data. You can choose to save the file directly or share it with other apps.',
    },
    {
      'question': 'How do I categorize transactions?',
      'answer':
          'Tap on any transaction in your transaction list and select a category from the list that appears.',
    },
    {
      'question': 'Can I import data from another device?',
      'answer':
          'Yes! Use the Export Data feature to create a backup file, then use Import Data on your other device to restore it.',
    },
    {
      'question': 'My SMS is not parsed. How can I parse it?',
      'answer':
          'Open the Failed Parses page and retry parsing the message from there. It is the button next to the lock button on the home page.',
    },
    {
      'question': 'Skipped a transaction today?',
      'answer':
          "In Today's transactions, tap the refresh button to rescan today's bank SMS to add anything that was missed.",
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Help & FAQ',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          children: [
            // Intro card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.cardColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      color: AppColors.primaryLight,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick answers',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap a question to reveal the details.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // FAQ items
            ...List.generate(_faqs.length, (i) {
              final isExpanded = _expanded[i] ?? false;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: AppColors.cardColor(context),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => setState(() => _expanded[i] = !isExpanded),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: AppColors.borderColor(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: AppColors.primaryLight,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _faqs[i]['question']!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary(context),
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.keyboard_arrow_down,
                                  color: AppColors.primaryLight,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Padding(
                              padding: const EdgeInsets.only(
                                  left: 40, top: 10, right: 4),
                              child: Text(
                                _faqs[i]['answer']!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary(context),
                                  height: 1.5,
                                ),
                              ),
                            ),
                            crossFadeState: isExpanded
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 200),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 16),

            // Contact card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.cardColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Still need help?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Reach out to detached and we will point you in the '
                    'right direction.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _openSupportChat,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryLight,
                        side: const BorderSide(color: AppColors.primaryLight),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Contact us',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
