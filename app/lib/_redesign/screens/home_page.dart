import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/_redesign/screens/redesign_shell.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/_redesign/screens/todays_transactions_page.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_tile.dart';

class RedesignHomePage extends StatefulWidget {
  const RedesignHomePage({super.key});

  @override
  State<RedesignHomePage> createState() => _RedesignHomePageState();
}

enum _ChartRange { week, month }

class _RedesignHomePageState extends State<RedesignHomePage> {
  bool _showBalance = false;
  _ChartRange _chartRange = _ChartRange.week;
  final Set<String> _selectedRefs = {};

  bool get _isSelecting => _selectedRefs.isNotEmpty;

  void _toggleSelection(Transaction transaction) {
    setState(() {
      if (_selectedRefs.contains(transaction.reference)) {
        _selectedRefs.remove(transaction.reference);
      } else {
        _selectedRefs.add(transaction.reference);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedRefs.clear());

  Future<void> _deleteSelected(TransactionProvider provider) async {
    if (_selectedRefs.isEmpty) return;
    final count = _selectedRefs.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count transaction${count > 1 ? 's' : ''}?'),
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
      await provider.deleteTransactionsByReferences(_selectedRefs.toList());
      _clearSelection();
    }
  }

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
          backgroundColor: AppColors.background(context),
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
                      onCardTap: _openAccountsPage,
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
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: _openAllTodayTransactions,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                foregroundColor: AppColors.primaryLight,
                              ),
                              child: const Text('See all'),
                            ),
                            const SizedBox(width: 4),
                            _RefreshButton(
                              isLoading: provider.isLoading,
                              onTap: provider.loadData,
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_isSelecting) ...[
                      const SizedBox(height: 8),
                      _SelectionBar(
                        count: _selectedRefs.length,
                        onDelete: () => _deleteSelected(provider),
                        onClear: _clearSelection,
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Keep existing rows visible during background reloads
                    // so returning to Home does not flash back to loading state.
                    if (provider.isLoading && todayList.isEmpty)
                      const _LoadingTransactions()
                    else if (todayList.isEmpty)
                      const _EmptyTransactions()
                    else
                      ...todayList.map((transaction) {
                        final bankLabel = _bankLabel(transaction.bankId);
                        final category =
                            provider.getCategoryById(transaction.categoryId);
                        final isSelfTransfer =
                            provider.isSelfTransfer(transaction);
                        final isMisc =
                            category?.uncategorized == true;
                        final categoryLabel = isSelfTransfer
                            ? 'Self'
                            : (category?.name ?? 'Categorize');
                        final isCategorize =
                            isSelfTransfer || category != null;
                        final isCredit = transaction.type == 'CREDIT';
                        final amountLabel = _amountLabel(
                          transaction.amount,
                          isCredit: isCredit,
                        );
                        final selected =
                            _selectedRefs.contains(transaction.reference);
                        return TransactionTile(
                          bank: bankLabel,
                          category: categoryLabel,
                          categoryModel: category,
                          isCategorized: isCategorize,
                          isDebit: !isCredit,
                          isSelfTransfer: isSelfTransfer,
                          isMisc: isMisc,
                          amount: amountLabel,
                          amountColor: isCredit
                              ? AppColors.incomeSuccess
                              : AppColors.red,
                          name: _transactionCounterparty(transaction),
                          timestamp: _transactionTimeLabel(transaction),
                          selected: selected,
                          onTap: _isSelecting
                              ? () => _toggleSelection(transaction)
                              : () => _openTransactionCategorySheet(
                                    provider: provider,
                                    transaction: transaction,
                                  ),
                          onLongPress: () => _toggleSelection(transaction),
                        );
                      }),
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

  void _openAllTodayTransactions() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const TodaysTransactionsPage(),
      ),
    );
  }

  void _openAccountsPage() {
    final shellState = context.findAncestorStateOfType<RedesignShellState>();
    shellState?.openMoneyAccountsPage();
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
    final provider = Provider.of<TransactionProvider>(context, listen: false);
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
          allTransactions: provider.allTransactions,
          provider: provider,
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
  final VoidCallback onCardTap;
  final VoidCallback onToggleBalance;
  final VoidCallback onBreakdownTap;

  const _TotalBalanceCard({
    required this.totalBalance,
    required this.todayIncome,
    required this.todayExpense,
    required this.weekIncome,
    required this.weekExpense,
    required this.showBalance,
    required this.onCardTap,
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

    return GestureDetector(
      onTap: onCardTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: BorderRadius.circular(12),
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
                    fontSize: 12,
                    letterSpacing: 1.1,
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
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'ETB $displayBalance',
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: onBreakdownTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'How did I get here?',
                      style: TextStyle(
                        color: AppColors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: AppColors.white.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 1,
              color: AppColors.white.withValues(alpha: 0.22),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _BalanceDelta(
                    label: 'Today',
                    income: todayIncomeLabel,
                    expense: todayExpenseLabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BalanceDelta(
                    label: 'This week',
                    income: weekIncomeLabel,
                    expense: weekExpenseLabel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _RefreshButton({
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      width: 40,
      child: IconButton(
        onPressed: isLoading ? null : onTap,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.cardColor(context),
          side: BorderSide(color: AppColors.borderColor(context)),
          foregroundColor: AppColors.isDark(context)
              ? AppColors.slate400
              : AppColors.slate700,
          disabledForegroundColor: AppColors.textTertiary(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryLight,
                ),
              )
            : const Icon(Icons.refresh, size: 18),
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
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              income,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.incomeSuccess,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 12,
              color: AppColors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(width: 8),
            Text(
              expense,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.red,
                fontSize: 13,
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
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
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
                    color: AppColors.textSecondary(context),
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.isDark(context)
                        ? AppColors.slate400
                        : AppColors.slate700,
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

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  const _SelectionBar({
    required this.count,
    required this.onDelete,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onDelete,
            child: Icon(Icons.delete_outline_rounded,
                size: 20, color: AppColors.red),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close_rounded,
                size: 20, color: AppColors.textSecondary(context)),
          ),
        ],
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
            color: AppColors.cardColor(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.mutedFill(context),
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
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 40,
            color: AppColors.textTertiary(context),
          ),
          const SizedBox(height: 10),
          Text(
            'No transactions today',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.isDark(context)
                  ? AppColors.slate400
                  : AppColors.slate700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'New transactions will appear here as they come in.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
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
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
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
                  color: AppColors.textPrimary(context),
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
                gridColor: AppColors.mutedFill(context),
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
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Last ${trendSeries.days} days',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary(context),
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
    final toggleBg = AppColors.mutedFill(context).withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: toggleBg,
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
          color: selected ? AppColors.cardColor(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected
                ? AppColors.textPrimary(context)
                : AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

class _IncomeExpenseChartPainter extends CustomPainter {
  final List<double> incomePoints;
  final List<double> expensePoints;
  final Color gridColor;

  _IncomeExpenseChartPainter({
    required this.incomePoints,
    required this.expensePoints,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
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
        oldDelegate.expensePoints != expensePoints ||
        oldDelegate.gridColor != gridColor;
  }
}

class _BalanceBreakdownSheet extends StatefulWidget {
  final double totalBalance;
  final int monthTransactions;
  final int selfTransferCount;
  final TransactionTotals monthTotals;
  final TransactionTotals thirtyDayTotals;
  final List<Transaction> allTransactions;
  final TransactionProvider provider;

  const _BalanceBreakdownSheet({
    required this.totalBalance,
    required this.monthTransactions,
    required this.selfTransferCount,
    required this.monthTotals,
    required this.thirtyDayTotals,
    required this.allTransactions,
    required this.provider,
  });

  @override
  State<_BalanceBreakdownSheet> createState() => _BalanceBreakdownSheetState();
}

class _BalanceBreakdownSheetState extends State<_BalanceBreakdownSheet> {
  bool _showWeek = true; // true = this week, false = this month

  // Precomputed flat list caches
  late List<Object> _weekItems;
  late List<Object> _monthItems;
  late double? _weekStartingBalance;
  late DateTime? _weekStartingDate;
  late double? _monthStartingBalance;
  late DateTime? _monthStartingDate;

  @override
  void initState() {
    super.initState();
    _precompute();
  }

  void _precompute() {
    final now = DateTime.now();
    // Rolling 7-day window (today + previous 6 days), not calendar week.
    final today = DateTime(now.year, now.month, now.day);
    final weekStartDay = today.subtract(const Duration(days: 6));
    final monthStartDay = DateTime(now.year, now.month, 1);

    // Sort descending (newest first)
    final sorted = List<Transaction>.from(widget.allTransactions)
      ..sort((a, b) {
        final aT = _parseTransactionTime(a.time);
        final bT = _parseTransactionTime(b.time);
        if (aT == null && bT == null) return 0;
        if (aT == null) return 1;
        if (bT == null) return -1;
        return bT.compareTo(aT);
      });

    _weekItems = _buildFlatItems(sorted, weekStartDay);
    _monthItems = _buildFlatItems(sorted, monthStartDay);

    _weekStartingBalance = _computeStartingBalance(sorted, weekStartDay);
    _weekStartingDate = weekStartDay;
    _monthStartingBalance = _computeStartingBalance(sorted, monthStartDay);
    _monthStartingDate = monthStartDay;
  }

  List<Object> _buildFlatItems(List<Transaction> sorted, DateTime startDay) {
    final items = <Object>[];
    String? lastKey;
    for (final txn in sorted) {
      final dt = _parseTransactionTime(txn.time);
      if (dt == null || dt.isBefore(startDay)) continue;
      final key = _formatDateKey(dt);
      if (key != lastKey) {
        items.add(key);
        lastKey = key;
      }
      items.add(txn);
    }
    return items;
  }

  double? _computeStartingBalance(List<Transaction> sorted, DateTime startDay) {
    // sorted is descending; walk backwards (ascending) to find
    // the last transaction before startDay
    for (int i = sorted.length - 1; i >= 0; i--) {
      final dt = _parseTransactionTime(sorted[i].time);
      if (dt != null && dt.isBefore(startDay)) {
        return double.tryParse(sorted[i].currentBalance ?? '');
      }
    }
    return null;
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDateKey(DateTime dt) =>
      '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

  String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final p = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flatItems = _showWeek ? _weekItems : _monthItems;
    final startBal = _showWeek ? _weekStartingBalance : _monthStartingBalance;
    final startDate = _showWeek ? _weekStartingDate : _monthStartingDate;

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
                    'How did I get here?',
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
            // Week / Month toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  _PeriodChip(
                    label: 'Last 7 days',
                    selected: _showWeek,
                    onTap: () => setState(() => _showWeek = true),
                  ),
                  const SizedBox(width: 8),
                  _PeriodChip(
                    label: 'This month',
                    selected: !_showWeek,
                    onTap: () => setState(() => _showWeek = false),
                  ),
                  const Spacer(),
                  Text(
                    '${flatItems.where((e) => e is Transaction).length} txns',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderColor(context)),
            // Starting balance
            if (startBal != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  '${startDate != null ? _formatDateKey(startDate) : ''} Starting Balance: ETB ${formatNumberWithComma(startBal)}',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            // Ledger timeline
            Expanded(
              child: flatItems.isEmpty
                  ? Center(
                      child: Text(
                        'No transactions this ${_showWeek ? 'last 7 days' : 'month'}',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: flatItems.length,
                      itemBuilder: (context, index) {
                        final item = flatItems[index];

                        // Date header
                        if (item is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryLight,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  item,
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Transaction entry
                        final txn = item as Transaction;
                        final isLastOverall = index == flatItems.length - 1;
                        final lineColor = AppColors.borderColor(context);
                        final isCredit = txn.type == 'CREDIT';
                        final arrow = isCredit ? '↓' : '↑';
                        final sign = isCredit ? '+' : '-';
                        final amountStr = formatNumberAbbreviated(txn.amount)
                            .replaceAll('k', 'K');
                        final amountColor =
                            isCredit ? AppColors.incomeSuccess : AppColors.red;
                        final name = _transactionCounterparty(txn);
                        final bank = _bankLabel(txn.bankId);
                        final dt = _parseTransactionTime(txn.time);
                        final timeStr = dt != null ? _formatTime(dt) : '';
                        final bal = double.tryParse(txn.currentBalance ?? '');
                        final balStr = bal != null
                            ? formatNumberAbbreviated(bal).replaceAll('k', 'K')
                            : '-';

                        return Padding(
                          padding: const EdgeInsets.only(left: 16, right: 16),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: 10,
                                  child: Center(
                                    child: Container(
                                      width: 1.5,
                                      color: isLastOverall
                                          ? Colors.transparent
                                          : lineColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      showTransactionDetailsSheet(
                                        context: context,
                                        transaction: txn,
                                        provider: widget.provider,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          top: 12, bottom: 6),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 58,
                                            child: Text(
                                              timeStr,
                                              style: TextStyle(
                                                color: AppColors.textSecondary(
                                                    context),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.textPrimary(
                                                            context),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '$arrow ${sign}ETB $amountStr',
                                                  style: TextStyle(
                                                    color: amountColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Bal: $balStr',
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.textSecondary(
                                                            context),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            bank,
                                            style: TextStyle(
                                              color: AppColors.textTertiary(
                                                  context),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
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
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.primaryDark
                : AppColors.borderColor(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? AppColors.white : AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
