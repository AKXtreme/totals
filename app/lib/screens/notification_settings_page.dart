import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shown
                ? 'Test summary notification sent'
                : 'Unable to send notification',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send test notification')),
      );
    }
  }

  String _nextDailySummaryLabel(BuildContext context) {
    final now = DateTime.now();
    final last = _lastDailySummarySentAt;
    final sentToday = last != null && _isSameDay(last, now);

    final scheduledToday = DateTime(
        now.year, now.month, now.day, _dailyTime.hour, _dailyTime.minute);

    if (sentToday) {
      final tomorrow = scheduledToday.add(const Duration(days: 1));
      final timeLabel = TimeOfDay.fromDateTime(tomorrow).format(context);
      return 'Tomorrow at $timeLabel';
    }

    if (scheduledToday.isAfter(now)) {
      return 'Today at ${_dailyTime.format(context)}';
    }

    return 'Sending soon';
  }

  String _lastDailySummaryLabel(BuildContext context) {
    final last = _lastDailySummarySentAt;
    if (last == null) return 'Not sent yet';

    final now = DateTime.now();
    final dayLabel = _isSameDay(last, now)
        ? 'Today'
        : DateFormat('MMM dd, yyyy').format(last);
    final timeLabel = DateFormat('hh:mm a').format(last);
    return '$dayLabel at $timeLabel';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<Category> _categoriesForFlow(String flow) {
    return _allCategories
        .where((c) => c.flow.toLowerCase() == flow && !c.uncategorized)
        .toList();
  }

  List<Category> _selectedCategoriesFor(String flow) {
    final ids = flow == 'income' ? _quickIncomeIds : _quickExpenseIds;
    return ids
        .map((id) => _allCategories.where((c) => c.id == id).firstOrNull)
        .whereType<Category>()
        .toList();
  }

  Future<void> _openQuickCategoryPicker(String flow) async {
    final available = _categoriesForFlow(flow);
    final currentIds =
        flow == 'income' ? List<int>.from(_quickIncomeIds) : List<int>.from(_quickExpenseIds);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        flow == 'income'
                            ? 'Quick categories for income'
                            : 'Quick categories for expenses',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Select up to 3 categories',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: available.length,
                        itemBuilder: (ctx, index) {
                          final cat = available[index];
                          final selected = currentIds.contains(cat.id);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (val) {
                              if (val == true && cat.id != null) {
                                if (currentIds.length >= 3) return;
                                setSheetState(() => currentIds.add(cat.id!));
                              } else if (cat.id != null) {
                                setSheetState(() => currentIds.remove(cat.id!));
                              }
                            },
                            secondary: Icon(iconForCategoryKey(cat.iconKey)),
                            title: Text(cat.name),
                            controlAffinity: ListTileControlAffinity.trailing,
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              if (flow == 'income') {
                                setState(() => _quickIncomeIds = currentIds);
                                await NotificationSettingsService.instance
                                    .setQuickCategorizeIncomeIds(currentIds);
                              } else {
                                setState(() => _quickExpenseIds = currentIds);
                                await NotificationSettingsService.instance
                                    .setQuickCategorizeExpenseIds(currentIds);
                              }
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickCategoryChips(String flow) {
    final selected = _selectedCategoriesFor(flow);
    if (selected.isEmpty) {
      return Text(
        'None selected',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: selected.map((cat) {
        return Chip(
          avatar: Icon(
            iconForCategoryKey(cat.iconKey),
            size: 18,
          ),
          label: Text(cat.name),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;

    if (!mounted) return;

    if (status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Notifications permission already granted')),
      );
      return;
    }

    if (status.isPermanentlyDenied) {
      final opened = await openAppSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Open Settings to enable notifications'
                : 'Enable notifications in system settings',
          ),
        ),
      );
      return;
    }

    final requested = await Permission.notification.request();
    if (!mounted) return;

    if (requested.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications enabled')),
      );
    } else if (requested.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifications are blocked; enable them in Settings'),
        ),
      );
      await openAppSettings();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications permission denied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile(
                    value: _transactionEnabled,
                    onChanged: _setTransactionEnabled,
                    title: const Text('Transaction alerts'),
                    subtitle:
                        const Text('Notify when a new transaction is detected'),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'Quick categorize',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    enabled: _transactionEnabled,
                    leading: const Icon(Icons.arrow_downward_rounded),
                    title: const Text('Income notifications'),
                    subtitle: _buildQuickCategoryChips('income'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _transactionEnabled
                        ? () => _openQuickCategoryPicker('income')
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    enabled: _transactionEnabled,
                    leading: const Icon(Icons.arrow_upward_rounded),
                    title: const Text('Expense notifications'),
                    subtitle: _buildQuickCategoryChips('expense'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _transactionEnabled
                        ? () => _openQuickCategoryPicker('expense')
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: SwitchListTile(
                    value: _budgetEnabled,
                    onChanged: _setBudgetEnabled,
                    title: const Text('Budget alerts'),
                    subtitle:
                        const Text('Notify when budget limits are reached'),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    value: _dailyEnabled,
                    onChanged: _setDailyEnabled,
                    title: const Text("Day's summary"),
                    subtitle:
                        const Text("Daily 'Today's spending' notification"),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    enabled: _dailyEnabled,
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Summary time'),
                    subtitle: Text(_dailyTime.format(context)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _dailyEnabled ? _pickDailyTime : null,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.widgets_rounded),
                    title: const Text('Widget refresh time'),
                    subtitle: Text(_widgetRefreshTime.format(context)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickWidgetRefreshTime,
                  ),
                ),
                // const SizedBox(height: 8),
                // Card(
                //   child: ListTile(
                //     enabled: _dailyEnabled,
                //     leading: const Icon(Icons.event_available_rounded),
                //     title: const Text('Next summary'),
                //     subtitle: Text(
                //       _dailyEnabled ? _nextDailySummaryLabel(context) : 'Off',
                //     ),
                //   ),
                // ),
                // const SizedBox(height: 8),
                // Card(
                //   child: ListTile(
                //     enabled: _dailyEnabled,
                //     leading: const Icon(Icons.history_rounded),
                //     title: const Text('Last sent'),
                //     subtitle: Text(
                //       _dailyEnabled ? _lastDailySummaryLabel(context) : 'Off',
                //     ),
                //   ),
                // ),
                // const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    enabled: _dailyEnabled,
                    leading: const Icon(Icons.notification_add_rounded),
                    title: const Text('Send test summary'),
                    subtitle:
                        const Text('Send a sample summary notification now'),
                    onTap: _dailyEnabled ? _sendTestDailySummary : null,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notifications_active_rounded),
                    title: const Text('Request permission'),
                    subtitle:
                        const Text('If notifications are blocked, enable them'),
                    onTap: () {
                      _requestNotificationPermission();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Note: delivery time depends on your phone's battery optimization.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}
