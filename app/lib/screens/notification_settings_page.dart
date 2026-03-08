import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/models/category.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_scheduler.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/widget_refresh_scheduler.dart';
import 'package:totals/services/widget_refresh_settings_service.dart';
import 'package:totals/services/widget_refresh_state_service.dart';
import 'package:totals/utils/category_icons.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _loading = true;
  bool _transactionEnabled = true;
  bool _budgetEnabled = true;
  bool _dailyEnabled = true;
  TimeOfDay _dailyTime = const TimeOfDay(hour: 20, minute: 0);
  TimeOfDay _widgetRefreshTime = const TimeOfDay(hour: 0, minute: 0);
  DateTime? _lastDailySummarySentAt;
  List<Category> _allCategories = [];
  List<int> _quickIncomeIds = [];
  List<int> _quickExpenseIds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = NotificationSettingsService.instance;
    final tx = await settings.isTransactionNotificationsEnabled();
    final budget = await settings.isBudgetAlertsEnabled();
    final daily = await settings.isDailySummaryEnabled();
    final time = await settings.getDailySummaryTime();
    final widgetTime =
        await WidgetRefreshSettingsService.instance.getWidgetRefreshTime();
    final lastSent = await settings.getDailySummaryLastSentAt();
    final categories = await CategoryRepository().getCategories();
    final incomeIds = await settings.getQuickCategorizeIncomeIds();
    final expenseIds = await settings.getQuickCategorizeExpenseIds();
    if (!mounted) return;
    setState(() {
      _transactionEnabled = tx;
      _budgetEnabled = budget;
      _dailyEnabled = daily;
      _dailyTime = time;
      _widgetRefreshTime = widgetTime;
      _lastDailySummarySentAt = lastSent;
      _allCategories = categories;
      _quickIncomeIds = incomeIds;
      _quickExpenseIds = expenseIds;
      _loading = false;
    });
  }

  // ── Setters ─────────────────────────────────────────────────────────────

  Future<void> _setTransactionEnabled(bool value) async {
    setState(() => _transactionEnabled = value);
    await NotificationSettingsService.instance
        .setTransactionNotificationsEnabled(value);
  }

  Future<void> _setBudgetEnabled(bool value) async {
    setState(() => _budgetEnabled = value);
    await NotificationSettingsService.instance.setBudgetAlertsEnabled(value);
  }

  Future<void> _setDailyEnabled(bool value) async {
    setState(() => _dailyEnabled = value);
    await NotificationSettingsService.instance.setDailySummaryEnabled(value);
    await NotificationScheduler.syncDailySummarySchedule();
    await _load();
  }

  Future<void> _pickDailyTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dailyTime,
    );
    if (picked == null) return;
    setState(() => _dailyTime = picked);
    await NotificationSettingsService.instance.setDailySummaryTime(picked);
    await NotificationScheduler.syncDailySummarySchedule();
    await _load();
  }

  Future<void> _pickWidgetRefreshTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _widgetRefreshTime,
    );
    if (picked == null) return;
    setState(() => _widgetRefreshTime = picked);
    await WidgetRefreshSettingsService.instance.setWidgetRefreshTime(picked);
    await WidgetRefreshStateService.instance.clearLastRefreshAt();
    await WidgetRefreshScheduler.syncWidgetRefreshSchedule();
    await _load();
  }

  Future<void> _sendTestDailySummary() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      final txRepo = TransactionRepository();
      final debits = await txRepo.getTransactionsByDateRange(
        start,
        end,
        type: 'DEBIT',
      );
      final totalSpent = debits.fold<double>(0.0, (sum, t) => sum + t.amount);
      final shown =
          await NotificationService.instance.showDailySpendingTestNotification(
        amount: totalSpent,
      );

      if (!mounted) return;
      _showSnack(
        shown
            ? 'Test summary notification sent'
            : 'Unable to send notification',
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to send test notification');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Category> _categoriesForFlow(String flow) =>
      _allCategories
          .where((c) => c.flow.toLowerCase() == flow && !c.uncategorized)
          .toList();

  List<Category> _selectedCategoriesFor(String flow) {
    final ids = flow == 'income' ? _quickIncomeIds : _quickExpenseIds;
    return ids
        .map((id) => _allCategories.where((c) => c.id == id).firstOrNull)
        .whereType<Category>()
        .toList();
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

  // ── Quick category picker sheet ─────────────────────────────────────────

  Future<void> _openQuickCategoryPicker(String flow) async {
    final available = _categoriesForFlow(flow);
    final currentIds = flow == 'income'
        ? List<int>.from(_quickIncomeIds)
        : List<int>.from(_quickExpenseIds);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardColor(ctx),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
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
                    flow == 'income'
                        ? 'Quick Income Categories'
                        : 'Quick Expense Categories',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(ctx),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select up to 3 categories for quick actions',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(ctx),
                        ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: available.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final cat = available[index];
                        final selected = currentIds.contains(cat.id);
                        final atLimit =
                            currentIds.length >= 3 && !selected;

                        return Material(
                          color: selected
                              ? AppColors.primaryLight
                                  .withValues(alpha: 0.08)
                              : AppColors.surfaceColor(ctx),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: atLimit
                                ? null
                                : () {
                                    if (cat.id == null) return;
                                    if (selected) {
                                      setSheetState(
                                          () => currentIds.remove(cat.id!));
                                    } else {
                                      setSheetState(
                                          () => currentIds.add(cat.id!));
                                    }
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primaryLight
                                      : AppColors.borderColor(ctx),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: (selected
                                              ? AppColors.primaryLight
                                              : AppColors.textTertiary(ctx))
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      iconForCategoryKey(cat.iconKey),
                                      size: 18,
                                      color: selected
                                          ? AppColors.primaryLight
                                          : AppColors.textSecondary(ctx),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      cat.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: atLimit
                                            ? AppColors.textTertiary(ctx)
                                            : AppColors.textPrimary(ctx),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: selected
                                          ? AppColors.primaryLight
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.primaryLight
                                            : AppColors.textTertiary(ctx),
                                        width: 2,
                                      ),
                                    ),
                                    child: selected
                                        ? const Icon(
                                            Icons.check_rounded,
                                            size: 14,
                                            color: AppColors.white,
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: AppColors.borderColor(ctx)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                                color: AppColors.textSecondary(ctx)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            if (flow == 'income') {
                              setState(
                                  () => _quickIncomeIds = currentIds);
                              await NotificationSettingsService.instance
                                  .setQuickCategorizeIncomeIds(
                                      currentIds);
                            } else {
                              setState(
                                  () => _quickExpenseIds = currentIds);
                              await NotificationSettingsService.instance
                                  .setQuickCategorizeExpenseIds(
                                      currentIds);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Save',
                            style:
                                TextStyle(fontWeight: FontWeight.w700),
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
        );
      },
    );
  }

  // ── Permission ──────────────────────────────────────────────────────────

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (!mounted) return;

    if (status.isGranted) {
      _showSnack('Notifications permission already granted');
      return;
    }

    if (status.isPermanentlyDenied) {
      final opened = await openAppSettings();
      if (!mounted) return;
      _showSnack(
        opened
            ? 'Open Settings to enable notifications'
            : 'Enable notifications in system settings',
      );
      return;
    }

    final requested = await Permission.notification.request();
    if (!mounted) return;

    if (requested.isGranted) {
      _showSnack('Notifications enabled');
    } else if (requested.isPermanentlyDenied) {
      _showSnack('Notifications are blocked; enable them in Settings');
      await openAppSettings();
    } else {
      _showSnack('Notifications permission denied');
    }
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (!mounted) return;

    if (status.isGranted) {
      _showSnack('Already excluded from battery optimization');
      return;
    }

    final result = await Permission.ignoreBatteryOptimizations.request();
    if (!mounted) return;

    if (result.isGranted) {
      _showSnack('Battery optimization disabled for Totals');
    } else {
      _showSnack('Battery optimization exemption denied');
    }
  }

  // ── Quick category chips ────────────────────────────────────────────────

  Widget _buildQuickCategoryChips(String flow) {
    final selected = _selectedCategoriesFor(flow);
    if (selected.isEmpty) {
      return Text(
        'None selected',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textTertiary(context),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: selected.map((cat) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                iconForCategoryKey(cat.iconKey),
                size: 14,
                color: AppColors.primaryLight,
              ),
              const SizedBox(width: 4),
              Text(
                cat.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLight,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

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
          'Notifications',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryLight,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Alerts ──────────────────────────────────────────
                  _SectionHeader(label: 'Alerts'),
                  const SizedBox(height: 10),

                  _SettingTile(
                    icon: Icons.swap_vert_rounded,
                    iconColor: AppColors.primaryLight,
                    title: 'Transaction alerts',
                    subtitle: 'Notify when a new transaction is detected',
                    trailing: Switch(
                      value: _transactionEnabled,
                      onChanged: _setTransactionEnabled,
                      activeColor: AppColors.primaryLight,
                    ),
                  ),

                  _SettingTile(
                    icon: Icons.pie_chart_outline_rounded,
                    iconColor: AppColors.amber,
                    title: 'Budget alerts',
                    subtitle: 'Notify when budget limits are reached',
                    trailing: Switch(
                      value: _budgetEnabled,
                      onChanged: _setBudgetEnabled,
                      activeColor: AppColors.primaryLight,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Quick categorize ────────────────────────────────
                  _SectionHeader(label: 'Quick Categorize'),
                  const SizedBox(height: 10),

                  _SettingTile(
                    icon: Icons.arrow_downward_rounded,
                    iconColor: AppColors.incomeSuccess,
                    title: 'Income categories',
                    subtitle: null,
                    customSubtitle: _buildQuickCategoryChips('income'),
                    enabled: _transactionEnabled,
                    onTap: _transactionEnabled
                        ? () => _openQuickCategoryPicker('income')
                        : null,
                  ),

                  _SettingTile(
                    icon: Icons.arrow_upward_rounded,
                    iconColor: AppColors.red,
                    title: 'Expense categories',
                    subtitle: null,
                    customSubtitle: _buildQuickCategoryChips('expense'),
                    enabled: _transactionEnabled,
                    onTap: _transactionEnabled
                        ? () => _openQuickCategoryPicker('expense')
                        : null,
                  ),

                  const SizedBox(height: 20),

                  // ── Daily summary ───────────────────────────────────
                  _SectionHeader(label: 'Daily Summary'),
                  const SizedBox(height: 10),

                  _SettingTile(
                    icon: Icons.summarize_outlined,
                    iconColor: AppColors.blue,
                    title: "Day's summary",
                    subtitle: "Daily 'Today's spending' notification",
                    trailing: Switch(
                      value: _dailyEnabled,
                      onChanged: _setDailyEnabled,
                      activeColor: AppColors.primaryLight,
                    ),
                  ),

                  _SettingTile(
                    icon: Icons.schedule_rounded,
                    iconColor: AppColors.primaryLight,
                    title: 'Summary time',
                    subtitle: _dailyTime.format(context),
                    enabled: _dailyEnabled,
                    onTap: _dailyEnabled ? _pickDailyTime : null,
                  ),

                  _SettingTile(
                    icon: Icons.notification_add_rounded,
                    iconColor: AppColors.incomeSuccess,
                    title: 'Send test summary',
                    subtitle: 'Send a sample summary notification now',
                    enabled: _dailyEnabled,
                    onTap: _dailyEnabled ? _sendTestDailySummary : null,
                  ),

                  const SizedBox(height: 20),

                  // ── Widget ──────────────────────────────────────────
                  _SectionHeader(label: 'Widget'),
                  const SizedBox(height: 10),

                  _SettingTile(
                    icon: Icons.widgets_outlined,
                    iconColor: AppColors.amber,
                    title: 'Widget refresh time',
                    subtitle: _widgetRefreshTime.format(context),
                    onTap: _pickWidgetRefreshTime,
                  ),

                  const SizedBox(height: 20),

                  // ── Permissions ─────────────────────────────────────
                  _SectionHeader(label: 'Permissions'),
                  const SizedBox(height: 10),

                  _SettingTile(
                    icon: Icons.notifications_active_outlined,
                    iconColor: AppColors.primaryLight,
                    title: 'Request permission',
                    subtitle: 'Enable notifications if blocked',
                    onTap: _requestNotificationPermission,
                  ),

                  _SettingTile(
                    icon: Icons.battery_saver_rounded,
                    iconColor: AppColors.incomeSuccess,
                    title: 'Battery optimization',
                    subtitle:
                        'Exclude from battery optimization to ensure '
                        'background notifications are delivered',
                    onTap: _requestBatteryOptimizationExemption,
                  ),
                ],
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppColors.textTertiary(context),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? customSubtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.customSubtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opacity = enabled ? 1.0 : 0.45;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: opacity,
        child: Material(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.borderColor(context)),
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
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (customSubtitle != null) ...[
                          const SizedBox(height: 6),
                          customSubtitle!,
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null)
                    trailing!
                  else if (onTap != null && enabled)
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
      ),
    );
  }
}
