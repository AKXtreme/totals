import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/gradients.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/widgets/categorize_transaction_sheet.dart';

class RedesignMoneyPage extends StatefulWidget {
  const RedesignMoneyPage({super.key});

  @override
  State<RedesignMoneyPage> createState() => _RedesignMoneyPageState();
}

enum _TopTab { activity, accounts }

enum _SubTab { transactions, analytics, ledger }

/// Filter state passed from the filter bottom sheet.
class _TransactionFilter {
  final String? type; // null = All, 'DEBIT' = Expense, 'CREDIT' = Income
  final int? bankId; // null = All Banks
  final String? accountNumber; // null = All Accounts
  final DateTime? startDate;
  final DateTime? endDate;

  const _TransactionFilter({
    this.type,
    this.bankId,
    this.accountNumber,
    this.startDate,
    this.endDate,
  });

  bool get isActive =>
      type != null ||
      bankId != null ||
      accountNumber != null ||
      startDate != null ||
      endDate != null;

  int get activeCount {
    int count = 0;
    if (type != null) count++;
    if (bankId != null) count++;
    if (accountNumber != null) count++;
    if (startDate != null || endDate != null) count++;
    return count;
  }
}

class _RedesignMoneyPageState extends State<RedesignMoneyPage> {
  _TopTab _topTab = _TopTab.activity;
  _SubTab _subTab = _SubTab.transactions;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _TransactionFilter _filter = const _TransactionFilter();
  int? _selectedBankId;
  String? _expandedAccountNumber;
  bool _showAccountBalances = true;

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
                      : _buildAccountsContent(provider),
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
                    onFilterTap: () => _openFilterSheet(provider),
                    activeFilterCount: _filter.activeCount,
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

