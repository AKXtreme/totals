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

  // Summaries
  AllSummary? _summary;
  List<BankSummary> _bankSummaries = [];
  List<AccountSummary> _accountSummaries = [];

  bool _isLoading = false;
  String _searchKey = "";
  DateTime _selectedDate = DateTime.now();

  // Getters
  List<Transaction> _allTransactions = [];

  // Getters
  List<Transaction> get transactions => _transactions;
  List<Transaction> get allTransactions => _allTransactions;
  List<Category> get categories => _categories;
  bool get isLoading => _isLoading;
  AllSummary? get summary => _summary;
  List<BankSummary> get bankSummaries => _bankSummaries;
  List<AccountSummary> get accountSummaries => _accountSummaries;
  DateTime get selectedDate => _selectedDate;

  Category? getCategoryById(int? id) {
    if (id == null) return null;
    return _categoryById[id];
  }

  String? getSelfTransferLabel(Transaction transaction) {
    return _selfTransferLabelByReference[transaction.reference];
  }

  bool isSelfTransfer(Transaction transaction) {
    return _selfTransferLabelByReference.containsKey(transaction.reference);
  }

  bool _isSelfTransfer(Transaction transaction) {
    return _selfTransferLabelByReference.containsKey(transaction.reference);
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
      final labels = _buildSelfTransferLabels(
        _telebirrMatchService.findMatches(_allTransactions, banks),
      );
      labels.addAll(_buildCashTransferLabels(_allTransactions));
      _selfTransferLabelByReference = labels;

      await _calculateSummaries(_allTransactions);
      _filterTransactions(_allTransactions);
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
      int bankId = entry.key;
      List<Account> accounts = entry.value;

      // Filter transactions for this bank (using valid transactions only)
      var bankTransactions =
          validTransactions.where((t) => t.bankId == bankId).toList();

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      double cashBalance = 0.0;

      for (var t in bankTransactions) {
        double amount = t.amount;
        if (t.type == "DEBIT") {
          cashBalance -= amount;
          if (!_isSelfTransfer(t)) {
            totalDebit += amount;
          }
        } else if (t.type == "CREDIT") {
          cashBalance += amount;
          if (!_isSelfTransfer(t)) {
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
          ? cashBalance
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
        if (t.type == "DEBIT") {
          cashBalance -= amount;
          if (!_isSelfTransfer(t)) {
            totalDebit += amount;
          }
        }
        if (t.type == "CREDIT") {
          cashBalance += amount;
          if (!_isSelfTransfer(t)) {
            totalCredit += amount;
          }
        }
      }

      final isCashAccount = account.bank == CashConstants.bankId;
      final accountBalance =
          isCashAccount ? cashBalance : account.balance;

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
      for (final transaction in transactions) transaction.reference: transaction,
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
    await _transactionRepo.saveTransaction(
      transaction.copyWith(categoryId: category.id),
    );

    // Save mapping if auto-categorization is enabled
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

    await loadData();
    await WidgetService.refreshWidget();
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

  Future<void> updateNoteForTransaction(
      Transaction transaction, String? note) async {
    await _transactionRepo.saveTransaction(
      transaction.copyWith(
        note: note?.trim().isEmpty ?? true ? null : note?.trim(),
        clearNote: note == null || note.trim().isEmpty,
      ),
      skipAutoCategorization: true,
    );
    await loadData();
  }

  Future<void> clearCategoryForTransaction(Transaction transaction) async {
    // Use copyWith with clearCategoryId flag to explicitly set categoryId to null
    await _transactionRepo.saveTransaction(
      transaction.copyWith(clearCategoryId: true),
      skipAutoCategorization: true,
    );
    await loadData();
    await WidgetService.refreshWidget();
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
    String? description,
    String flow = 'expense',
    bool recurring = false,
  }) async {
    await _categoryRepo.createCategory(
      name: name,
      essential: essential,
      uncategorized: uncategorized,
      iconKey: iconKey,
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
