import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/widgets/categorize_transaction_sheet.dart';

class RedesignHomePage extends StatefulWidget {
  const RedesignHomePage({super.key});

  @override
  State<RedesignHomePage> createState() => _RedesignHomePageState();
}

enum _ChartRange { week, month }

class _RedesignHomePageState extends State<RedesignHomePage> {
  bool _showBalance = true;
  _ChartRange _chartRange = _ChartRange.week;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<TransactionProvider>(context, listen: false);
      provider.loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        final summary = provider.summary;
        final totalBalance = summary?.totalBalance ?? 0.0;
        final todaySorted = provider.todayTransactions;
        final todayCount = todaySorted.length;
        final monthTransactionsCount = provider.monthTransactions.length;
        final todayList = todaySorted.take(3).toList(growable: false);
        final todayTotals = provider.todayTotals;
        final weekTotals = provider.weekTotals;
        final monthTotals = provider.monthTotals;
        final thirtyDayTotals = provider.thirtyDayTotals;
        final selfTransferCount = provider.selfTransferCount;
        final insightMessage = provider.monthlyInsight;
        final trendSeries = _chartRange == _ChartRange.week
            ? provider.weekTrendSeries
            : provider.monthTrendSeries;

        return Scaffold(
          backgroundColor: AppColors.slate50,
          body: SafeArea(
            child: RefreshIndicator(
              color: AppColors.primaryLight,
              onRefresh: provider.loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TotalBalanceCard(
                      totalBalance: totalBalance,
                      todayIncome: todayTotals.income,
                      todayExpense: todayTotals.expense,
                      weekIncome: weekTotals.income,
                      weekExpense: weekTotals.expense,
                      showBalance: _showBalance,
                      onToggleBalance: () {
                        setState(() {
                          _showBalance = !_showBalance;
                        });
                      },
                      onBreakdownTap: () => _openBalanceBreakdown(
                        totalBalance: totalBalance,
                        monthTransactions: monthTransactionsCount,
                        selfTransferCount: selfTransferCount,
                        monthTotals: monthTotals,
                        thirtyDayTotals: thirtyDayTotals,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InsightCard(message: insightMessage),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Today ($todayCount)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate900,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _openAllTodayTransactions(
                                provider: provider,
                                transactions: todaySorted,
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                foregroundColor: AppColors.primaryLight,
                              ),
                              child: const Text('See all'),
                            ),
                            const SizedBox(width: 4),
                            _QuickActionIconButton(
                              icon: Icons.refresh,
                              onTap: provider.loadData,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (provider.isLoading)
                      const _LoadingTransactions()
                    else if (todayList.isEmpty)
                      const _EmptyTransactions()
                    else
                      ...todayList.map((transaction) {
                        final bankLabel = _bankLabel(transaction.bankId);
                        final category =
                            provider.getCategoryById(transaction.categoryId);
                        final selfTransferLabel =
                            provider.getSelfTransferLabel(transaction);
                        final categoryLabel =
                            selfTransferLabel ?? category?.name ?? 'Categorize';
                        final isCategorize =
                            selfTransferLabel == null && category == null;
                        final isCredit = transaction.type == 'CREDIT';
                        final amountLabel = _amountLabel(
                          transaction.amount,
                          isCredit: isCredit,
                        );
                        return _TransactionTile(
                          bank: bankLabel,
                          category: categoryLabel,
                          categoryFilled: isCategorize,
                          amount: amountLabel,
                          amountColor: isCredit
                              ? AppColors.incomeSuccess
                              : AppColors.red,
                          name: _transactionCounterparty(transaction),
                          timestamp: _transactionTimeLabel(transaction),
                          onTap: () => _openTransactionCategorySheet(
                            provider: provider,
                            transaction: transaction,
                          ),
                        );
                      }),
                    if (todayList.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tap a transaction to categorize it.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.slate500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _IncomeExpenseCard(
                      trendSeries: trendSeries,
                      selectedRange: _chartRange,
                      onRangeChanged: (value) {
                        if (_chartRange == value) return;
                        setState(() {
                          _chartRange = value;
                        });
                      },
                    ),
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

  void _openAllTodayTransactions({
    required TransactionProvider provider,
    required List<Transaction> transactions,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _AllTodayTransactionsSheet(
          transactions: transactions,
          provider: provider,
          onTransactionTap: (transaction) => _openTransactionCategorySheet(
            provider: provider,
            transaction: transaction,
          ),
        );
      },
    );
  }

  Future<void> _openTransactionCategorySheet({
    required TransactionProvider provider,
    required Transaction transaction,
  }) async {
    await showTransactionDetailsSheet(
      context: context,
      transaction: transaction,
      provider: provider,
    );
  }

  void _openBalanceBreakdown({
    required double totalBalance,
    required int monthTransactions,
    required int selfTransferCount,
    required TransactionTotals monthTotals,
    required TransactionTotals thirtyDayTotals,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _BalanceBreakdownSheet(
          totalBalance: totalBalance,
          monthTransactions: monthTransactions,
          selfTransferCount: selfTransferCount,
          monthTotals: monthTotals,
          thirtyDayTotals: thirtyDayTotals,
        );
      },
    );
  }
}

DateTime? _parseTransactionTime(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toLocal();
  } catch (_) {
    return null;
  }
}

String _formatEtbValue(double value) {
  final rounded = value.roundToDouble();
  final formatted =
      formatNumberWithComma(rounded).replaceFirst(RegExp(r'\.00$'), '');
  return formatted;
}

String _formatSignedEtb(double value) {
  final prefix = value >= 0 ? '+' : '-';
  return '$prefix ETB ${_formatEtbValue(value.abs())}';
}

String _bankLabel(int? bankId) {
  if (bankId == null) return 'Bank';
  if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
  try {
    final bank = AppConstants.banks.firstWhere((b) => b.id == bankId);
    return bank.shortName;
  } catch (_) {
    return 'Bank $bankId';
  }
}

String _amountLabel(double amount, {required bool isCredit}) {
  final formatted = formatNumberWithComma(amount);
  return '${isCredit ? '+' : '-'} ETB $formatted';
}

String _transactionCounterparty(Transaction transaction) {
  final receiver = transaction.receiver?.trim();
  final creditor = transaction.creditor?.trim();
  if (receiver != null && receiver.isNotEmpty) return receiver.toUpperCase();
  if (creditor != null && creditor.isNotEmpty) return creditor.toUpperCase();
  return 'UNKNOWN';
}

String _transactionTimeLabel(Transaction transaction) {
  final dt = _parseTransactionTime(transaction.time);
  if (dt == null) return 'Unknown time';
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

class _TotalBalanceCard extends StatelessWidget {
  final double totalBalance;
  final double todayIncome;
  final double todayExpense;
  final double weekIncome;
  final double weekExpense;
  final bool showBalance;
  final VoidCallback onToggleBalance;
  final VoidCallback onBreakdownTap;

  const _TotalBalanceCard({
    required this.totalBalance,
    required this.todayIncome,
    required this.todayExpense,
    required this.weekIncome,
    required this.weekExpense,
    required this.showBalance,
    required this.onToggleBalance,
    required this.onBreakdownTap,
  });

  @override
  Widget build(BuildContext context) {
    final abbreviated =
        formatNumberAbbreviated(totalBalance).replaceAll('k', 'K');
    final displayBalance = showBalance ? abbreviated : '***';
    final todayIncomeLabel =
        showBalance ? '+ ${_formatDelta(todayIncome)}' : '***';
    final todayExpenseLabel =
        showBalance ? '- ${_formatDelta(todayExpense)}' : '***';
    final weekIncomeLabel =
        showBalance ? '+ ${_formatDelta(weekIncome)}' : '***';
    final weekExpenseLabel =
        showBalance ? '- ${_formatDelta(weekExpense)}' : '***';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TOTAL BALANCE',
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onToggleBalance,
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.white.withValues(alpha: 0.9),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(24, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  showBalance
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'ETB $displayBalance',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 14),
          const _DashedLine(color: AppColors.white, opacity: 0.35),
          const SizedBox(height: 4),
          InkWell(
            onTap: onBreakdownTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    'How did I get here?',
                    style: TextStyle(
                      color: AppColors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: AppColors.white.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
          const _DashedLine(color: AppColors.white, opacity: 0.25),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: _BalanceDelta(
                    label: 'Today (ETB)',
                    income: todayIncomeLabel,
                    expense: todayExpenseLabel,
                  ),
                ),
                const SizedBox(width: 16),
                const _DashedLineVertical(
                  color: AppColors.white,
                  opacity: 0.3,
                  height: 44,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _BalanceDelta(
                    label: 'This week (ETB)',
                    income: weekIncomeLabel,
                    expense: weekExpenseLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      width: 40,
      child: IconButton(
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.white,
          side: const BorderSide(color: AppColors.border),
          foregroundColor: AppColors.slate700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _BalanceDelta extends StatelessWidget {
  final String label;
  final String income;
  final String expense;

  const _BalanceDelta({
    required this.label,
    required this.income,
    required this.expense,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.white.withValues(alpha: 0.85),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              income,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.incomeSuccess,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 1,
              height: 14,
              color: AppColors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(width: 10),
            Text(
              expense,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.red,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatDelta(double value) {
  final formatted = formatNumberAbbreviated(value).replaceAll('k', 'K');
  return formatted;
}

class _DashedLine extends StatelessWidget {
  final Color color;
  final double opacity;

  const _DashedLine({
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 4.0;
        const dashSpace = 4.0;
        final dashCount =
            (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            dashCount,
            (_) => Container(
              width: dashWidth,
              height: 2,
              decoration: BoxDecoration(
                color: color.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashedLineVertical extends StatelessWidget {
  final Color color;
  final double opacity;
  final double height;

  const _DashedLineVertical({
    required this.color,
    required this.opacity,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    const dashHeight = 6.0;
    const dashSpace = 6.0;
    final dashCount = (height / (dashHeight + dashSpace)).floor().clamp(1, 12);
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          dashCount,
          (_) => Container(
            width: 2,
            height: dashHeight,
            decoration: BoxDecoration(
              color: color.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String message;

  const _InsightCard({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.lightbulb_outline,
              color: AppColors.amber,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INSIGHT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.slate500,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.slate700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final String bank;
  final String category;
  final bool categoryFilled;
  final String amount;
  final Color amountColor;
  final String name;
  final String timestamp;
  final VoidCallback? onTap;

  const _TransactionTile({
    required this.bank,
    required this.category,
    required this.categoryFilled,
    required this.amount,
    required this.amountColor,
    required this.name,
    required this.timestamp,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _CategoryChip(
                      label: category,
                      filled: categoryFilled,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.slate500,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timestamp,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.slate400,
                      fontSize: 10,
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

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool filled;

  const _CategoryChip({
    required this.label,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled
        ? AppColors.primaryLight
        : AppColors.primaryLight.withValues(alpha: 0.12);
    final foreground = filled ? AppColors.white : AppColors.primaryDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LoadingTransactions extends StatelessWidget {
  const _LoadingTransactions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.slate200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'No transactions today',
        style: TextStyle(
          color: AppColors.slate500,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _IncomeExpenseCard extends StatelessWidget {
  final TransactionTrendSeries trendSeries;
  final _ChartRange selectedRange;
  final ValueChanged<_ChartRange> onRangeChanged;

  const _IncomeExpenseCard({
    required this.trendSeries,
    required this.selectedRange,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Income vs Expense',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate900,
                ),
              ),
              const Spacer(),
              _RangeToggle(
                selectedRange: selectedRange,
                onRangeChanged: onRangeChanged,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(
              painter: _IncomeExpenseChartPainter(
                incomePoints: trendSeries.incomePoints,
                expensePoints: trendSeries.expensePoints,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Text(
                '+ ETB ${_formatEtbValue(trendSeries.totalIncome)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.incomeSuccess,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '- ETB ${_formatEtbValue(trendSeries.totalExpense)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Peak: ETB ${_formatEtbValue(trendSeries.maxValue)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.slate500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Last ${trendSeries.days} days',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.slate500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  final _ChartRange selectedRange;
  final ValueChanged<_ChartRange> onRangeChanged;

  const _RangeToggle({
    required this.selectedRange,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate200.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RangeToggleButton(
            label: '7D',
            selected: selectedRange == _ChartRange.week,
            onTap: () => onRangeChanged(_ChartRange.week),
          ),
          _RangeToggleButton(
            label: '30D',
            selected: selectedRange == _ChartRange.month,
            onTap: () => onRangeChanged(_ChartRange.month),
          ),
        ],
      ),
    );
  }
}

class _RangeToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.slate900 : AppColors.slate500,
          ),
        ),
      ),
    );
  }
}

class _IncomeExpenseChartPainter extends CustomPainter {
  final List<double> incomePoints;
  final List<double> expensePoints;

  _IncomeExpenseChartPainter({
    required this.incomePoints,
    required this.expensePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.slate200
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const dashSpace = 4.0;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), gridPaint);
        x += dashWidth + dashSpace;
      }
    }

    final incomePaint = Paint()
      ..color = AppColors.incomeSuccess
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final expensePaint = Paint()
      ..color = AppColors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    Path buildPath(List<double> values) {
      if (values.isEmpty) return Path();
      if (values.length == 1) {
        final y = size.height * (1 - values.first.clamp(0.0, 1.0));
        return Path()
          ..moveTo(0, y)
          ..lineTo(size.width, y);
      }
      final path = Path();
      for (int i = 0; i < values.length; i++) {
        final x = size.width * (i / (values.length - 1));
        final y = size.height * (1 - values[i]);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    canvas.drawPath(buildPath(incomePoints), incomePaint);
    canvas.drawPath(buildPath(expensePoints), expensePaint);
  }

  @override
  bool shouldRepaint(covariant _IncomeExpenseChartPainter oldDelegate) {
    return oldDelegate.incomePoints != incomePoints ||
        oldDelegate.expensePoints != expensePoints;
  }
}

class _BalanceBreakdownSheet extends StatelessWidget {
  final double totalBalance;
  final int monthTransactions;
  final int selfTransferCount;
  final TransactionTotals monthTotals;
  final TransactionTotals thirtyDayTotals;

  const _BalanceBreakdownSheet({
    required this.totalBalance,
    required this.monthTransactions,
    required this.selfTransferCount,
    required this.monthTotals,
    required this.thirtyDayTotals,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthNet = monthTotals.income - monthTotals.expense;
    final last30Net = thirtyDayTotals.income - thirtyDayTotals.expense;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                color: AppColors.slate400,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Balance breakdown',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate900,
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
            const Divider(height: 1, color: AppColors.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BreakdownValueRow(
                      label: 'Current balance',
                      value: 'ETB ${_formatEtbValue(totalBalance)}',
                      valueColor: AppColors.slate900,
                      emphasize: true,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'This month',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.slate700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _BreakdownValueRow(
                      label: 'Income',
                      value: '+ ETB ${_formatEtbValue(monthTotals.income)}',
                      valueColor: AppColors.incomeSuccess,
                    ),
                    _BreakdownValueRow(
                      label: 'Expense',
                      value: '- ETB ${_formatEtbValue(monthTotals.expense)}',
                      valueColor: AppColors.red,
                    ),
                    _BreakdownValueRow(
                      label: 'Net',
                      value: _formatSignedEtb(monthNet),
                      valueColor: monthNet >= 0
                          ? AppColors.incomeSuccess
                          : AppColors.red,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Last 30 days',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.slate700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _BreakdownValueRow(
                      label: 'Income',
                      value: '+ ETB ${_formatEtbValue(thirtyDayTotals.income)}',
                      valueColor: AppColors.incomeSuccess,
                    ),
                    _BreakdownValueRow(
                      label: 'Expense',
                      value:
                          '- ETB ${_formatEtbValue(thirtyDayTotals.expense)}',
                      valueColor: AppColors.red,
                    ),
                    _BreakdownValueRow(
                      label: 'Net',
                      value: _formatSignedEtb(last30Net),
                      valueColor: last30Net >= 0
                          ? AppColors.incomeSuccess
                          : AppColors.red,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '$monthTransactions transactions counted this month.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.slate600,
                      ),
                    ),
                    if (selfTransferCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$selfTransferCount self transfers are excluded from income and expense totals.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.slate500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownValueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool emphasize;

  const _BreakdownValueRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.slate600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllTodayTransactionsSheet extends StatelessWidget {
  final List<Transaction> transactions;
  final TransactionProvider provider;
  final ValueChanged<Transaction> onTransactionTap;

  const _AllTodayTransactionsSheet({
    required this.transactions,
    required this.provider,
    required this.onTransactionTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.slate400,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'Today (${transactions.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate900,
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
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: transactions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: _EmptyTransactions(),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final transaction = transactions[index];
                      final bankLabel = _bankLabel(transaction.bankId);
                      final category =
                          provider.getCategoryById(transaction.categoryId);
                      final selfTransferLabel =
                          provider.getSelfTransferLabel(transaction);
                      final categoryLabel =
                          selfTransferLabel ?? category?.name ?? 'Categorize';
                      final isCategorize =
                          selfTransferLabel == null && category == null;
                      final isCredit = transaction.type == 'CREDIT';
                      return _TransactionTile(
                        bank: bankLabel,
                        category: categoryLabel,
                        categoryFilled: isCategorize,
                        amount: _amountLabel(
                          transaction.amount,
                          isCredit: isCredit,
                        ),
                        amountColor:
                            isCredit ? AppColors.incomeSuccess : AppColors.red,
                        name: _transactionCounterparty(transaction),
                        timestamp: _transactionTimeLabel(transaction),
                        onTap: () => onTransactionTap(transaction),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
