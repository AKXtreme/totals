import 'dart:math' as math;

import 'package:flutter/foundation.dart' hide Category;
import 'package:totals/models/account.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/budget_alert_service.dart';
import 'package:totals/services/receiver_category_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/telebirr_bank_transfer_service.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/utils/text_utils.dart';

class TransactionTotals {
  final double income;
  final double expense;

  const TransactionTotals({
    required this.income,
    required this.expense,
  });

  const TransactionTotals.zero()
      : income = 0.0,
        expense = 0.0;
}

class TransactionTrendSeries {
  final List<double> incomePoints;
  final List<double> expensePoints;
  final double maxValue;
  final double totalIncome;
  final double totalExpense;
  final int days;

  const TransactionTrendSeries({
    required this.incomePoints,
    required this.expensePoints,
    required this.maxValue,
    required this.totalIncome,
    required this.totalExpense,
    required this.days,
  });

  factory TransactionTrendSeries.empty(int days) {
    return TransactionTrendSeries(
      incomePoints: List<double>.filled(days, 0),
      expensePoints: List<double>.filled(days, 0),
      maxValue: 0,
      totalIncome: 0,
      totalExpense: 0,
      days: days,
    );
  }
}

class TransactionProvider with ChangeNotifier {
  final TransactionRepository _transactionRepo = TransactionRepository();
  final AccountRepository _accountRepo = AccountRepository();
  final CategoryRepository _categoryRepo = CategoryRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  final BudgetAlertService _budgetAlertService = BudgetAlertService();
  final TelebirrBankTransferService _telebirrMatchService =
      TelebirrBankTransferService();

  List<Transaction> _transactions = [];
  List<Account> _accounts = [];
  List<Category> _categories = [];
  Map<int, Category> _categoryById = {};
  Map<String, String> _selfTransferLabelByReference = {};
  Map<int, String> _bankNamesById = {
    CashConstants.bankId: CashConstants.bankName,
  };
  Map<int, String> _bankShortNamesById = {
    CashConstants.bankId: CashConstants.bankShortName,
  };

  // Summaries
  AllSummary? _summary;
  List<BankSummary> _bankSummaries = [];
  List<AccountSummary> _accountSummaries = [];

  bool _isLoading = false;
  String _searchKey = "";
  DateTime _selectedDate = DateTime.now();

  List<Transaction> _allTransactions = [];

  // Redesign home cached metrics
  List<Transaction> _todayTransactions = [];
  List<Transaction> _monthTransactions = [];
  TransactionTotals _todayTotals = const TransactionTotals.zero();
  TransactionTotals _weekTotals = const TransactionTotals.zero();
  TransactionTotals _monthTotals = const TransactionTotals.zero();
  TransactionTotals _thirtyDayTotals = const TransactionTotals.zero();
  int _selfTransferCount = 0;
  String _monthlyInsight =
      'No monthly activity yet. Keep using Totals to unlock insights.';
  TransactionTrendSeries _weekTrendSeries = TransactionTrendSeries.empty(7);
  TransactionTrendSeries _monthTrendSeries = TransactionTrendSeries.empty(30);
  int _dataVersion = 0;

  // Getters
  List<Transaction> get transactions => _transactions;
  List<Transaction> get allTransactions => _allTransactions;
  List<Category> get categories => _categories;
  bool get isLoading => _isLoading;
  AllSummary? get summary => _summary;
  List<BankSummary> get bankSummaries => _bankSummaries;
  List<AccountSummary> get accountSummaries => _accountSummaries;
  DateTime get selectedDate => _selectedDate;
  List<Transaction> get todayTransactions => _todayTransactions;
  List<Transaction> get monthTransactions => _monthTransactions;
  TransactionTotals get todayTotals => _todayTotals;
  TransactionTotals get weekTotals => _weekTotals;
  TransactionTotals get monthTotals => _monthTotals;
  TransactionTotals get thirtyDayTotals => _thirtyDayTotals;
  int get selfTransferCount => _selfTransferCount;
  String get monthlyInsight => _monthlyInsight;
  TransactionTrendSeries get weekTrendSeries => _weekTrendSeries;
  TransactionTrendSeries get monthTrendSeries => _monthTrendSeries;
  int get dataVersion => _dataVersion;
  Map<int, String> get bankNamesById => _bankNamesById;
  Map<int, String> get bankShortNamesById => _bankShortNamesById;

