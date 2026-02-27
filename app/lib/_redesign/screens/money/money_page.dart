import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/widgets/categorize_transaction_sheet.dart';

class RedesignMoneyPage extends StatefulWidget {
  const RedesignMoneyPage({super.key});

  @override
  State<RedesignMoneyPage> createState() => _RedesignMoneyPageState();
}

enum _TopTab { activity, accounts }

enum _SubTab { transactions, analytics, ledger }

class _RedesignMoneyPageState extends State<RedesignMoneyPage> {
  _TopTab _topTab = _TopTab.activity;
  _SubTab _subTab = _SubTab.transactions;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: AppColors.slate50,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _TopTabBar(
                    selectedTab: _topTab,
                    onTabChanged: (tab) => setState(() => _topTab = tab),
                  ),
                ),
                Expanded(
                  child: _topTab == _TopTab.activity
                      ? _buildActivityContent(provider)
                      : _buildAccountsPlaceholder(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivityContent(TransactionProvider provider) {
    final monthTotals = provider.monthTotals;
    final healthScore =
        _computeHealthScore(monthTotals.income, monthTotals.expense);
    final monthAbbrev = _currentMonthAbbrev();

    final transactions = provider.transactions;
    final filtered = _filterTransactions(transactions);
    final grouped = _groupByDate(filtered);

    // Build flat list: date headers + transactions interleaved
    final flatItems = <Object>[];
    for (final entry in grouped.entries) {
      flatItems.add(entry.key);
      flatItems.addAll(entry.value);
    }

    return RefreshIndicator(
      color: AppColors.primaryLight,
      onRefresh: provider.loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  _FinancialHealthCard(
                    healthScore: healthScore,
                    monthName: monthAbbrev,
                    monthIncome: monthTotals.income,
                    monthExpense: monthTotals.expense,
                  ),
                  const SizedBox(height: 16),
                  _SubTabBar(
                    selectedTab: _subTab,
                    onTabChanged: (tab) => setState(() => _subTab = tab),
                  ),
                  const SizedBox(height: 12),
                  _SearchFilterRow(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    onFilterTap: () {},
                  ),
                ],
              ),
            ),
          ),
          if (_subTab == _SubTab.transactions) ...[
            if (provider.isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _LoadingTransactions(),
                ),
              )
            else if (flatItems.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _EmptyTransactions(),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                sliver: SliverList.builder(
                  itemCount: flatItems.length,
                  itemBuilder: (context, index) {
                    final item = flatItems[index];
                    if (item is String) {
                      return _DateHeader(label: item);
                    }
                    final transaction = item as Transaction;
                    return _buildTransactionTile(provider, transaction);
                  },
                ),
              ),
          ] else
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  _subTab == _SubTab.analytics ? 'Analytics' : 'Ledger',
                  style: const TextStyle(
                    color: AppColors.slate500,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(
    TransactionProvider provider,
    Transaction transaction,
  ) {
    final bankLabel = _bankLabel(transaction.bankId);
    final category = provider.getCategoryById(transaction.categoryId);
    final selfTransferLabel = provider.getSelfTransferLabel(transaction);
    final categoryLabel = selfTransferLabel ?? category?.name ?? 'Categorize';
    final isCategorized = selfTransferLabel != null || category != null;
    final isCredit = transaction.type == 'CREDIT';

    return _TransactionTile(
      bank: bankLabel,
      category: categoryLabel,
      isCategorized: isCategorized,
      amount: _amountLabel(transaction.amount, isCredit: isCredit),
      amountColor: isCredit ? AppColors.incomeSuccess : AppColors.red,
      name: _transactionCounterparty(transaction),
      onTap: () => _openTransactionCategorySheet(provider, transaction),
    );
  }

  Future<void> _openTransactionCategorySheet(
    TransactionProvider provider,
    Transaction transaction,
  ) async {
    if (provider.isSelfTransfer(transaction)) {
      final label = provider.getSelfTransferLabel(transaction) ?? 'self';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This transaction is marked as "$label" and excluded from totals.',
          ),
        ),
      );
      return;
    }

    await showCategorizeTransactionSheet(
      context: context,
      provider: provider,
      transaction: transaction,
    );
  }

  Widget _buildAccountsPlaceholder() {
    return const Center(
      child: Text(
        'Accounts',
        style: TextStyle(
          color: AppColors.slate500,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Transaction> _filterTransactions(List<Transaction> transactions) {
    if (_searchQuery.isEmpty) return transactions;
    final query = _searchQuery.toLowerCase();
    return transactions.where((t) {
      final receiver = t.receiver?.toLowerCase() ?? '';
      final creditor = t.creditor?.toLowerCase() ?? '';
      final bank = _bankLabel(t.bankId).toLowerCase();
      return receiver.contains(query) ||
          creditor.contains(query) ||
          bank.contains(query);
    }).toList();
  }
}

// ─── Helper functions ─────────────────────────────────────────────

const _months = [
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

String _currentMonthAbbrev() {
  return _months[DateTime.now().month - 1].toUpperCase();
}

String _formatDateHeader(DateTime date) {
  return '${_months[date.month - 1]} ${date.day}, ${date.year}';
}

DateTime? _parseTransactionTime(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toLocal();
  } catch (_) {
    return null;
  }
}

int _computeHealthScore(double income, double expense) {
  if (income <= 0) return 0;
  final ratio = (income - expense) / income;
  return (ratio * 100).round().clamp(0, 100);
}

Color _healthColor(int score) {
  if (score < 30) return AppColors.red;
  if (score < 60) return AppColors.amber;
  if (score < 80) return AppColors.blue;
  return AppColors.incomeSuccess;
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

Map<String, List<Transaction>> _groupByDate(List<Transaction> transactions) {
  final sorted = List<Transaction>.from(transactions)
    ..sort((a, b) {
      final aTime = _parseTransactionTime(a.time);
      final bTime = _parseTransactionTime(b.time);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

  final Map<String, List<Transaction>> grouped = {};
  for (final txn in sorted) {
    final dt = _parseTransactionTime(txn.time);
    final key = dt != null ? _formatDateHeader(dt) : 'Unknown Date';
    grouped.putIfAbsent(key, () => []).add(txn);
  }
  return grouped;
}

// ─── Widgets ──────────────────────────────────────────────────────

class _TopTabBar extends StatelessWidget {
  final _TopTab selectedTab;
  final ValueChanged<_TopTab> onTabChanged;

  const _TopTabBar({
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TopTabItem(
            label: 'Activity',
            selected: selectedTab == _TopTab.activity,
            onTap: () => onTabChanged(_TopTab.activity),
          ),
        ),
        Expanded(
          child: _TopTabItem(
            label: 'Accounts',
            selected: selectedTab == _TopTab.accounts,
            onTap: () => onTabChanged(_TopTab.accounts),
          ),
        ),
      ],
    );
  }
}

class _TopTabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TopTabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.primaryLight : AppColors.border,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primaryLight : AppColors.slate500,
            fontSize: 20,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _FinancialHealthCard extends StatelessWidget {
  final int healthScore;
  final String monthName;
  final double monthIncome;
  final double monthExpense;

  const _FinancialHealthCard({
    required this.healthScore,
    required this.monthName,
    required this.monthIncome,
    required this.monthExpense,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreColor = _healthColor(healthScore);
    final incomeFormatted =
        formatNumberAbbreviated(monthIncome).replaceAll('k', 'K');
    final expenseFormatted =
        formatNumberAbbreviated(monthExpense).replaceAll('k', 'K');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FINANCIAL HEALTH',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.slate500,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$healthScore',
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      ' / 100',
                      style: TextStyle(
                        color: AppColors.slate500,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'CASH FLOW ($monthName)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.slate500,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '+ETB $incomeFormatted',
                      style: const TextStyle(
                        color: AppColors.incomeSuccess,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      ' | ',
                      style: TextStyle(
                        color: AppColors.slate400,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '- ETB $expenseFormatted',
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 56,
            height: 56,
            child: CustomPaint(
              painter: _HealthGaugePainter(
                score: healthScore,
                color: scoreColor,
              ),
              child: Center(
                child: Text(
                  '$healthScore',
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthGaugePainter extends CustomPainter {
  final int score;
  final Color color;

  _HealthGaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const strokeWidth = 5.0;

    // Background ring
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweepAngle = (score / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HealthGaugePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.color != color;
  }
}

class _SubTabBar extends StatelessWidget {
  final _SubTab selectedTab;
  final ValueChanged<_SubTab> onTabChanged;

  const _SubTabBar({
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate200.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: _SubTabButton(
              label: 'Transactions',
              selected: selectedTab == _SubTab.transactions,
              onTap: () => onTabChanged(_SubTab.transactions),
            ),
          ),
          Expanded(
            child: _SubTabButton(
              label: 'Analytics',
              selected: selectedTab == _SubTab.analytics,
              onTap: () => onTabChanged(_SubTab.analytics),
            ),
          ),
          Expanded(
            child: _SubTabButton(
              label: 'Ledger',
              selected: selectedTab == _SubTab.ledger,
              onTap: () => onTabChanged(_SubTab.ledger),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SubTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDark : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.white : AppColors.slate600,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SearchFilterRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;

  const _SearchFilterRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
              // border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 14, color: AppColors.slate900),
              decoration: const InputDecoration(
                hintText: 'Search Transactions',
                hintStyle: TextStyle(
                  color: AppColors.slate400,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onFilterTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.filter_list,
              color: AppColors.slate500,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String label;

  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.slate700,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final String bank;
  final String category;
  final bool isCategorized;
  final String amount;
  final Color amountColor;
  final String name;
  final VoidCallback? onTap;

  const _TransactionTile({
    required this.bank,
    required this.category,
    required this.isCategorized,
    required this.amount,
    required this.amountColor,
    required this.name,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _CategoryChip(
                      label: category,
                      isCategorized: isCategorized,
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
                      fontSize: 15,
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
  final bool isCategorized;

  const _CategoryChip({
    required this.label,
    required this.isCategorized,
  });

  @override
  Widget build(BuildContext context) {
    if (isCategorized) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.incomeSuccess,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.slate400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.slate700,
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: Text(
          'No transactions found',
          style: TextStyle(
            color: AppColors.slate500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