  Widget _buildAccountsContent(TransactionProvider provider) {
    final summary = provider.summary;
    final bankSummaries = provider.bankSummaries;
    final accountSummaries = provider.accountSummaries;
    final isOverview = _selectedBankId == null;

    // Overview data
    final totalBalance = summary?.totalBalance ?? 0.0;
    final bankCount = summary?.banks ?? 0;
    final accountCount = summary?.accounts ?? 0;
    final totalCredit = summary?.totalCredit ?? 0.0;
    final totalDebit = summary?.totalDebit ?? 0.0;
    final totalTxnCount = provider.allTransactions.length;

    // Bank detail data
    BankSummary? bankSummary;
    if (!isOverview) {
      for (final b in bankSummaries) {
        if (b.bankId == _selectedBankId) {
          bankSummary = b;
          break;
        }
      }
      if (bankSummary == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedBankId = null);
        });
        return const SizedBox.shrink();
      }
    }

    final accounts = isOverview
        ? <AccountSummary>[]
        : accountSummaries
            .where((a) => a.bankId == _selectedBankId)
            .toList();
    final bankTxnCount = isOverview
        ? 0
        : provider.allTransactions
            .where((t) => t.bankId == _selectedBankId)
            .length;

    return RefreshIndicator(
      color: AppColors.primaryLight,
      onRefresh: provider.loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        child: Column(
          children: [
            // Selector strip: Totals icon + bank icons
            _BankSelectorStrip(
              bankSummaries: bankSummaries,
              selectedBankId: _selectedBankId,
              onBankSelected: (id) => setState(() {
                _selectedBankId = id;
                _expandedAccountNumber = null;
              }),
              onTotalsSelected: () => setState(() {
                _selectedBankId = null;
                _expandedAccountNumber = null;
              }),
            ),
            const SizedBox(height: 12),

            // Balance card
            _AccountsBalanceCard(
              balance: isOverview ? totalBalance : bankSummary!.totalBalance,
              subtitle: isOverview
                  ? '$bankCount Banks | $accountCount Accounts'
                  : '${bankSummary!.accountCount} Account${bankSummary!.accountCount == 1 ? '' : 's'}',
              transactionCount: isOverview ? totalTxnCount : bankTxnCount,
              totalCredit:
                  isOverview ? totalCredit : bankSummary!.totalCredit,
              totalDebit: isOverview ? totalDebit : bankSummary!.totalDebit,
              showBalance: _showAccountBalances,
              onToggleBalance: () =>
                  setState(() => _showAccountBalances = !_showAccountBalances),
            ),
            const SizedBox(height: 16),

            // Content below balance card
            if (isOverview)
              _BankGrid(
                bankSummaries: bankSummaries,
                showBalance: _showAccountBalances,
                onBankTap: (bankId) =>
                    setState(() => _selectedBankId = bankId),
              )
            else
              ...accounts.map((account) {
                final acctTxnCount = account.totalTransactions.toInt();
                return _AccountCard(
                  account: account,
                  bankId: _selectedBankId!,
                  isExpanded:
                      _expandedAccountNumber == account.accountNumber,
                  showBalance: _showAccountBalances,
                  transactionCount: acctTxnCount,
                  onToggleExpand: () => setState(() {
                    _expandedAccountNumber =
                        _expandedAccountNumber == account.accountNumber
                            ? null
                            : account.accountNumber;
                  }),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilterSheet(TransactionProvider provider) async {
    // Derive unique bank IDs and account numbers from transactions.
    final allTxns = provider.transactions;
    final bankIds = <int>{};
    final accountNumbers = <String>{};
    for (final t in allTxns) {
      if (t.bankId != null) bankIds.add(t.bankId!);
      if (t.accountNumber != null && t.accountNumber!.isNotEmpty) {
        accountNumbers.add(t.accountNumber!);
      }
    }

    final result = await showModalBottomSheet<_TransactionFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterTransactionsSheet(
        currentFilter: _filter,
        bankIds: bankIds.toList()..sort(),
        accountNumbers: accountNumbers.toList()..sort(),
      ),
    );
    if (result != null) {
      setState(() => _filter = result);
    }
  }

  List<Transaction> _filterTransactions(List<Transaction> transactions) {
    var result = transactions;

    // Type filter
    if (_filter.type != null) {
      result = result.where((t) => t.type == _filter.type).toList();
    }

    // Bank filter
    if (_filter.bankId != null) {
      result = result.where((t) => t.bankId == _filter.bankId).toList();
    }

    // Account filter
    if (_filter.accountNumber != null) {
      result = result
          .where((t) => t.accountNumber == _filter.accountNumber)
          .toList();
    }

    // Date range filter
    if (_filter.startDate != null || _filter.endDate != null) {
      result = result.where((t) {
        final dt = _parseTransactionTime(t.time);
        if (dt == null) return false;
        if (_filter.startDate != null && dt.isBefore(_filter.startDate!)) {
          return false;
        }
        if (_filter.endDate != null) {
          final endOfDay = _filter.endDate!
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
          if (dt.isAfter(endOfDay)) return false;
        }
        return true;
      }).toList();
    }

    // Search query filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((t) {
        final receiver = t.receiver?.toLowerCase() ?? '';
        final creditor = t.creditor?.toLowerCase() ?? '';
        final bank = _bankLabel(t.bankId).toLowerCase();
        return receiver.contains(query) ||
            creditor.contains(query) ||
            bank.contains(query);
      }).toList();
    }

    return result;
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

String _formatCount(int count) {
  final formatted = formatNumberWithComma(count.toDouble());
  return formatted.replaceFirst(RegExp(r'\.00$'), '');
}

String _formatEtbAbbrev(double value) {
  return formatNumberAbbreviated(value).replaceAll('k', 'K');
}

String _getBankImage(int bankId) {
  if (bankId == CashConstants.bankId) return 'assets/images/eth_birr.png';
  try {
    return AppConstants.banks.firstWhere((b) => b.id == bankId).image;
  } catch (_) {
    return '';
  }
}

String _getBankName(int bankId) {
  if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
  try {
    return AppConstants.banks.firstWhere((b) => b.id == bankId).shortName;
  } catch (_) {
    return 'Bank $bankId';
  }
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
  final int activeFilterCount;

  const _SearchFilterRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
    this.activeFilterCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters = activeFilterCount > 0;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasFilters
                      ? AppColors.primaryDark.withValues(alpha: 0.1)
                      : AppColors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        hasFilters ? AppColors.primaryDark : AppColors.border,
                  ),
                ),
                child: Icon(
                  Icons.filter_list,
                  color:
                      hasFilters ? AppColors.primaryDark : AppColors.slate500,
                  size: 22,
                ),
              ),
              if (hasFilters)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryDark,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$activeFilterCount',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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

// ─── Accounts Widgets ─────────────────────────────────────────────

const _balanceCardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
);

