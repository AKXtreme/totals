import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/bank.dart' as bank_model;
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/services/account_registration_service.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/services/bank_detection_service.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/widgets/add_cash_transaction_sheet.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';

class RedesignMoneyPage extends StatefulWidget {
  const RedesignMoneyPage({super.key});

  @override
  State<RedesignMoneyPage> createState() => _RedesignMoneyPageState();
}

enum _TopTab { activity, accounts }

enum _SubTab { transactions, analytics, ledger }

final List<bank_model.Bank> _assetBanks = AllBanksFromAssets.getAllBanks();

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
  final Set<String> _selectedRefs = {};
  DateTime? _ledgerStartDate;
  DateTime? _ledgerEndDate;

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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: AppColors.background(context),
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
                  if (_subTab != _SubTab.ledger) ...[
                    const SizedBox(height: 12),
                    _SearchFilterRow(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      onFilterTap: () => _openFilterSheet(provider),
                      activeFilterCount: _filter.activeCount,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_subTab == _SubTab.transactions) ...[
            if (_isSelecting)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _SelectionBar(
                    count: _selectedRefs.length,
                    onDelete: () => _deleteSelected(provider),
                    onClear: _clearSelection,
                  ),
                ),
              ),
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
          ] else if (_subTab == _SubTab.ledger) ...[
            ..._buildLedgerSlivers(provider),
          ] else
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Analytics',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
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

    final selected = _selectedRefs.contains(transaction.reference);
    return _TransactionTile(
      bank: bankLabel,
      category: categoryLabel,
      isCategorized: isCategorized,
      amount: _amountLabel(transaction.amount, isCredit: isCredit),
      amountColor: isCredit ? AppColors.incomeSuccess : AppColors.red,
      name: _transactionCounterparty(transaction),
      selected: selected,
      onTap: _isSelecting
          ? () => _toggleSelection(transaction)
          : () => _openTransactionCategorySheet(provider, transaction),
      onLongPress: () => _toggleSelection(transaction),
    );
  }

  Future<void> _openTransactionCategorySheet(
    TransactionProvider provider,
    Transaction transaction,
  ) async {
    await showTransactionDetailsSheet(
      context: context,
      transaction: transaction,
      provider: provider,
    );
  }

  List<Widget> _buildLedgerSlivers(TransactionProvider provider) {
    // Sort all transactions by time ascending for ledger view
    final allTxns = List<Transaction>.from(provider.allTransactions)
      ..sort((a, b) {
        final aTime = _parseTransactionTime(a.time);
        final bTime = _parseTransactionTime(b.time);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

    // Apply date range filter and find starting balance in one pass
    double? startingBalance;
    DateTime? startingBalanceDate;
    final filtered = <Transaction>[];

    for (int i = 0; i < allTxns.length; i++) {
      final txn = allTxns[i];
      final dt = _parseTransactionTime(txn.time);

      bool inRange = true;
      if (_ledgerStartDate != null && dt != null) {
        final start = DateTime(
          _ledgerStartDate!.year,
          _ledgerStartDate!.month,
          _ledgerStartDate!.day,
        );
        if (dt.isBefore(start)) inRange = false;
      }
      if (_ledgerEndDate != null && dt != null) {
        final endOfDay = DateTime(
          _ledgerEndDate!.year,
          _ledgerEndDate!.month,
          _ledgerEndDate!.day,
          23,
          59,
          59,
        );
        if (dt.isAfter(endOfDay)) inRange = false;
      }

      if (inRange) {
        filtered.add(txn);
      }
    }

    // Compute starting balance from the oldest transaction in the range
    if (filtered.isNotEmpty) {
      final oldest = filtered.last; // descending → last is oldest
      final oldestIdx = allTxns.indexOf(oldest);
      startingBalanceDate = _parseTransactionTime(oldest.time);

      // Find the chronologically previous transaction (next index in desc list)
      for (int j = oldestIdx + 1; j < allTxns.length; j++) {
        final prevBal =
            double.tryParse(allTxns[j].currentBalance ?? '');
        if (prevBal != null) {
          startingBalance = prevBal;
          break;
        }
      }
      // Fallback: derive from oldest transaction
      if (startingBalance == null) {
        final oldestBal =
            double.tryParse(oldest.currentBalance ?? '');
        if (oldestBal != null) {
          if (oldest.type == 'DEBIT') {
            startingBalance = oldestBal + oldest.amount;
          } else {
            startingBalance = oldestBal - oldest.amount;
          }
        }
      }
    }

    // Build flat list: date headers (String) + transactions interleaved
    final flatItems = <Object>[];
    String? lastDateKey;
    for (final txn in filtered) {
      final dt = _parseTransactionTime(txn.time);
      final key = dt != null ? _formatDateHeader(dt) : 'Unknown Date';
      if (key != lastDateKey) {
        flatItems.add(key);
        lastDateKey = key;
      }
      flatItems.add(_LedgerFlatItem(txn));
    }

    return [
      // Date pickers
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _LedgerDatePickerRow(
            startDate: _ledgerStartDate,
            endDate: _ledgerEndDate,
            onStartDateChanged: (d) =>
                setState(() => _ledgerStartDate = d),
            onEndDateChanged: (d) => setState(() => _ledgerEndDate = d),
          ),
        ),
      ),
      // Starting balance
      if (startingBalance != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              '${startingBalanceDate != null ? _formatDateHeader(startingBalanceDate) : ''} Starting Balance: ${_showAccountBalances ? 'ETB ${formatNumberWithComma(startingBalance)}' : '*****'}',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      // Timeline content
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
        SliverList.builder(
          itemCount: flatItems.length,
          itemBuilder: (context, index) {
            final item = flatItems[index];
            if (item is String) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                    const SizedBox(width: 12),
                    Text(
                      item,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }
            final entry = item as _LedgerFlatItem;
            // Only hide line after the very last transaction overall
            final isLastOverall = index == flatItems.length - 1;
            final lineColor = AppColors.borderColor(context);
            return Padding(
              padding: const EdgeInsets.only(left: 20, right: 20),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 10,
                      child: Center(
                        child: Container(
                          width: 1.5,
                          color: isLastOverall ? Colors.transparent : lineColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openTransactionCategorySheet(
                            provider, entry.transaction),
                        behavior: HitTestBehavior.opaque,
                        child: _LedgerTransactionEntry(
                          transaction: entry.transaction,
                          showBalance: _showAccountBalances,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
    ];
  }

  Widget _buildAccountsContent(TransactionProvider provider) {
    final summary = provider.summary;
    final bankSummaries = provider.bankSummaries;
    final accountSummaries = provider.accountSummaries;
    final syncStatusService = context.watch<AccountSyncStatusService>();
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
                syncStatusService: syncStatusService,
                onBankTap: (bankId) =>
                    setState(() => _selectedBankId = bankId),
                onAddAccount: _showAddAccountSheet,
              )
            else
              ...accounts.map((account) {
                final isCash =
                    account.bankId == CashConstants.bankId;
                final acctTxnCount = account.totalTransactions.toInt();
                return _AccountCard(
                  account: account,
                  bankId: _selectedBankId!,
                  isCash: isCash,
                  isExpanded:
                      _expandedAccountNumber == account.accountNumber,
                  showBalance: _showAccountBalances,
                  transactionCount: acctTxnCount,
                  syncStatus: isCash
                      ? null
                      : syncStatusService.getSyncStatus(
                          account.accountNumber,
                          account.bankId,
                        ),
                  syncProgress: isCash
                      ? null
                      : syncStatusService.getSyncProgress(
                          account.accountNumber,
                          account.bankId,
                        ),
                  onToggleExpand: () => setState(() {
                    _expandedAccountNumber =
                        _expandedAccountNumber == account.accountNumber
                            ? null
                            : account.accountNumber;
                  }),
                  onDelete: isCash
                      ? null
                      : () => _showDeleteConfirmation(account),
                  onCashExpense: isCash ? _showCashExpenseSheet : null,
                  onCashIncome: isCash ? _showCashIncomeSheet : null,
                  onSetCashAmount: isCash ? _showSetCashAmountSheet : null,
                  onClearCash: isCash ? _confirmClearCashWallet : null,
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

  bool _isAdjustingCash = false;

  String _cashAccountNumber() {
    final provider =
        Provider.of<TransactionProvider>(context, listen: false);
    final cashAccounts = provider.accountSummaries
        .where((a) => a.bankId == CashConstants.bankId)
        .toList();
    return cashAccounts.isNotEmpty
        ? cashAccounts.first.accountNumber
        : CashConstants.defaultAccountNumber;
  }

  void _showCashExpenseSheet() {
    final provider =
        Provider.of<TransactionProvider>(context, listen: false);
    showAddCashTransactionSheet(
      context: context,
      provider: provider,
      accountNumber: _cashAccountNumber(),
      initialIsDebit: true,
    );
  }

  void _showCashIncomeSheet() {
    final provider =
        Provider.of<TransactionProvider>(context, listen: false);
    showAddCashTransactionSheet(
      context: context,
      provider: provider,
      accountNumber: _cashAccountNumber(),
      initialIsDebit: false,
    );
  }

  void _showSetCashAmountSheet() async {
    final provider =
        Provider.of<TransactionProvider>(context, listen: false);
    final cashSummaries = provider.accountSummaries
        .where((a) => a.bankId == CashConstants.bankId)
        .toList();
    final currentBalance = cashSummaries.isNotEmpty
        ? cashSummaries.fold<double>(0.0, (sum, a) => sum + a.balance)
        : 0.0;

    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SetCashAmountSheet(currentBalance: currentBalance),
    );
    if (result != null) {
      _applyCashTarget(result);
    }
  }

  void _confirmClearCashWallet() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardColor(dialogContext),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear Cash Wallet',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(dialogContext),
          ),
        ),
        content: Text(
          'This will set your cash wallet balance to zero.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary(dialogContext)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary(dialogContext))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _applyCashTarget(0);
            },
            child: Text('Clear',
                style: TextStyle(
                    color: Colors.red[600], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _applyCashTarget(double targetBalance) async {
    if (_isAdjustingCash) return;
    setState(() => _isAdjustingCash = true);

    try {
      final provider =
          Provider.of<TransactionProvider>(context, listen: false);
      final delta = await provider.setCashWalletBalance(
        targetBalance: targetBalance,
        accountNumber: _cashAccountNumber(),
      );

      if (!mounted) return;

      if (delta.abs() < 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cash wallet is already at that amount'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final direction = delta > 0 ? 'increased' : 'decreased';
        final amount = formatNumberWithComma(delta.abs());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cash wallet $direction by ETB $amount'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update cash wallet: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdjustingCash = false);
    }
  }

  void _showAddAccountSheet({int? bankId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddAccountSheet(
        initialBankId: bankId ?? _selectedBankId,
        onAccountAdded: () {
          Provider.of<TransactionProvider>(context, listen: false).loadData();
        },
      ),
    );
  }

  void _showDeleteConfirmation(AccountSummary account) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.cardColor(dialogContext),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Delete Account',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(dialogContext),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this account?',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary(dialogContext)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background(dialogContext),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account: ${account.accountNumber}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary(dialogContext)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Holder: ${account.accountHolderName}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary(dialogContext)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bank: ${_getBankName(account.bankId)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary(dialogContext)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This action cannot be undone.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary(dialogContext)),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _deleteAccount(account);
              },
              child: Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount(AccountSummary account) async {
    try {
      final accountRepo = AccountRepository();
      await accountRepo.deleteAccount(account.accountNumber, account.bankId);

      if (mounted) {
        Provider.of<TransactionProvider>(context, listen: false).loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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
    final bank = _assetBanks.firstWhere((b) => b.id == bankId);
    return bank.shortName;
  } catch (_) {
    try {
      final bank = AppConstants.banks.firstWhere((b) => b.id == bankId);
      return bank.shortName;
    } catch (_) {
      return 'Bank $bankId';
    }
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

String _formatLedgerTime(DateTime dt) {
  final hour = dt.hour;
  final minute = dt.minute;
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
}

String _getBankImage(int bankId) {
  if (bankId == CashConstants.bankId) return 'assets/images/eth_birr.png';
  try {
    return _assetBanks.firstWhere((b) => b.id == bankId).image;
  } catch (_) {
    try {
      return AppConstants.banks.firstWhere((b) => b.id == bankId).image;
    } catch (_) {
      return '';
    }
  }
}

String _getBankName(int bankId) {
  if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
  try {
    return _assetBanks.firstWhere((b) => b.id == bankId).shortName;
  } catch (_) {
    try {
      return AppConstants.banks.firstWhere((b) => b.id == bankId).shortName;
    } catch (_) {
      return 'Bank $bankId';
    }
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
              color: selected ? AppColors.primaryLight : AppColors.borderColor(context),
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primaryLight : AppColors.textSecondary(context),
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
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
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
                    color: AppColors.textSecondary(context),
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
                    Text(
                      ' / 100',
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
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
                    color: AppColors.textSecondary(context),
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
                    Text(
                      ' | ',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
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
        color: AppColors.mutedFill(context).withValues(alpha: 0.6),
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
            color: selected ? AppColors.white : AppColors.textSecondary(context),
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
              color: AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
              decoration: InputDecoration(
                hintText: 'Search Transactions',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary(context),
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
                      : AppColors.cardColor(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        hasFilters ? AppColors.primaryDark : AppColors.borderColor(context),
                  ),
                ),
                child: Icon(
                  Icons.filter_list,
                  color:
                      hasFilters ? AppColors.primaryDark : AppColors.textSecondary(context),
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
                size: 20, color: AppColors.slate600),
          ),
        ],
      ),
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
        style: TextStyle(
          color: AppColors.isDark(context) ? AppColors.slate400 : AppColors.slate700,
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
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _TransactionTile({
    required this.bank,
    required this.category,
    required this.isCategorized,
    required this.amount,
    required this.amountColor,
    required this.name,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primaryLight.withValues(alpha: 0.08)
            : AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppColors.primaryLight : AppColors.borderColor(context),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              if (selected) ...[
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
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
                      color: AppColors.textSecondary(context),
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
        border: Border.all(color: AppColors.textTertiary(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.isDark(context) ? AppColors.slate400 : AppColors.slate700,
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
            color: AppColors.cardColor(context),
            borderRadius: BorderRadius.circular(10),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Center(
        child: Text(
          'No transactions found',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _LedgerFlatItem {
  final Transaction transaction;
  const _LedgerFlatItem(this.transaction);
}

// ─── Ledger Widgets ───────────────────────────────────────────────

class _LedgerDatePickerRow extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime?> onStartDateChanged;
  final ValueChanged<DateTime?> onEndDateChanged;

  const _LedgerDatePickerRow({
    required this.startDate,
    required this.endDate,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LedgerDateField(
            label: 'START DATE:',
            date: startDate,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: startDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) onStartDateChanged(picked);
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _LedgerDateField(
            label: 'END DATE:',
            date: endDate,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: endDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) onEndDateChanged(picked);
            },
          ),
        ),
      ],
    );
  }
}

class _LedgerDateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _LedgerDateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateText =
        date != null ? _formatDateHeader(date!) : 'Select date';

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Text(
              dateText,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerTransactionEntry extends StatelessWidget {
  final Transaction transaction;
  final bool showBalance;

  const _LedgerTransactionEntry({
    required this.transaction,
    required this.showBalance,
  });

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.type == 'CREDIT';
    final amountColor =
        isCredit ? AppColors.incomeSuccess : AppColors.red;
    final arrow = isCredit ? '↓' : '↑';
    final sign = isCredit ? '+' : '-';

    final amount = transaction.amount;
    final amountStr =
        formatNumberAbbreviated(amount).replaceAll('k', 'K');

    final name = _transactionCounterparty(transaction);
    final bankName = _bankLabel(transaction.bankId);

    final dt = _parseTransactionTime(transaction.time);
    final timeStr = dt != null ? _formatLedgerTime(dt) : '';

    final parsedBalance =
        double.tryParse(transaction.currentBalance ?? '');
    final balanceStr = showBalance && parsedBalance != null
        ? formatNumberAbbreviated(parsedBalance).replaceAll('k', 'K')
        : '*****';

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              timeStr,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$arrow  ${sign}ETB $amountStr',
                  style: TextStyle(
                    color: amountColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Balance: $balanceStr',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            bankName,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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

class _BankGrid extends StatefulWidget {
  final List<BankSummary> bankSummaries;
  final bool showBalance;
  final AccountSyncStatusService syncStatusService;
  final ValueChanged<int> onBankTap;
  final void Function({int? bankId}) onAddAccount;

  const _BankGrid({
    required this.bankSummaries,
    required this.showBalance,
    required this.syncStatusService,
    required this.onBankTap,
    required this.onAddAccount,
  });

  @override
  State<_BankGrid> createState() => _BankGridState();
}

class _BankGridState extends State<_BankGrid> with WidgetsBindingObserver {
  final BankDetectionService _detectionService = BankDetectionService();
  List<DetectedBank> _detectedBanks = [];
  bool _awaitingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDetectedBanks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(_BankGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload when the registered bank list changes (account added/removed)
    if (oldWidget.bankSummaries.length != widget.bankSummaries.length) {
      _loadDetectedBanks(forceRefresh: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPermission) {
      _awaitingPermission = false;
      _loadDetectedBanks();
    }
  }

  Future<void> _loadDetectedBanks({bool forceRefresh = false}) async {
    try {
      final permissionStatus = await Permission.sms.status;
      if (!permissionStatus.isGranted) return;

      final banks = await _detectionService.detectUnregisteredBanks(
        forceRefresh: forceRefresh,
      );
      banks.sort((a, b) =>
          a.bank.shortName.toLowerCase().compareTo(b.bank.shortName.toLowerCase()));
      if (mounted) setState(() => _detectedBanks = banks);
    } catch (_) {
      // Silently fail — detected banks are a nice-to-have
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      ...widget.bankSummaries.map((bank) {
        final isCash = bank.bankId == CashConstants.bankId;
        return _BankGridCard(
          bankId: bank.bankId,
          isCash: isCash,
          accountCount: bank.accountCount,
          balance: bank.totalBalance,
          showBalance: widget.showBalance,
          syncProgress: isCash
              ? null
              : widget.syncStatusService.getSyncProgressForBank(bank.bankId),
          onTap: () => widget.onBankTap(bank.bankId),
        );
      }),
      ..._detectedBanks.map((detected) => _DetectedBankCard(
            detected: detected,
            onTap: () => widget.onAddAccount(bankId: detected.bank.id),
          )),
      _AddAccountCard(onTap: () => widget.onAddAccount()),
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
  final bool isCash;
  final int accountCount;
  final double balance;
  final bool showBalance;
  final double? syncProgress;
  final VoidCallback onTap;

  const _BankGridCard({
    required this.bankId,
    required this.isCash,
    required this.accountCount,
    required this.balance,
    required this.showBalance,
    this.syncProgress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bankName = isCash ? 'Cash Wallet' : _getBankName(bankId);
    final bankImage = _getBankImage(bankId);
    final balanceLabel =
        showBalance ? 'ETB ${_formatEtbAbbrev(balance)}' : '*****';
    final subtitleLabel = isCash
        ? 'On-hand cash'
        : '$accountCount Account${accountCount == 1 ? '' : 's'}';
    final isSyncing = syncProgress != null;
    final normalizedProgress = syncProgress?.clamp(0.0, 1.0).toDouble();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primaryLight.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          bankName,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
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
                    subtitleLabel,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isSyncing
                        ? 'Syncing ${(normalizedProgress! * 100).round()}%'
                        : balanceLabel,
                    style: TextStyle(
                      color: isSyncing
                          ? AppColors.primaryLight
                          : showBalance
                              ? (AppColors.isDark(context) ? AppColors.slate400 : AppColors.slate700)
                              : AppColors.textSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: (isSyncing || showBalance) ? 0 : 2,
                    ),
                  ),
                ],
              ),
            ),
            if (isSyncing)
              LinearProgressIndicator(
                value: normalizedProgress,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(AppColors.primaryLight),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddAccountCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddAccountCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderColor(context), style: BorderStyle.solid),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Add\nAccount',
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
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
                    border: Border.all(color: AppColors.mutedFill(context), width: 1.5),
                  ),
                  child: Icon(
                    Icons.add,
                    color: AppColors.textSecondary(context),
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Register new',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Bank Account',
              style: TextStyle(
                color: AppColors.textSecondary(context),
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

class _DetectedBankCard extends StatelessWidget {
  final DetectedBank detected;
  final VoidCallback onTap;

  const _DetectedBankCard({
    required this.detected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bankImage = _getBankImage(detected.bank.id);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    detected.bank.shortName,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
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
              '${detected.messageCount} messages',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 12,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Tap to add',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLight,
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
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderColor(context)),
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
                final isCash = bank.bankId == CashConstants.bankId;
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
  final bool isCash;
  final bool isExpanded;
  final bool showBalance;
  final int transactionCount;
  final String? syncStatus;
  final double? syncProgress;
  final VoidCallback onToggleExpand;
  final VoidCallback? onDelete;
  final VoidCallback? onCashExpense;
  final VoidCallback? onCashIncome;
  final VoidCallback? onSetCashAmount;
  final VoidCallback? onClearCash;

  const _AccountCard({
    required this.account,
    required this.bankId,
    required this.isCash,
    required this.isExpanded,
    required this.showBalance,
    required this.transactionCount,
    required this.syncStatus,
    required this.syncProgress,
    required this.onToggleExpand,
    this.onDelete,
    this.onCashExpense,
    this.onCashIncome,
    this.onSetCashAmount,
    this.onClearCash,
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
    final normalizedProgress = syncProgress == null
        ? null
        : syncProgress!.clamp(0.0, 1.0).toDouble();
    final syncPercentLabel = normalizedProgress == null
        ? null
        : '${(normalizedProgress * 100).round()}%';
    final primaryValueLabel =
        syncStatus != null ? (syncPercentLabel ?? '0%') : balanceLabel;

    final accountLabel =
        isCash ? 'On-hand cash' : account.accountNumber;
    final holderLabel =
        isCash ? 'Personal funds' : account.accountHolderName.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: InkWell(
        onTap: onToggleExpand,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Padding(
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
                          accountLabel,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          holderLabel,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (syncStatus != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            syncStatus!,
                            style: TextStyle(
                              color: AppColors.primaryLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (isExpanded) ...[
                          const SizedBox(height: 4),
                          Text(
                            primaryValueLabel,
                            style: TextStyle(
                              color: syncStatus != null
                                  ? AppColors.primaryLight
                                  : AppColors.textPrimary(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary(context),
                    size: 22,
                  ),
                ],
              ),
              if (!isExpanded) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 56),
                    Text(
                      primaryValueLabel,
                      style: TextStyle(
                        color: syncStatus != null
                            ? AppColors.primaryLight
                            : showBalance
                                ? (AppColors.isDark(context) ? AppColors.slate400 : AppColors.slate700)
                            : AppColors.textSecondary(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing:
                            (syncPercentLabel != null || showBalance) ? 0 : 2,
                      ),
                    ),
                  ],
                ),
              ],
              if (isExpanded) ...[
                const SizedBox(height: 14),
                Container(height: 1, color: AppColors.borderColor(context)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRANSACTIONS',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatCount(transactionCount),
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
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
                        Text(
                          'IN & OUT',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
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
                            Text(
                              ' | ',
                              style: TextStyle(
                                color: AppColors.textTertiary(context),
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
                // Delete for non-cash accounts
                if (onDelete != null) ...[
                  const SizedBox(height: 14),
                  Container(height: 1, color: AppColors.borderColor(context)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onDelete,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: AppColors.red.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Remove Account',
                          style: TextStyle(
                            color: AppColors.red.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              // Cash wallet actions – always visible below the card
              if (isCash) ...[
                const SizedBox(height: 12),
                Container(height: 1, color: AppColors.borderColor(context)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _CashActionButton(
                        label: 'Expense',
                        icon: Icons.remove_circle_outline,
                        color: AppColors.red,
                        onTap: onCashExpense,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CashActionButton(
                        label: 'Income',
                        icon: Icons.add_circle_outline,
                        color: AppColors.incomeSuccess,
                        onTap: onCashIncome,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _CashActionButton(
                        label: 'Clear',
                        icon: Icons.cleaning_services_outlined,
                        color: AppColors.red,
                        outlined: true,
                        onTap: onClearCash,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CashActionButton(
                        label: 'Set amount',
                        icon: Icons.tune,
                        color: AppColors.primaryDark,
                        outlined: true,
                        onTap: onSetCashAmount,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
            ),
            // Sync progress bar — sits at the bottom edge of the card
            if (syncStatus != null)
              LinearProgressIndicator(
                value: normalizedProgress,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(AppColors.primaryLight),
              ),
          ],
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
        decoration: BoxDecoration(
          color: AppColors.mutedFill(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.account_balance,
          size: size * 0.5,
          color: AppColors.textSecondary(context),
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
          color: AppColors.mutedFill(context),
          child: Icon(
            Icons.account_balance,
            size: size * 0.5,
            color: AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

class _CashActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool outlined;
  final VoidCallback? onTap;

  const _CashActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.outlined = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: outlined ? AppColors.cardColor(context) : color,
          borderRadius: BorderRadius.circular(10),
          border: outlined ? Border.all(color: color.withValues(alpha: 0.5)) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: outlined ? color : AppColors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: outlined ? color : AppColors.white,
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

// ─── Set Cash Amount Sheet ───────────────────────────────────────

class _SetCashAmountSheet extends StatefulWidget {
  final double currentBalance;

  const _SetCashAmountSheet({required this.currentBalance});

  @override
  State<_SetCashAmountSheet> createState() => _SetCashAmountSheetState();
}

class _SetCashAmountSheetState extends State<_SetCashAmountSheet> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final initial = widget.currentBalance > 0
        ? widget.currentBalance.toStringAsFixed(2)
        : '';
    _controller = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? _parseAmount(String raw) {
    final cleaned = raw.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              'Set cash wallet amount',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                labelText: 'Target balance',
                prefixText: 'ETB ',
                prefixStyle: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                hintText: '0.00',
                filled: true,
                fillColor: AppColors.surfaceColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primaryLight),
                ),
              ),
              validator: (value) {
                final parsed = _parseAmount(value ?? '');
                if (parsed == null) return 'Enter a valid amount';
                if (parsed < 0) return 'Amount cannot be negative';
                return null;
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: AppColors.borderColor(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      if (!_formKey.currentState!.validate()) return;
                      final parsed = _parseAmount(_controller.text);
                      Navigator.pop(context, parsed);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Set amount',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ─── Add Account Sheet ───────────────────────────────────────────

class _AddAccountSheet extends StatefulWidget {
  final int? initialBankId;
  final VoidCallback onAccountAdded;

  const _AddAccountSheet({
    this.initialBankId,
    required this.onAccountAdded,
  });

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final _accountNumberController = TextEditingController();
  final _holderNameController = TextEditingController();
  List<bank_model.Bank> _banks = [];
  int? _selectedBankId;
  bool _isFormValid = false;
  bool _isSubmitting = false;
  bool _syncPreviousSms = true;

  @override
  void initState() {
    super.initState();
    _accountNumberController.addListener(_validateForm);
    _holderNameController.addListener(_validateForm);
    _loadBanks();
  }

  @override
  void dispose() {
    _accountNumberController.dispose();
    _holderNameController.dispose();
    super.dispose();
  }

  void _loadBanks() {
    final banks = AllBanksFromAssets.getAllBanks();
    if (mounted) {
      setState(() {
        _banks = banks;
        if (banks.isEmpty) {
          _selectedBankId = null;
          return;
        }
        final hasInitialBank = widget.initialBankId != null &&
            banks.any((bank) => bank.id == widget.initialBankId);
        _selectedBankId = hasInitialBank ? widget.initialBankId : banks.first.id;
      });
    }
  }

  void _validateForm() {
    setState(() {
      _isFormValid = _accountNumberController.text.trim().isNotEmpty &&
          _holderNameController.text.trim().isNotEmpty;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedBankId == null) return;
    final accountNumber = _accountNumberController.text.trim();
    final accountHolderName = _holderNameController.text.trim();
    final bankId = _selectedBankId!;
    final messenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<TransactionProvider>(context, listen: false);

    setState(() => _isSubmitting = true);

    try {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      widget.onAccountAdded();

      final service = AccountRegistrationService();
      final account = await service.registerAccount(
        accountNumber: accountNumber,
        accountHolderName: accountHolderName,
        bankId: bankId,
        syncPreviousSms: _syncPreviousSms,
        onSyncComplete: () {
          provider.loadData();
        },
      );

      if (account == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('This account already exists'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _syncPreviousSms
                ? "Adding your account. You can leave the app, we'll notify you when it's done."
                : 'Account added successfully',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      provider.loadData();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error adding account: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
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

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Account',
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceColor(context),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        color: AppColors.textSecondary(context),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Bank selector
              Text(
                'Bank',
                style: TextStyle(
                  color: AppColors.isDark(context) ? AppColors.slate400 : AppColors.slate700,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showBankPicker,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Row(
                    children: [
                      if (_selectedBankId != null) ...[
                        _BankLogoCircle(
                          imagePath: _getBankImage(_selectedBankId!),
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          _selectedBankId != null
                              ? _getBankName(_selectedBankId!)
                              : 'Select a bank',
                          style: TextStyle(
                            color: _selectedBankId != null
                                ? AppColors.textPrimary(context)
                                : AppColors.textTertiary(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Account number
              Text(
                'Account Number',
                style: TextStyle(
                  color: AppColors.isDark(context) ? AppColors.slate400 : AppColors.slate700,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _accountNumberController,
                keyboardType: TextInputType.number,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter account number',
                  hintStyle: TextStyle(color: AppColors.textTertiary(context)),
                  filled: true,
                  fillColor: AppColors.surfaceColor(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderColor(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderColor(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primaryLight),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 20),

              // Account holder name
              Text(
                'Account Holder Name',
                style: TextStyle(
                  color: AppColors.isDark(context) ? AppColors.slate400 : AppColors.slate700,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _holderNameController,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter account holder name',
                  hintStyle: TextStyle(color: AppColors.textTertiary(context)),
                  filled: true,
                  fillColor: AppColors.surfaceColor(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderColor(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderColor(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primaryLight),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 20),

              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceColor(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderColor(context)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.sms_outlined,
                      color: AppColors.textSecondary(context),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sync SMS History',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Import past transactions for this account',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _syncPreviousSms,
                      onChanged: (value) {
                        setState(() => _syncPreviousSms = value);
                      },
                      activeColor: AppColors.primaryDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.borderColor(context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed:
                          (_isFormValid && !_isSubmitting) ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: AppColors.white,
                        elevation: 0,
                        disabledBackgroundColor: AppColors.mutedFill(context),
                        disabledForegroundColor: AppColors.textTertiary(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          : const Text(
                              'Add Account',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showBankPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: AppColors.cardColor(sheetContext),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slate400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Bank',
                style: TextStyle(
                  color: AppColors.textPrimary(sheetContext),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.85,
                ),
                itemCount: _banks.length,
                itemBuilder: (context, index) {
                  final bank = _banks[index];
                  final isSelected = _selectedBankId == bank.id;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedBankId = bank.id);
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryLight.withValues(alpha: 0.1)
                            : AppColors.surfaceColor(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryLight
                              : AppColors.borderColor(context),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _BankLogoCircle(
                            imagePath: bank.image,
                            size: 44,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            bank.shortName,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primaryDark
                                  : AppColors.textPrimary(context),
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
      builder: (ctx, child) {
        final dark = AppColors.isDark(ctx);
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? ColorScheme.dark(
                    primary: AppColors.primaryLight,
                    onPrimary: AppColors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.white,
                  )
                : const ColorScheme.light(
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
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                Expanded(
                  child: Text(
                    'Filter Transactions',
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: AppColors.textSecondary(context)),
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
                            foregroundColor: AppColors.textSecondary(context),
                            side: BorderSide(color: AppColors.borderColor(context)),
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
      style: TextStyle(
        color: AppColors.textSecondary(context),
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
          color: selected ? AppColors.primaryDark : AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryDark : AppColors.borderColor(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.white : AppColors.textSecondary(context),
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
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                  color:
                      value != null ? AppColors.textPrimary(context) : AppColors.textTertiary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.textTertiary(context),
                ),
              )
            else
              Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
          ],
        ),
      ),
    );
  }
}
