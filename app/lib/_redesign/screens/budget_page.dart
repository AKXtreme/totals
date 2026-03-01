import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/utils/text_utils.dart';

class RedesignBudgetPage extends StatefulWidget {
  const RedesignBudgetPage({super.key});

  @override
  State<RedesignBudgetPage> createState() => _RedesignBudgetPageState();
}

class _RedesignBudgetPageState extends State<RedesignBudgetPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bp = Provider.of<BudgetProvider>(context, listen: false);
      final tp = Provider.of<TransactionProvider>(context, listen: false);
      bp.setTransactionProvider(tp);
      bp.loadBudgets();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BudgetProvider, TransactionProvider>(
      builder: (context, budgetProvider, transactionProvider, _) {
        final statuses = budgetProvider.budgetStatuses;
        final isLoading = budgetProvider.isLoading;

        return Scaffold(
          backgroundColor: AppColors.background(context),
          body: SafeArea(
            child: RefreshIndicator(
              color: AppColors.primaryLight,
              onRefresh: budgetProvider.loadBudgets,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BudgetHeader(
                      onAdd: () => _openBudgetForm(
                        budgetProvider: budgetProvider,
                        transactionProvider: transactionProvider,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isLoading)
                      const _BudgetLoadingShimmer()
                    else if (statuses.isEmpty)
                      _BudgetEmptyState(
                        onCreateTap: () => _openBudgetForm(
                          budgetProvider: budgetProvider,
                          transactionProvider: transactionProvider,
                        ),
                      )
                    else ...[
                      _BudgetOverviewCard(statuses: statuses),
                      const SizedBox(height: 20),
                      Text(
                        'Your budgets',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary(context),
                            ),
                      ),
                      const SizedBox(height: 10),
                      ...statuses.map(
                        (status) => _BudgetCard(
                          status: status,
                          transactionProvider: transactionProvider,
                          onTap: () => _openBudgetDetail(
                            status: status,
                            budgetProvider: budgetProvider,
                            transactionProvider: transactionProvider,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 96),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openBudgetForm({
    required BudgetProvider budgetProvider,
    required TransactionProvider transactionProvider,
    Budget? existing,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetFormSheet(
        budgetProvider: budgetProvider,
        transactionProvider: transactionProvider,
        existing: existing,
      ),
    );
  }

  void _openBudgetDetail({
    required BudgetStatus status,
    required BudgetProvider budgetProvider,
    required TransactionProvider transactionProvider,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetDetailSheet(
        status: status,
        budgetProvider: budgetProvider,
        transactionProvider: transactionProvider,
        onEdit: () {
          Navigator.of(context).pop();
          _openBudgetForm(
            budgetProvider: budgetProvider,
            transactionProvider: transactionProvider,
            existing: status.budget,
          );
        },
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _BudgetHeader extends StatelessWidget {
  final VoidCallback onAdd;

  const _BudgetHeader({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Budget',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Track your spending limits.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          width: 40,
          child: IconButton(
            onPressed: onAdd,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add, size: 20),
          ),
        ),
      ],
    );
  }
}

// ── Loading shimmer ─────────────────────────────────────────────────────────

class _BudgetLoadingShimmer extends StatelessWidget {
  const _BudgetLoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.cardColor(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 14,
                width: 120,
                decoration: BoxDecoration(
                  color: AppColors.isDark(context)
                      ? AppColors.slate700
                      : AppColors.slate200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.isDark(context)
                      ? AppColors.slate700
                      : AppColors.slate200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 12,
                width: 80,
                decoration: BoxDecoration(
                  color: AppColors.isDark(context)
                      ? AppColors.slate700
                      : AppColors.slate200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _BudgetEmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;

  const _BudgetEmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 48,
            color: AppColors.textTertiary(context),
          ),
          const SizedBox(height: 12),
          Text(
            'No budgets yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create a budget to start tracking\nyour spending limits.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onCreateTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Create Budget',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overview card (hero) ────────────────────────────────────────────────────

class _BudgetOverviewCard extends StatelessWidget {
  final List<BudgetStatus> statuses;

  const _BudgetOverviewCard({required this.statuses});

  @override
  Widget build(BuildContext context) {
    final totalBudget =
        statuses.fold<double>(0, (s, e) => s + e.budget.amount);
    final totalSpent = statuses.fold<double>(0, (s, e) => s + e.spent);
    final totalRemaining = totalBudget - totalSpent;
    final percentage = totalBudget > 0 ? (totalSpent / totalBudget) * 100 : 0.0;
    final progress = (percentage / 100).clamp(0.0, 1.0);

    final progressColor = percentage >= 100
        ? AppColors.red
        : percentage >= 70
            ? AppColors.amber
            : AppColors.incomeSuccess;

    final spentLabel = formatNumberWithComma(totalSpent)
        .replaceFirst(RegExp(r'\.00$'), '');
    final budgetLabel = formatNumberWithComma(totalBudget)
        .replaceFirst(RegExp(r'\.00$'), '');
    final remainingLabel = formatNumberWithComma(totalRemaining.abs())
        .replaceFirst(RegExp(r'\.00$'), '');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERALL BUDGET',
            style: TextStyle(
              color: AppColors.white.withValues(alpha: 0.85),
              fontSize: 14,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'ETB $spentLabel / $budgetLabel',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.9),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.white.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(progressColor),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                totalRemaining >= 0
                    ? 'ETB $remainingLabel remaining'
                    : 'ETB $remainingLabel over budget',
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${statuses.length} active budget${statuses.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Budget card (list item) ─────────────────────────────────────────────────

class _BudgetCard extends StatelessWidget {
  final BudgetStatus status;
  final TransactionProvider transactionProvider;
  final VoidCallback onTap;

  const _BudgetCard({
    required this.status,
    required this.transactionProvider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = status.budget;
    final percentage = status.percentageUsed;
    final progress = (percentage / 100).clamp(0.0, 1.0);

    final progressColor = status.isExceeded
        ? AppColors.red
        : status.isApproachingLimit
            ? AppColors.amber
            : AppColors.incomeSuccess;

    final statusLabel = status.isExceeded
        ? 'EXCEEDED'
        : status.isApproachingLimit
            ? 'WARNING'
            : 'ON TRACK';

    final statusColor = status.isExceeded
        ? AppColors.red
        : status.isApproachingLimit
            ? AppColors.amber
            : AppColors.incomeSuccess;

    final periodLabel = _periodLabel(budget);
    final spentLabel = formatNumberWithComma(status.spent)
        .replaceFirst(RegExp(r'\.00$'), '');
    final limitLabel = formatNumberWithComma(budget.amount)
        .replaceFirst(RegExp(r'\.00$'), '');

    // Category info
    Category? category;
    if (budget.categoryId != null) {
      category = transactionProvider.getCategoryById(budget.categoryId);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (category != null) ...[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        iconForCategoryKey(category.iconKey),
                        size: 18,
                        color: AppColors.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          budget.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.isDark(context)
                                ? AppColors.slate700
                                : AppColors.slate200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            periodLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.isDark(context)
                      ? AppColors.slate700
                      : AppColors.slate200,
                  valueColor: AlwaysStoppedAnimation(progressColor),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'ETB $spentLabel / $limitLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: progressColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Detail bottom sheet ─────────────────────────────────────────────────────

class _BudgetDetailSheet extends StatelessWidget {
  final BudgetStatus status;
  final BudgetProvider budgetProvider;
  final TransactionProvider transactionProvider;
  final VoidCallback onEdit;

  const _BudgetDetailSheet({
    required this.status,
    required this.budgetProvider,
    required this.transactionProvider,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = status.budget;
    final percentage = status.percentageUsed;
    final progress = (percentage / 100).clamp(0.0, 1.0);

    final progressColor = status.isExceeded
        ? AppColors.red
        : status.isApproachingLimit
            ? AppColors.amber
            : AppColors.incomeSuccess;

    final periodLabel = _periodLabel(budget);
    final spentLabel = formatNumberWithComma(status.spent)
        .replaceFirst(RegExp(r'\.00$'), '');
    final budgetLabel = formatNumberWithComma(budget.amount)
        .replaceFirst(RegExp(r'\.00$'), '');
    final remainingLabel = formatNumberWithComma(status.remaining.abs())
        .replaceFirst(RegExp(r'\.00$'), '');

    Category? category;
    if (budget.categoryId != null) {
      category = transactionProvider.getCategoryById(budget.categoryId);
    }

    final dateFormat = DateFormat('MMM d, yyyy');

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Budget Details',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderColor(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  children: [
                    // Circular progress
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CustomPaint(
                        painter: _CircularProgressPainter(
                          progress: progress,
                          progressColor: progressColor,
                          trackColor: AppColors.isDark(context)
                              ? AppColors.slate700
                              : AppColors.slate200,
                        ),
                        child: Center(
                          child: Text(
                            '${percentage.toStringAsFixed(0)}%',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      budget.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _DetailRow(label: 'Budget', value: 'ETB $budgetLabel'),
                    _DetailRow(
                      label: 'Spent',
                      value: 'ETB $spentLabel',
                      valueColor: status.isExceeded ? AppColors.red : null,
                    ),
                    _DetailRow(
                      label: 'Remaining',
                      value: status.remaining >= 0
                          ? 'ETB $remainingLabel'
                          : '-ETB $remainingLabel',
                      valueColor: status.remaining < 0 ? AppColors.red : AppColors.incomeSuccess,
                    ),
                    _DetailRow(label: 'Period', value: periodLabel),
                    _DetailRow(
                      label: 'Start',
                      value: dateFormat.format(status.periodStart),
                    ),
                    _DetailRow(
                      label: 'End',
                      value: dateFormat.format(status.periodEnd),
                    ),
                    _DetailRow(
                      label: 'Alert threshold',
                      value: '${budget.alertThreshold.toStringAsFixed(0)}%',
                    ),
                    _DetailRow(
                      label: 'Rollover',
                      value: budget.rollover ? 'Yes' : 'No',
                    ),
                    if (category != null)
                      _DetailRow(label: 'Category', value: category.name),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onEdit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Edit Budget',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _confirmDelete(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: BorderSide(
                            color: AppColors.red.withValues(alpha: 0.4),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Delete budget',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete budget?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await budgetProvider.deleteBudget(status.budget.id!);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor ?? AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Circular progress painter ───────────────────────────────────────────────

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color progressColor;
  final Color trackColor;

  _CircularProgressPainter({
    required this.progress,
    required this.progressColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 6;
    const strokeWidth = 10.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor;
  }
}

// ── Form bottom sheet ───────────────────────────────────────────────────────

class _BudgetFormSheet extends StatefulWidget {
  final BudgetProvider budgetProvider;
  final TransactionProvider transactionProvider;
  final Budget? existing;

  const _BudgetFormSheet({
    required this.budgetProvider,
    required this.transactionProvider,
    this.existing,
  });

  @override
  State<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends State<_BudgetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _alertController;
  late String _selectedPeriod;
  int? _selectedCategoryId;
  late bool _rollover;
  bool _isSaving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _nameController = TextEditingController(text: b?.name ?? '');
    _amountController = TextEditingController(
      text: b != null ? b.amount.toStringAsFixed(0) : '',
    );
    _alertController = TextEditingController(
      text: b != null
          ? b.alertThreshold.toStringAsFixed(0)
          : '80',
    );
    _selectedCategoryId = b?.categoryId;
    _rollover = b?.rollover ?? false;

    // Determine period from existing budget
    if (b != null) {
      if (b.type == 'category') {
        _selectedPeriod = b.timeFrame ?? 'monthly';
      } else {
        _selectedPeriod = b.type;
      }
    } else {
      _selectedPeriod = 'monthly';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _alertController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final expenseCategories = widget.transactionProvider.categories
        .where((c) => c.flow == 'expense' && !c.uncategorized)
        .toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    _isEdit ? 'Edit Budget' : 'Create Budget',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderColor(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        'Name',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration(context, 'e.g. Monthly groceries'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Amount
                      Text(
                        'Amount',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(context, '0').copyWith(
                          prefixText: 'ETB  ',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = double.tryParse(v.trim());
                          if (n == null || n <= 0) return 'Enter a valid amount';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Period
                      Text(
                        'Period',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _PeriodToggle(
                        selected: _selectedPeriod,
                        onChanged: (v) => setState(() => _selectedPeriod = v),
                      ),
                      const SizedBox(height: 16),

                      // Category
                      Text(
                        'Category (optional)',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _CategoryChipButton(
                              label: 'None',
                              icon: null,
                              selected: _selectedCategoryId == null,
                              onTap: () =>
                                  setState(() => _selectedCategoryId = null),
                            ),
                            ...expenseCategories.map((cat) {
                              return _CategoryChipButton(
                                label: cat.name,
                                icon: iconForCategoryKey(cat.iconKey),
                                selected: _selectedCategoryId == cat.id,
                                onTap: () =>
                                    setState(() => _selectedCategoryId = cat.id),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Alert threshold
                      Text(
                        'Alert threshold',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _alertController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration(context, '80').copyWith(
                          suffixText: '%',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = double.tryParse(v.trim());
                          if (n == null || n < 1 || n > 100) {
                            return '1-100';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Rollover
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceColor(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SwitchListTile(
                          title: Text(
                            'Rollover unused budget',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            'Carry remaining budget to the next period',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          value: _rollover,
                          onChanged: (v) => setState(() => _rollover = v),
                          activeColor: AppColors.primaryLight,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            disabledBackgroundColor:
                                AppColors.primaryDark.withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.white,
                                  ),
                                )
                              : Text(
                                  _isEdit ? 'Save Changes' : 'Create Budget',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),

                      if (_isEdit) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : _delete,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.red,
                              side: BorderSide(
                                color: AppColors.red.withValues(alpha: 0.4),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Delete budget',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
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

  InputDecoration _inputDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textTertiary(context)),
      filled: true,
      fillColor: AppColors.surfaceColor(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final isCategory = _selectedCategoryId != null;
    final now = DateTime.now();
    final budget = Budget(
      id: widget.existing?.id,
      name: _nameController.text.trim(),
      type: isCategory ? 'category' : _selectedPeriod,
      amount: double.parse(_amountController.text.trim()),
      categoryId: _selectedCategoryId,
      startDate: widget.existing?.startDate ?? now,
      rollover: _rollover,
      alertThreshold: double.parse(_alertController.text.trim()),
      isActive: true,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      timeFrame: isCategory ? _selectedPeriod : null,
    );

    try {
      if (_isEdit) {
        await widget.budgetProvider.updateBudget(budget);
      } else {
        await widget.budgetProvider.createBudget(budget);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Provider already prints debug logs
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete budget?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.budgetProvider.deleteBudget(widget.existing!.id!);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

// ── Period toggle ───────────────────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _PeriodToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final toggleBg = AppColors.isDark(context)
        ? AppColors.slate700.withValues(alpha: 0.6)
        : AppColors.slate200.withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: toggleBg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: ['daily', 'monthly', 'yearly'].map((period) {
          final isSelected = selected == period;
          final label =
              period[0].toUpperCase() + period.substring(1);
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(period),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.cardColor(context)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppColors.textPrimary(context)
                        : AppColors.textSecondary(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Category chip button ────────────────────────────────────────────────────

class _CategoryChipButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChipButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.primaryLight
        : AppColors.isDark(context)
            ? AppColors.slate700
            : AppColors.slate200;
    final fg = selected
        ? AppColors.white
        : AppColors.textSecondary(context);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

String _periodLabel(Budget budget) {
  if (budget.type == 'category') {
    final tf = budget.timeFrame ?? 'monthly';
    return '${tf[0].toUpperCase()}${tf.substring(1)} (Category)';
  }
  return '${budget.type[0].toUpperCase()}${budget.type.substring(1)}';
}