class _AccountsBalanceCard extends StatelessWidget {
  final double balance;
  final String subtitle;
  final int transactionCount;
  final double totalCredit;
  final double totalDebit;
  final bool showBalance;
  final VoidCallback onToggleBalance;

  const _AccountsBalanceCard({
    required this.balance,
    required this.subtitle,
    required this.transactionCount,
    required this.totalCredit,
    required this.totalDebit,
    required this.showBalance,
    required this.onToggleBalance,
  });

  @override
  Widget build(BuildContext context) {
    final balanceLabel =
        showBalance ? 'ETB ${_formatEtbAbbrev(balance)}' : 'ETB ***';
    final creditLabel =
        showBalance ? '+ETB ${_formatEtbAbbrev(totalCredit)}' : '+ETB ***';
    final debitLabel =
        showBalance ? '-ETB ${_formatEtbAbbrev(totalDebit)}' : '-ETB ***';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _balanceCardGradient,
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
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onToggleBalance,
                child: Icon(
                  showBalance
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.white.withValues(alpha: 0.9),
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            balanceLabel,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$subtitle | ${_formatCount(transactionCount)} Txns',
            style: TextStyle(
              color: AppColors.white.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: AppColors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                creditLabel,
                style: const TextStyle(
                  color: AppColors.incomeSuccess,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                ' | ',
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
              Text(
                debitLabel,
                style: const TextStyle(
                  color: AppColors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BankGrid extends StatelessWidget {
  final List<BankSummary> bankSummaries;
  final bool showBalance;
  final ValueChanged<int> onBankTap;

  const _BankGrid({
    required this.bankSummaries,
    required this.showBalance,
    required this.onBankTap,
  });

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      ...bankSummaries.map((bank) {
        return _BankGridCard(
          bankId: bank.bankId,
          accountCount: bank.accountCount,
          balance: bank.totalBalance,
          showBalance: showBalance,
          onTap: () => onBankTap(bank.bankId),
        );
      }),
      const _AddAccountCard(),
    ];

    final rows = <Widget>[];
    for (int i = 0; i < cards.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < cards.length ? 12 : 0),
          child: Row(
            children: [
              Expanded(child: cards[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < cards.length ? cards[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _BankGridCard extends StatelessWidget {
  final int bankId;
  final int accountCount;
  final double balance;
  final bool showBalance;
  final VoidCallback onTap;

  const _BankGridCard({
    required this.bankId,
    required this.accountCount,
    required this.balance,
    required this.showBalance,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bankName = _getBankName(bankId);
    final bankImage = _getBankImage(bankId);
    final balanceLabel =
        showBalance ? 'ETB ${_formatEtbAbbrev(balance)}' : '*****';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    bankName,
                    style: const TextStyle(
                      color: AppColors.slate900,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _BankLogoCircle(imagePath: bankImage, size: 40),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$accountCount Account${accountCount == 1 ? '' : 's'}',
              style: const TextStyle(
                color: AppColors.slate500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              balanceLabel,
              style: TextStyle(
                color:
                    showBalance ? AppColors.slate700 : AppColors.slate500,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: showBalance ? 0 : 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddAccountCard extends StatelessWidget {
  const _AddAccountCard();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, style: BorderStyle.solid),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text(
                    'Add\nAccount',
                    style: TextStyle(
                      color: AppColors.slate900,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.slate200, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: AppColors.slate500,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Register new',
              style: TextStyle(
                color: AppColors.slate500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bank Account',
              style: TextStyle(
                color: AppColors.slate500,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankSelectorStrip extends StatelessWidget {
  final List<BankSummary> bankSummaries;
  final int? selectedBankId;
  final ValueChanged<int> onBankSelected;
  final VoidCallback onTotalsSelected;

  const _BankSelectorStrip({
    required this.bankSummaries,
    required this.selectedBankId,
    required this.onBankSelected,
    required this.onTotalsSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isTotalsSelected = selectedBankId == null;

    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Totals icon (first)
              GestureDetector(
                onTap: onTotalsSelected,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isTotalsSelected
                        ? Border.all(
                            color: AppColors.primaryLight, width: 2.5)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icon/totals_icon.png',
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              // Bank icons
              ...bankSummaries.map((bank) {
                final isSelected = bank.bankId == selectedBankId;
                final image = _getBankImage(bank.bankId);
                return GestureDetector(
                  onTap: () => onBankSelected(bank.bankId),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: AppColors.primaryLight, width: 2.5)
                          : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: _BankLogoCircle(
                        imagePath: image,
                        size: 36,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final AccountSummary account;
  final int bankId;
  final bool isExpanded;
  final bool showBalance;
  final int transactionCount;
  final VoidCallback onToggleExpand;

  const _AccountCard({
    required this.account,
    required this.bankId,
    required this.isExpanded,
    required this.showBalance,
    required this.transactionCount,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final bankImage = _getBankImage(bankId);
    final balanceLabel = showBalance
        ? 'ETB ${formatNumberWithComma(account.balance).replaceFirst(RegExp(r'\.00\$'), '')}'
        : '*****';
    final creditLabel =
        showBalance ? '+ETB ${_formatEtbAbbrev(account.totalCredit)}' : '***';
    final debitLabel =
        showBalance ? '-ETB ${_formatEtbAbbrev(account.totalDebit)}' : '***';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onToggleExpand,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  _BankLogoCircle(imagePath: bankImage, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.accountNumber,
                          style: const TextStyle(
                            color: AppColors.slate900,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          account.accountHolderName.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.slate500,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (isExpanded) ...[
                          const SizedBox(height: 4),
                          Text(
                            balanceLabel,
                            style: const TextStyle(
                              color: AppColors.slate900,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: AppColors.slate500,
                        size: 22,
                      ),
                      const SizedBox(height: 8),
                      Icon(
                        showBalance
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.slate400,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
              if (!isExpanded) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 56),
                    Text(
                      balanceLabel,
                      style: TextStyle(
                        color: showBalance
                            ? AppColors.slate700
                            : AppColors.slate500,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: showBalance ? 0 : 2,
                      ),
                    ),
                  ],
                ),
              ],
              if (isExpanded) ...[
                const SizedBox(height: 14),
                Container(height: 1, color: AppColors.border),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TRANSACTIONS',
                          style: TextStyle(
                            color: AppColors.slate500,
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatCount(transactionCount),
                          style: const TextStyle(
                            color: AppColors.slate900,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'IN & OUT',
                          style: TextStyle(
                            color: AppColors.slate500,
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              creditLabel,
                              style: const TextStyle(
                                color: AppColors.incomeSuccess,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              ' | ',
                              style: TextStyle(
                                color: AppColors.slate400,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              debitLabel,
                              style: const TextStyle(
                                color: AppColors.red,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BankLogoCircle extends StatelessWidget {
  final String imagePath;
  final double size;

  const _BankLogoCircle({
    required this.imagePath,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePath.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: AppColors.slate200,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.account_balance,
          size: size * 0.5,
          color: AppColors.slate500,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.slate200,
          child: Icon(
            Icons.account_balance,
            size: size * 0.5,
            color: AppColors.slate500,
          ),
        ),
      ),
    );
  }
}

// ─── Filter Bottom Sheet ──────────────────────────────────────────

class _FilterTransactionsSheet extends StatefulWidget {
  final _TransactionFilter currentFilter;
  final List<int> bankIds;
  final List<String> accountNumbers;

  const _FilterTransactionsSheet({
    required this.currentFilter,
    required this.bankIds,
    required this.accountNumbers,
  });

  @override
  State<_FilterTransactionsSheet> createState() =>
      _FilterTransactionsSheetState();
}

class _FilterTransactionsSheetState extends State<_FilterTransactionsSheet> {
  late String? _selectedType;
  late int? _selectedBankId;
  late String? _selectedAccountNumber;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentFilter.type;
    _selectedBankId = widget.currentFilter.bankId;
    _selectedAccountNumber = widget.currentFilter.accountNumber;
    _startDate = widget.currentFilter.startDate;
    _endDate = widget.currentFilter.endDate;
  }

  void _clearAll() {
    setState(() {
      _selectedType = null;
      _selectedBankId = null;
      _selectedAccountNumber = null;
      _startDate = null;
      _endDate = null;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      _TransactionFilter(
        type: _selectedType,
        bankId: _selectedBankId,
        accountNumber: _selectedAccountNumber,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryDark,
              onPrimary: AppColors.white,
              surface: AppColors.white,
              onSurface: AppColors.slate900,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  String _maskAccount(String accountNumber) {
    if (accountNumber.length <= 6) return accountNumber;
    final visible = accountNumber.length > 10 ? 4 : 3;
    final prefix = accountNumber.substring(0, visible);
    final suffix = accountNumber.substring(accountNumber.length - visible);
    final masked = '*' * (accountNumber.length - visible * 2);
    return '$prefix$masked$suffix';
  }

  String _formatDate(DateTime date) {
    return '${_months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.slate400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Filter Transactions',
                    style: TextStyle(
                      color: AppColors.slate900,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.slate500),
                  splashRadius: 20,
                ),
              ],
            ),
          ),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── TYPE ──
                  _sectionLabel('TYPE'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _selectedType == null,
                        onTap: () => setState(() => _selectedType = null),
                      ),
                      _FilterChip(
                        label: 'Expense',
                        selected: _selectedType == 'DEBIT',
                        onTap: () => setState(() => _selectedType = 'DEBIT'),
                      ),
                      _FilterChip(
                        label: 'Income',
                        selected: _selectedType == 'CREDIT',
                        onTap: () => setState(() => _selectedType = 'CREDIT'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── BANK ──
                  _sectionLabel('BANK'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'All Banks',
                        selected: _selectedBankId == null,
                        onTap: () => setState(() => _selectedBankId = null),
                      ),
                      for (final bankId in widget.bankIds)
                        _FilterChip(
                          label: _bankLabel(bankId),
                          selected: _selectedBankId == bankId,
                          onTap: () => setState(() => _selectedBankId = bankId),
                        ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── ACCOUNT ──
                  _sectionLabel('ACCOUNT'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'All Accounts',
                        selected: _selectedAccountNumber == null,
                        onTap: () =>
                            setState(() => _selectedAccountNumber = null),
                      ),
                      for (final account in widget.accountNumbers)
                        _FilterChip(
                          label: _maskAccount(account),
                          selected: _selectedAccountNumber == account,
                          onTap: () =>
                              setState(() => _selectedAccountNumber = account),
                        ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── DATE RANGE ──
                  _sectionLabel('DATE RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DatePickerField(
                          hint: 'Start date',
                          value: _startDate != null
                              ? _formatDate(_startDate!)
                              : null,
                          onTap: () => _pickDate(isStart: true),
                          onClear: _startDate != null
                              ? () => setState(() => _startDate = null)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DatePickerField(
                          hint: 'End date',
                          value:
                              _endDate != null ? _formatDate(_endDate!) : null,
                          onTap: () => _pickDate(isStart: false),
                          onClear: _endDate != null
                              ? () => setState(() => _endDate = null)
                              : null,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── ACTIONS ──
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.slate700,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Clear All',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _apply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Apply Filters',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.slate500,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDark : AppColors.slate50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryDark : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.white : AppColors.slate700,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String hint;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DatePickerField({
    required this.hint,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                  color:
                      value != null ? AppColors.slate900 : AppColors.slate400,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.slate400,
                ),
              )
            else
              const Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: AppColors.slate400,
              ),
          ],
        ),
      ),
    );
  }
}