  String getBankName(int? bankId) {
    if (bankId == null) return 'Bank';
    if (bankId == CashConstants.bankId) return CashConstants.bankName;
    return _bankNamesById[bankId] ?? 'Bank $bankId';
  }

  String getBankShortName(int? bankId) {
    if (bankId == null) return 'Bank';
    if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
    return _bankShortNamesById[bankId] ?? 'Bank $bankId';
  }

  Category? getCategoryById(int? id) {
    if (id == null) return null;
    return _categoryById[id];
  }

  String? getSelfTransferLabel(Transaction transaction) {
    final existing = _selfTransferLabelByReference[transaction.reference];
    if (existing != null) return existing;
    if (_isManualSelfCategory(transaction)) {
      return transaction.type == 'CREDIT' ? 'to self' : 'from self';
    }
    return null;
  }

  bool isSelfTransfer(Transaction transaction) {
    return _isSelfTransfer(transaction);
  }

  bool _isSelfTransfer(Transaction transaction) {
    return _selfTransferLabelByReference.containsKey(transaction.reference) ||
        _isManualSelfCategory(transaction);
  }

  bool _isManualSelfCategory(Transaction transaction) {
    final category = _categoryById[transaction.categoryId];
    if (category == null) return false;
    return category.name.trim().toLowerCase() == 'self';
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _accounts = await _accountRepo.getAccounts();
      // print all the accounts
      print("debug: Accounts: ${_accounts.map((a) => a.balance).join(', ')}");

      _categories = await _categoryRepo.getCategories();
      _categoryById = {
        for (final c in _categories)
          if (c.id != null) c.id!: c,
      };

      _allTransactions = await _transactionRepo.getTransactions();
      print("debug: Transactions: ${_allTransactions.length}");

      final banks = await _bankConfigService.getBanks();
      _bankNamesById = {
        CashConstants.bankId: CashConstants.bankName,
        for (final bank in banks) bank.id: bank.name,
      };
      _bankShortNamesById = {
        CashConstants.bankId: CashConstants.bankShortName,
        for (final bank in banks) bank.id: bank.shortName,
      };
      final labels = _buildSelfTransferLabels(
        _telebirrMatchService.findMatches(_allTransactions, banks),
      );
      labels.addAll(_buildCashTransferLabels(_allTransactions));
      _selfTransferLabelByReference = labels;

      await _calculateSummaries(_allTransactions);
      _filterTransactions(_allTransactions);
      _recomputeRedesignHomeMetrics(_allTransactions);
      _dataVersion += 1;
    } catch (e) {
      print("debug: Error loading data: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateSearchKey(String key) {
    _searchKey = key;
    loadData(); // Reload to re-filter
  }

  void updateDate(DateTime date) {
    _selectedDate = date;
    loadData();
  }

  Future<void> _calculateSummaries(List<Transaction> allTransactions) async {
    final banks = await _bankConfigService.getBanks();
    final banksById = {for (final bank in banks) bank.id: bank};

    // Filter out transactions that don't have a matching account (orphaned transactions)
    final validTransactions = allTransactions.where((t) {
      if (t.bankId == null) return false;

      // Check if there's an account for this transaction's bank
      final bankAccounts = _accounts.where((a) => a.bank == t.bankId).toList();
      if (bankAccounts.isEmpty) return false;

      if (t.bankId == CashConstants.bankId) {
        return true;
      }

      final bank = banksById[t.bankId];
      if (bank == null) return false;

      // If transaction has accountNumber, verify it matches an account
      if (t.accountNumber != null && t.accountNumber!.isNotEmpty) {
        for (var account in bankAccounts) {
          bool matches = false;

          if (bank.uniformMasking == true) {
            // CBE: match last 4 digits
            matches = t.accountNumber!
                    .substring(t.accountNumber!.length - bank.maskPattern!) ==
                account.accountNumber.substring(
                    account.accountNumber.length - bank.maskPattern!);
          } else if (bank.uniformMasking == false) {
            // Awash/Telebirr: match by bankId only
            matches = true;
          } else {
            // Other banks: exact match
            matches = t.accountNumber == account.accountNumber;
          }

          if (matches) return true;
        }
        return false; // No matching account found
      } else {
        // NULL accountNumber - include only if single account for bank (legacy data)
        return bankAccounts.length == 1;
      }
    }).toList();

    // Group accounts by bank
    Map<int, List<Account>> groupedAccounts = {};
    for (var account in _accounts) {
      if (!groupedAccounts.containsKey(account.bank)) {
        groupedAccounts[account.bank] = [];
      }
      groupedAccounts[account.bank]!.add(account);
    }

    // Calculate Bank Summaries
    _bankSummaries = groupedAccounts.entries.map((entry) {
      final bankId = entry.key;
      final accounts = entry.value;

      // Filter transactions for this bank (using valid transactions only)
      var bankTransactions =
          validTransactions.where((t) => t.bankId == bankId).toList();

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      double cashBalance = 0.0;

      for (var t in bankTransactions) {
        double amount = t.amount;
        final skip = _isSelfTransfer(t) ||
            _categoryById[t.categoryId]?.uncategorized == true;
        if (t.type == "DEBIT") {
          cashBalance -= amount;
          if (!skip) {
            totalDebit += amount;
          }
        } else if (t.type == "CREDIT") {
          cashBalance += amount;
          if (!skip) {
            totalCredit += amount;
          }
        }
      }

      double settledBalance =
          accounts.fold(0.0, (sum, a) => sum + (a.settledBalance ?? 0.0));
      double pendingCredit =
          accounts.fold(0.0, (sum, a) => sum + (a.pendingCredit ?? 0.0));
      final isCashBank = bankId == CashConstants.bankId;
      double totalBalance = isCashBank
          ? accounts.fold(0.0, (sum, a) => sum + a.balance) + cashBalance
          : accounts.fold(0.0, (sum, a) => sum + a.balance);

      return BankSummary(
        bankId: bankId,
        totalCredit: totalCredit,
        totalDebit: totalDebit,
        settledBalance: settledBalance,
        pendingCredit: pendingCredit,
        totalBalance: totalBalance,
        accountCount: accounts.length,
      );
    }).toList();

    // Calculate Account Summaries
    _accountSummaries = _accounts.map((account) {
      // Logic for specific account transactions
      // Note: original logic had a specific condition for bankId == 1 handling substrings
      // Use validTransactions to ensure we only include transactions with matching accounts
      var accountTransactions = validTransactions.where((t) {
        bool bankMatch = t.bankId == account.bank;
        if (!bankMatch) return false;

        if (account.bank == CashConstants.bankId) {
          return true;
        }

        final bank = banksById[t.bankId];
        if (bank == null) return false;

        if (bank.uniformMasking == true) {
          // CBE check: last 4 digits

          return t.accountNumber
                  ?.substring(t.accountNumber!.length - bank.maskPattern!) ==
              account.accountNumber
                  .substring(account.accountNumber.length - bank.maskPattern!);
        } else {
          return t.bankId == account.bank;
        }
      }).toList();

      print("debug: Account Transactions: ${accountTransactions.length}");

      // Fallback: If this is the ONLY account for this bank, also include transactions with NULL account number
      // This handles legacy data or parsing failures where account wasn't captured.
      // NOTE: Skip this for banks that match by bankId only (uniformMasking == false)
      // because they already get all transactions via the else clause above
      if (account.bank != CashConstants.bankId) {
        try {
          final accountBank = banksById[account.bank];
          if (accountBank != null && accountBank.uniformMasking != false) {
            var bankAccounts =
                _accounts.where((a) => a.bank == account.bank).toList();
            if (bankAccounts.length == 1 && bankAccounts.first == account) {
              var orphanedTransactions = validTransactions
                  .where((t) =>
                      t.bankId == account.bank &&
                      (t.accountNumber == null || t.accountNumber!.isEmpty))
                  .toList();
              accountTransactions.addAll(orphanedTransactions);
            }
          }
        } catch (e) {
          // Bank not found in database, skip orphaned transactions fallback
        }
      }

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      double cashBalance = 0.0;
      for (var t in accountTransactions) {
        double amount = t.amount;
        final skip = _isSelfTransfer(t) ||
            _categoryById[t.categoryId]?.uncategorized == true;
        if (t.type == "DEBIT") {
          cashBalance -= amount;
          if (!skip) {
            totalDebit += amount;
          }
        }
        if (t.type == "CREDIT") {
          cashBalance += amount;
          if (!skip) {
            totalCredit += amount;
          }
        }
      }

      final isCashAccount = account.bank == CashConstants.bankId;
      final accountBalance =
          isCashAccount ? account.balance + cashBalance : account.balance;

      return AccountSummary(
        bankId: account.bank,
        accountNumber: account.accountNumber,
        accountHolderName: account.accountHolderName,
        totalTransactions: accountTransactions.length.toDouble(),
        totalCredit: totalCredit,
        totalDebit: totalDebit,
        settledBalance: account.settledBalance ?? 0.0,
        balance: accountBalance,
        pendingCredit: account.pendingCredit ?? 0.0,
      );
    }).toList();

    // Calculate AllSummary
    double grandTotalCredit =
        _bankSummaries.fold(0.0, (sum, b) => sum + b.totalCredit);
    double grandTotalDebit =
        _bankSummaries.fold(0.0, (sum, b) => sum + b.totalDebit);
    double grandTotalBalance =
        _bankSummaries.fold(0.0, (sum, b) => sum + b.totalBalance);

    _summary = AllSummary(
      totalCredit: grandTotalCredit,
      totalDebit: grandTotalDebit,
      banks: _accounts
          .length, // Original logic passed account length to banks? weird, but sticking to logic
      accounts: _accounts.length,
      totalBalance: grandTotalBalance,
    );
  }

  void _filterTransactions(List<Transaction> allTransactions) {
    // Filter by date and search key
    // Normalize selected date to start of day for comparison
    DateTime selectedDateStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    _transactions = allTransactions.where((t) {
      if (t.time == null) return false;

      // Parse ISO8601 date string
      try {
        DateTime? transactionDate;
        if (t.time!.contains('T')) {
          // ISO8601 format: "2024-01-15T10:30:00.000Z"
          transactionDate = DateTime.parse(t.time!);
        } else {
          // Try other formats if needed
          transactionDate = DateTime.tryParse(t.time!);
        }

        if (transactionDate == null) return false;

        // Normalize transaction date to start of day for comparison
        DateTime transactionDateStart = DateTime(
          transactionDate.year,
          transactionDate.month,
          transactionDate.day,
        );

        // Compare dates (ignoring time)
        bool dateMatch =
            transactionDateStart.isAtSameMomentAs(selectedDateStart);
        if (!dateMatch) return false;
      } catch (e) {
        print("debug: Error parsing transaction date: ${t.time}, error: $e");
        return false;
      }

      if (_searchKey.isEmpty) return true;

      return (t.creditor?.toLowerCase().contains(_searchKey.toLowerCase()) ??
              false) ||
          (t.reference.toLowerCase().contains(_searchKey.toLowerCase()));
    }).toList();
  }

  Transaction? _replaceTransactionLocally(Transaction updated) {
    Transaction? previous;

    List<Transaction> replaceInList(List<Transaction> source) {
      return source.map((transaction) {
        if (transaction.reference != updated.reference) return transaction;
        previous ??= transaction;
        return updated;
      }).toList();
    }

    _allTransactions = replaceInList(_allTransactions);
    _transactions = replaceInList(_transactions);
    _todayTransactions = replaceInList(_todayTransactions);
    _monthTransactions = replaceInList(_monthTransactions);
    return previous;
  }

  void _notifyOptimisticChange() {
    _dataVersion += 1;
    notifyListeners();
  }

  Future<void> _recomputeAfterTransactionMutation() async {
    await _calculateSummaries(_allTransactions);
    _filterTransactions(_allTransactions);
    _recomputeRedesignHomeMetrics(_allTransactions);
    _dataVersion += 1;
    notifyListeners();
  }

  Map<String, String> _buildSelfTransferLabels(
    List<TelebirrBankTransferMatch> matches,
  ) {
    final labels = <String, String>{};
    for (final match in matches) {
      labels[match.telebirrTransaction.reference] = 'from self';
      labels[match.bankTransaction.reference] = 'to self';
    }
    return labels;
  }

  Map<String, String> _buildCashTransferLabels(
    List<Transaction> transactions,
  ) {
    final labels = <String, String>{};
    final byReference = {
      for (final transaction in transactions)
        transaction.reference: transaction,
    };

    for (final transaction in transactions) {
      if (transaction.bankId != CashConstants.bankId) continue;
      final reference = transaction.reference;
      if (!reference.startsWith(CashConstants.atmReferencePrefix)) continue;

      final linkedReference =
          reference.substring(CashConstants.atmReferencePrefix.length);
      if (!byReference.containsKey(linkedReference)) continue;

      labels[reference] = 'from self';
      labels[linkedReference] = 'to self';
    }

    return labels;
  }

  void _recomputeRedesignHomeMetrics(List<Transaction> transactions) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    // Keep Home graph/weekly totals aligned with "How did I get here":
    // rolling 7-day window (today + previous 6 days), not calendar week.
    final weekStart = todayStart.subtract(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    final last30Start = todayStart.subtract(const Duration(days: 29));

    final todayEntries = <MapEntry<Transaction, DateTime>>[];
    final monthTransactions = <Transaction>[];

    var todayIncome = 0.0;
    var todayExpense = 0.0;
    var weekIncome = 0.0;
    var weekExpense = 0.0;
    var monthIncome = 0.0;
    var monthExpense = 0.0;
    var thirtyDayIncome = 0.0;
    var thirtyDayExpense = 0.0;
    var selfTransferCount = 0;

    final weekIncomeBuckets = List<double>.filled(7, 0);
    final weekExpenseBuckets = List<double>.filled(7, 0);
    final monthIncomeBuckets = List<double>.filled(30, 0);
    final monthExpenseBuckets = List<double>.filled(30, 0);

    final monthNetByOffset = List<double>.filled(4, 0);
    final monthHasTransactions = List<bool>.filled(4, false);

    for (final transaction in transactions) {
      final dt = _parseTransactionTimeLocal(transaction.time);
      if (dt == null) continue;

      final dateOnly = DateTime(dt.year, dt.month, dt.day);
      final isToday =
          !dateOnly.isBefore(todayStart) && dateOnly.isBefore(tomorrowStart);
      final isWeek =
          !dateOnly.isBefore(weekStart) && !dateOnly.isAfter(todayStart);
      final isMonth =
          !dateOnly.isBefore(monthStart) && dateOnly.isBefore(nextMonthStart);
      final isLast30 =
          !dateOnly.isBefore(last30Start) && !dateOnly.isAfter(todayStart);
      final isSelfTransfer = _isSelfTransfer(transaction);

      if (isToday) {
        todayEntries.add(MapEntry(transaction, dt));
      }
      if (isMonth) {
        monthTransactions.add(transaction);
      }
      if (isSelfTransfer) {
        selfTransferCount += 1;
      }

      final monthOffset =
          (now.year - dateOnly.year) * 12 + (now.month - dateOnly.month);
      if (monthOffset >= 0 && monthOffset <= 3) {
        monthHasTransactions[monthOffset] = true;
      }

      final isMisc =
          _categoryById[transaction.categoryId]?.uncategorized == true;

      if (isSelfTransfer || isMisc) continue;

      final isCredit = transaction.type == 'CREDIT';
      final isDebit = transaction.type == 'DEBIT';
      if (!isCredit && !isDebit) continue;

      final amount = transaction.amount;

      if (isToday) {
        if (isCredit) {
          todayIncome += amount;
        } else {
          todayExpense += amount;
        }
      }

      if (isWeek) {
        if (isCredit) {
          weekIncome += amount;
        } else {
          weekExpense += amount;
        }

        final weekIndex = dateOnly.difference(weekStart).inDays;
        if (weekIndex >= 0 && weekIndex < 7) {
          if (isCredit) {
            weekIncomeBuckets[weekIndex] += amount;
          } else {
            weekExpenseBuckets[weekIndex] += amount;
          }
        }
      }

      if (isMonth) {
        if (isCredit) {
          monthIncome += amount;
        } else {
          monthExpense += amount;
        }
      }

      if (isLast30) {
        if (isCredit) {
          thirtyDayIncome += amount;
        } else {
          thirtyDayExpense += amount;
        }

        final monthIndex = dateOnly.difference(last30Start).inDays;
        if (monthIndex >= 0 && monthIndex < 30) {
          if (isCredit) {
            monthIncomeBuckets[monthIndex] += amount;
          } else {
            monthExpenseBuckets[monthIndex] += amount;
          }
        }
      }

      if (monthOffset >= 0 && monthOffset <= 3) {
        monthNetByOffset[monthOffset] += isCredit ? amount : -amount;
      }
    }

    todayEntries.sort((a, b) => b.value.compareTo(a.value));

    _todayTransactions =
        todayEntries.map((entry) => entry.key).toList(growable: false);
    _monthTransactions = monthTransactions.toList(growable: false);
    _todayTotals =
        TransactionTotals(income: todayIncome, expense: todayExpense);
    _weekTotals = TransactionTotals(income: weekIncome, expense: weekExpense);
    _monthTotals =
        TransactionTotals(income: monthIncome, expense: monthExpense);
    _thirtyDayTotals = TransactionTotals(
      income: thirtyDayIncome,
      expense: thirtyDayExpense,
    );
    _selfTransferCount = selfTransferCount;
    _weekTrendSeries =
        _buildTrendSeriesFromBuckets(weekIncomeBuckets, weekExpenseBuckets);
    _monthTrendSeries =
        _buildTrendSeriesFromBuckets(monthIncomeBuckets, monthExpenseBuckets);
    _monthlyInsight =
        _buildMonthlyInsightFromNets(monthNetByOffset, monthHasTransactions);
  }

  DateTime? _parseTransactionTimeLocal(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  TransactionTrendSeries _buildTrendSeriesFromBuckets(
    List<double> income,
    List<double> expense,
  ) {
    final days = income.length;
    final totalIncome = income.fold<double>(0.0, (sum, value) => sum + value);
    final totalExpense = expense.fold<double>(0.0, (sum, value) => sum + value);
    final maxIncome = income.fold<double>(0.0, math.max);
    final maxExpense = expense.fold<double>(0.0, math.max);
    final maxValue = math.max(maxIncome, maxExpense);

    if (maxValue <= 0) {
      return TransactionTrendSeries.empty(days);
    }

    List<double> normalize(List<double> values) {
      return values
          .map((value) => (value / maxValue).clamp(0.0, 1.0).toDouble())
          .toList(growable: false);
    }

    return TransactionTrendSeries(
      incomePoints: normalize(income),
      expensePoints: normalize(expense),
      maxValue: maxValue,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      days: days,
    );
  }

  String _buildMonthlyInsightFromNets(
    List<double> monthNetByOffset,
    List<bool> monthHasTransactions,
  ) {
    final currentNet = monthNetByOffset[0];
    final priorNets = <double>[];

    for (int offset = 1; offset <= 3; offset++) {
      if (!monthHasTransactions[offset]) continue;
      priorNets.add(monthNetByOffset[offset]);
    }

    if (!monthHasTransactions[0] && priorNets.isEmpty) {
      return 'No monthly activity yet. Keep using Totals to unlock insights.';
    }

    final currentLabel = _formatEtbValue(currentNet.abs());
    final currentSign = currentNet >= 0 ? 'saved' : 'spent more than earned';

    if (priorNets.isEmpty) {
      return currentNet >= 0
          ? "You've saved ETB $currentLabel so far this month."
          : "You've spent ETB $currentLabel more than you earned this month.";
    }

    final avgNet =
        priorNets.reduce((sum, value) => sum + value) / priorNets.length;
    if (avgNet.abs() < 0.01) {
      return currentNet >= 0
          ? "You've saved ETB $currentLabel so far this month."
          : "You've spent ETB $currentLabel more than you earned this month.";
    }

    final deltaPercent = ((currentNet - avgNet).abs() / avgNet.abs()) * 100;
    final roundedPercent = deltaPercent.isFinite ? deltaPercent.round() : 0;
    final direction = currentNet >= avgNet ? 'better' : 'lower';

    return "You've $currentSign ETB $currentLabel this month, $roundedPercent% $direction than your 3-month average.";
  }

  String _formatEtbValue(double value) {
    final rounded = value.roundToDouble();
    return formatNumberWithComma(rounded).replaceFirst(RegExp(r'\\.00$'), '');
  }

  Future<double> setCashWalletBalance({
    required double targetBalance,
    required String accountNumber,
  }) async {
    if (targetBalance < 0) {
      throw ArgumentError('Target balance cannot be negative');
    }

    final cashAccounts =
        _accounts.where((a) => a.bank == CashConstants.bankId).toList();

    if (cashAccounts.isEmpty) {
      final accountToCreate = accountNumber.isNotEmpty
          ? accountNumber
          : CashConstants.defaultAccountNumber;
      await _accountRepo.saveAccount(
        Account(
          accountNumber: accountToCreate,
          bank: CashConstants.bankId,
          balance: targetBalance,
          accountHolderName: CashConstants.defaultAccountHolderName,
        ),
      );
      await loadData();
      await WidgetService.refreshWidget();
      return targetBalance;
    }

    final cashAccount = cashAccounts.firstWhere(
      (a) => a.accountNumber == accountNumber,
      orElse: () => cashAccounts.first,
    );

    final walletSummaries = _accountSummaries
        .where((summary) => summary.bankId == CashConstants.bankId)
        .toList();
    final currentBalance = walletSummaries.isNotEmpty
        ? walletSummaries.fold<double>(
            0.0, (sum, summary) => sum + summary.balance)
        : cashAccounts.fold<double>(
            0.0, (sum, account) => sum + account.balance);

    final delta = targetBalance - currentBalance;
    if (delta.abs() < 0.0001) return 0.0;

    final updatedCashAccount = Account(
      accountNumber: cashAccount.accountNumber,
      bank: cashAccount.bank,
      balance: cashAccount.balance + delta,
      accountHolderName: cashAccount.accountHolderName,
      settledBalance: cashAccount.settledBalance,
      pendingCredit: cashAccount.pendingCredit,
      profileId: cashAccount.profileId,
    );
    await _accountRepo.saveAccount(updatedCashAccount);
    await loadData();
    await WidgetService.refreshWidget();
    return delta;
  }

  // Method to handle new incoming SMS transaction
  Future<void> addTransaction(Transaction t) async {
    await _transactionRepo.saveTransaction(t);
    // Update account balance if match found
    // This logic was in onBackgroundMessage, we should probably centralize it here or in a Service
    // For now, simpler to just reload everything
    await loadData();
    await WidgetService.refreshWidget();
    // Check budget alerts after adding transaction (only for DEBIT transactions)
    if (t.type == 'DEBIT') {
      try {
        await _budgetAlertService.checkAndNotifyBudgetAlerts();
      } catch (e) {
        print("debug: Error checking budget alerts after transaction: $e");
      }
    }
  }

  Future<void> setCategoryForTransaction(
    Transaction transaction,
    Category category,
  ) async {
    if (category.id == null) return;
    final updated = transaction.copyWith(categoryId: category.id);
    final previous = _replaceTransactionLocally(updated);
    if (previous != null) {
      _notifyOptimisticChange();
    }

    try {
      await _transactionRepo.saveTransaction(updated);
    } catch (e) {
      if (previous != null) {
        _replaceTransactionLocally(previous);
        _notifyOptimisticChange();
      }
      rethrow;
    }

    // Save mapping if auto-categorization is enabled
    try {
      final isEnabled = await NotificationSettingsService.instance
          .isAutoCategorizeByReceiverEnabled();
      if (isEnabled && category.id != null) {
        // Save receiver mapping if receiver exists
        if (transaction.receiver != null && transaction.receiver!.isNotEmpty) {
          await ReceiverCategoryService.instance.saveMapping(
            transaction.receiver!,
            category.id!,
            'receiver',
          );
        }
        // Save creditor mapping if creditor exists
        if (transaction.creditor != null && transaction.creditor!.isNotEmpty) {
          await ReceiverCategoryService.instance.saveMapping(
            transaction.creditor!,
            category.id!,
            'creditor',
          );
        }
      }
    } catch (e) {
      print("debug: Error saving receiver/creditor category mapping: $e");
    }

    try {
      await _recomputeAfterTransactionMutation();
      await WidgetService.refreshWidget();
    } catch (e) {
      print("debug: Error recomputing state after categorizing: $e");
    }

    // Check budget alerts after categorizing transaction (only for DEBIT transactions)
    // Only check budgets for the specific category that was selected
    if (transaction.type == 'DEBIT' && category.id != null) {
      try {
        await _budgetAlertService
            .checkAndNotifyBudgetAlertsForCategory(category.id!);
      } catch (e) {
        print("debug: Error checking budget alerts after categorizing: $e");
      }
    }
  }

  Future<void> clearCategoryForTransaction(Transaction transaction) async {
    // Use copyWith with clearCategoryId flag to explicitly set categoryId to null
    final updated = transaction.copyWith(clearCategoryId: true);
    final previous = _replaceTransactionLocally(updated);
    if (previous != null) {
      _notifyOptimisticChange();
    }

    try {
      await _transactionRepo.saveTransaction(
        updated,
        skipAutoCategorization: true,
      );
    } catch (e) {
      if (previous != null) {
        _replaceTransactionLocally(previous);
        _notifyOptimisticChange();
      }
      rethrow;
    }

    try {
      await _recomputeAfterTransactionMutation();
      await WidgetService.refreshWidget();
    } catch (e) {
      print("debug: Error recomputing state after clearing category: $e");
    }
  }

  Future<void> deleteTransactionsByReferences(
      Iterable<String> references) async {
    await _transactionRepo.deleteTransactionsByReferences(references);
    await loadData();
    await WidgetService.refreshWidget();
  }

  Future<void> createCategory({
    required String name,
    required bool essential,
    bool uncategorized = false,
    String? iconKey,
    String? colorKey,
    String? description,
    String flow = 'expense',
    bool recurring = false,
  }) async {
    await _categoryRepo.createCategory(
      name: name,
      essential: essential,
      uncategorized: uncategorized,
      iconKey: iconKey,
      colorKey: colorKey,
      description: description,
      flow: flow,
      recurring: recurring,
    );
    await loadData();
  }

  Future<void> updateCategory(Category category) async {
    await _categoryRepo.updateCategory(category);
    await loadData();
  }

  Future<void> deleteCategory(Category category) async {
    await _categoryRepo.deleteCategory(category);
    await loadData();
  }

  /// Apply auto-categorization to existing uncategorized transactions
  /// This is called when the feature is enabled
  Future<int> applyAutoCategorizationToExisting() async {
    final isEnabled = await NotificationSettingsService.instance
        .isAutoCategorizeByReceiverEnabled();
    if (!isEnabled) return 0;

    // Get all uncategorized transactions
    final uncategorizedTransactions = _allTransactions
        .where((t) => t.categoryId == null)
        .where((t) =>
            (t.receiver != null && t.receiver!.isNotEmpty) ||
            (t.creditor != null && t.creditor!.isNotEmpty))
        .toList();

    int updatedCount = 0;
    final batch = <Transaction>[];

    for (final transaction in uncategorizedTransactions) {
      final categoryId =
          await ReceiverCategoryService.instance.getCategoryForTransaction(
        receiver: transaction.receiver,
        creditor: transaction.creditor,
      );

      if (categoryId != null) {
        batch.add(transaction.copyWith(categoryId: categoryId));
        updatedCount++;
      }
    }

    // Save all updated transactions
    if (batch.isNotEmpty) {
      for (final transaction in batch) {
        await _transactionRepo.saveTransaction(transaction);
      }
      await loadData();
    }

    return updatedCount;
  }
}
