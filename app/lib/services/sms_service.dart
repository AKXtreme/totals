import 'dart:ui';

import 'package:another_telephony/telephony.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/pattern_parser.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/failed_parse.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/budget_alert_service.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/utils/transaction_duplicate_detector.dart';

enum ParseStatus {
  success,
  noBank,
  noPattern,
  duplicate,
}

class ParseResult {
  final ParseStatus status;
  final Transaction? transaction;
  final String? reason;

  const ParseResult({
    required this.status,
    this.transaction,
    this.reason,
  });

  bool get isResolved => status == ParseStatus.success;
}

class TodaySmsSyncResult {
  final int processed;
  final int added;
  final int duplicates;
  final int noPattern;
  final int skipped;
  final int errors;
  final bool permissionDenied;

  const TodaySmsSyncResult({
    this.processed = 0,
    this.added = 0,
    this.duplicates = 0,
    this.noPattern = 0,
    this.skipped = 0,
    this.errors = 0,
    this.permissionDenied = false,
  });

  bool get hasBankMessages => processed > 0;
}

// Top-level function for background execution
@pragma('vm:entry-point')
onBackgroundMessage(SmsMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    print("debug: BG: Handler started.");

    final String? address = message.address;
    print("debug: BG: Address: '$address'");

    final String? body = message.body;
    if (body == null) {
      print("debug: BG: Body is null. Exiting.");
      return;
    }

    print("debug: BG: Checking if relevant...");
    if (await SmsService.isRelevantMessage(address)) {
      print("debug: BG: Message IS relevant. Processing...");
      final receivedAt = message.date == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(message.date!);
      await SmsService.processMessage(body, address!,
          notifyUser: true,
          messageDate: receivedAt);
      print("debug: BG: Processing finished.");
    } else {
      print("debug: BG: Message NOT relevant.");
    }
  } catch (e, stack) {
    print("debug: BG: CRITICAL ERROR: $e");
    print(stack);
  }
}

class SmsService {
  final Telephony _telephony = Telephony.instance;
  static final BankConfigService _bankConfigService = BankConfigService();
  static List<Bank>? _cachedBanks;
  static const String _atmCashCutoffPrefPrefix =
      'atm_cash_transfer_cutoff_iso_profile_';
  static const int _dashenBankId = 4;

  // Callback for foreground-only UI updates.
  ValueChanged<Transaction>? onTransactionSaved;

  void _registerIncomingSmsListener() {
    _telephony.listenIncomingSms(
      onNewMessage: _handleForegroundMessage,
      onBackgroundMessage: onBackgroundMessage,
    );
  }

  Future<void> init() async {
    final bool? result = await _telephony.requestSmsPermissions;
    if (result != null && result) {
      _registerIncomingSmsListener();
    } else {
      print("debug: SMS Permission denied");
    }
  }

  void _handleForegroundMessage(SmsMessage message) async {
    print("debug: Foreground message from ${message.address}: ${message.body}");
    if (message.body == null) return;

    try {
      if (await SmsService.isRelevantMessage(message.address)) {
        final receivedAt = message.date == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(message.date!);
        final tx = await SmsService.processMessage(
            message.body!, message.address!,
            notifyUser: true,
            messageDate: receivedAt);
        if (tx != null && onTransactionSaved != null) {
          onTransactionSaved!(tx);
        }
      }
    } catch (e) {
      print("debug: Error processing foreground message: $e");
    }
  }

  Future<TodaySmsSyncResult> syncTodayBankSms() async {
    final bool? permissionGranted = await _telephony.requestSmsPermissions;
    if (permissionGranted != true) {
      return const TodaySmsSyncResult(permissionDenied: true);
    }

    _registerIncomingSmsListener();
    await _getAtmCashTransferCutoff();

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final filter = SmsFilter.where(SmsColumn.DATE)
        .greaterThanOrEqualTo(startOfDay.millisecondsSinceEpoch.toString())
        .and(SmsColumn.DATE)
        .lessThan(endOfDay.millisecondsSinceEpoch.toString());

    final messages = await _telephony.getInboxSms(
      filter: filter,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    int processed = 0;
    int added = 0;
    int duplicates = 0;
    int noPattern = 0;
    int skipped = 0;
    int errors = 0;

    for (final message in messages) {
      final body = message.body;
      final address = message.address;
      if (body == null || address == null) {
        skipped++;
        continue;
      }

      final bank = await getRelevantBank(address);
      if (bank == null) {
        skipped++;
        continue;
      }

      processed++;
      final messageDate = message.date != null
          ? DateTime.fromMillisecondsSinceEpoch(message.date!)
          : null;

      try {
        final result = await _processMessageInternal(
          body,
          address,
          messageDate: messageDate,
          notifyUser: false,
          recordFailure: false,
        );
        switch (result.status) {
          case ParseStatus.success:
            added++;
            break;
          case ParseStatus.duplicate:
            duplicates++;
            break;
          case ParseStatus.noPattern:
            noPattern++;
            break;
          case ParseStatus.noBank:
            skipped++;
            break;
        }
      } catch (e) {
        errors++;
        print("debug: Error processing SMS: $e");
      }
    }

    return TodaySmsSyncResult(
      processed: processed,
      added: added,
      duplicates: duplicates,
      noPattern: noPattern,
      skipped: skipped,
      errors: errors,
    );
  }

  /// Checks if the message address matches any of our known bank codes.
  static Future<bool> isRelevantMessage(String? address) async {
    if (address == null) return false;
    final bank = await getRelevantBank(address);
    return bank != null;
  }

  static String _normalizeSenderToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static bool _addressMatchesCode(String normalizedAddress, String code) {
    final normalizedCode = _normalizeSenderToken(code);
    if (normalizedCode.isEmpty) return false;
    return normalizedAddress.contains(normalizedCode);
  }

  /// Identifies the bank associated with the sender address.
  static Future<Bank?> getRelevantBank(String? address) async {
    if (address == null) return null;

    // Fetch banks from database (with static caching)
    if (_cachedBanks == null) {
      _cachedBanks = await _bankConfigService.getBanks();
    }

    final normalizedAddress = _normalizeSenderToken(address);
    if (normalizedAddress.isEmpty) return null;

    for (var bank in _cachedBanks!) {
      for (var code in bank.codes) {
        if (_addressMatchesCode(normalizedAddress, code)) {
          return bank;
        }
      }
    }
    return null;
  }

  static double sanitizeAmount(String? raw) {
    if (raw == null) return 0.0;

    String cleaned = raw.trim();

    // Remove all characters except digits and decimal points
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9.]'), '');

    // If multiple dots exist, keep only the first valid decimal
    int firstDot = cleaned.indexOf('.');
    if (firstDot != -1) {
      // Remove all dots after the first one
      cleaned = cleaned.substring(0, firstDot + 1) +
          cleaned.substring(firstDot + 1).replaceAll('.', '');
    }

    // If the string ends with a dot, add a zero → "12." → "12.0"
    if (cleaned.endsWith('.')) {
      cleaned = cleaned + '0';
    }

    // If empty after cleaning, return 0
    if (cleaned.isEmpty) return 0.0;

    // Safe parse
    return double.tryParse(cleaned) ?? 0.0;
  }

  static Bank? _bankById(List<Bank> banks, int bankId) {
    for (final bank in banks) {
      if (bank.id == bankId) return bank;
    }
    return null;
  }

  static Account? _accountForBank(List<Account> accounts, int bankId) {
    for (final account in accounts) {
      if (account.bank == bankId) return account;
    }
    return null;
  }

  static Account? _maskedAccountMatch(
    List<Account> accounts, {
    required int bankId,
    required String extractedAccount,
    required int? maskPattern,
  }) {
    final trimmedAccount = extractedAccount.trim();
    if (trimmedAccount.isEmpty) return null;

    final suffix = maskPattern != null &&
            maskPattern > 0 &&
            trimmedAccount.length > maskPattern
        ? trimmedAccount.substring(trimmedAccount.length - maskPattern)
        : trimmedAccount;

    for (final account in accounts) {
      if (account.bank != bankId) continue;
      if (account.accountNumber.endsWith(suffix)) return account;
    }
    return null;
  }

  static Future<void> _saveUpdatedAccountBalance(
    AccountRepository accRepo,
    Account account,
    double newBalance,
  ) async {
    final updated = Account(
      accountNumber: account.accountNumber,
      bank: account.bank,
      balance: newBalance,
      accountHolderName: account.accountHolderName,
      settledBalance: account.settledBalance,
      pendingCredit: account.pendingCredit,
      profileId: account.profileId,
    );
    await accRepo.saveAccount(updated);
    print("debug: Account balance updated for ${account.accountHolderName}");
  }

  static bool _isAtmWithdrawal(
    Map<String, dynamic> details,
    String messageBody,
  ) {
    final type = (details['type'] ?? '').toString().toUpperCase();
    if (type != 'DEBIT') return false;

    final description =
        (details['patternDescription'] as String?)?.toLowerCase();
    if (description != null && description.contains('atm')) {
      return true;
    }

    final normalizedBody = messageBody.toLowerCase();
    return normalizedBody.contains('atm') &&
        normalizedBody.contains('withdraw');
  }

  static Future<void> _ensureCashAccount() async {
    final accountRepo = AccountRepository();
    final accounts = await accountRepo.getAccounts();
    final hasCash = accounts.any((a) => a.bank == CashConstants.bankId);
    if (hasCash) return;

    final cashAccount = Account(
      accountNumber: CashConstants.defaultAccountNumber,
      bank: CashConstants.bankId,
      balance: 0.0,
      accountHolderName: CashConstants.defaultAccountHolderName,
    );
    await accountRepo.saveAccount(cashAccount);
  }

  static Future<void> _createCashTransactionForAtmWithdrawal(
    Transaction withdrawal,
    List<Transaction> existingTransactions,
  ) async {
    final bankId = withdrawal.bankId;
    if (bankId == null || bankId == CashConstants.bankId) return;

    if (await _isWithdrawalBeforeCashCutoff(withdrawal)) {
      print(
          "debug: Skipping historical ATM cash transfer for ${withdrawal.reference}");
      return;
    }

    final cashReference = CashConstants.buildAtmReference(withdrawal.reference);
    if (existingTransactions.any((t) => t.reference == cashReference)) {
      return;
    }

    await _ensureCashAccount();
    final currentCashBalance =
        await _currentCashWalletBalance(existingTransactions);

    final cashTransaction = Transaction(
      amount: withdrawal.amount,
      reference: cashReference,
      creditor: 'ATM withdrawal',
      time: withdrawal.time ?? DateTime.now().toIso8601String(),
      bankId: CashConstants.bankId,
      type: 'CREDIT',
      currentBalance: (currentCashBalance + withdrawal.amount).toStringAsFixed(2),
      transactionLink: withdrawal.reference,
      accountNumber: CashConstants.defaultAccountNumber,
    );

    await TransactionRepository().saveTransaction(cashTransaction);
  }

  static Future<double> _currentCashWalletBalance(
    List<Transaction> existingTransactions,
  ) async {
    final accountRepo = AccountRepository();
    final accounts = await accountRepo.getAccounts();
    final accountBase = accounts
        .where((a) => a.bank == CashConstants.bankId)
        .fold<double>(0.0, (sum, account) => sum + account.balance);

    final txDelta = existingTransactions
        .where((t) => t.bankId == CashConstants.bankId)
        .fold<double>(0.0, (sum, transaction) {
      if (transaction.type == 'DEBIT') return sum - transaction.amount;
      if (transaction.type == 'CREDIT') return sum + transaction.amount;
      return sum;
    });

    return accountBase + txDelta;
  }

  static Future<bool> _isWithdrawalBeforeCashCutoff(Transaction withdrawal) async {
    final withdrawalTime = DateTime.tryParse(withdrawal.time ?? '');
    if (withdrawalTime == null) return false;
    final cutoff = await _getAtmCashTransferCutoff();
    return withdrawalTime.isBefore(cutoff);
  }

  static Future<DateTime> _getAtmCashTransferCutoff() async {
    final profileRepo = ProfileRepository();
    final activeProfileId = await profileRepo.getActiveProfileId();
    final key = activeProfileId != null
        ? '$_atmCashCutoffPrefPrefix$activeProfileId'
        : '${_atmCashCutoffPrefPrefix}default';

    final prefs = await SharedPreferences.getInstance();
    final existingIso = prefs.getString(key);
    if (existingIso != null) {
      final parsed = DateTime.tryParse(existingIso);
      if (parsed != null) return parsed;
    }

    final cutoff = (await profileRepo.getActiveProfile())?.createdAt ??
        (await profileRepo.getDefaultProfile())?.createdAt ??
        DateTime.now();

    await prefs.setString(key, cutoff.toIso8601String());
    await _cleanupHistoricalAtmCashTransactions(cutoff);
    return cutoff;
  }

  static Future<void> _cleanupHistoricalAtmCashTransactions(
      DateTime cutoff) async {
    final txRepo = TransactionRepository();
    final transactions = await txRepo.getTransactions();
    final staleReferences = transactions
        .where((transaction) {
          if (transaction.bankId != CashConstants.bankId) return false;
          if (!transaction.reference
              .startsWith(CashConstants.atmReferencePrefix)) {
            return false;
          }
          final txTime = DateTime.tryParse(transaction.time ?? '');
          if (txTime == null) return false;
          return txTime.isBefore(cutoff);
        })
        .map((transaction) => transaction.reference)
        .toList(growable: false);

    if (staleReferences.isEmpty) return;

    await txRepo.deleteTransactionsByReferences(staleReferences);
    print(
        "debug: Removed ${staleReferences.length} historical ATM cash transfer(s) before cutoff");
  }

  static bool _isDashenExpenseDuplicate(
    Map<String, dynamic> details,
    List<Transaction> existingTransactions,
  ) {
    final bankId = details['bankId'];
    final type = (details['type'] ?? '').toString().toUpperCase();
    final amount = details['amount'];
    if (bankId != _dashenBankId || type != 'DEBIT' || amount is! num) {
      return false;
    }

    return hasExactAmountAndBalanceDuplicate(
      bankId: bankId,
      type: type,
      amount: amount.toDouble(),
      currentBalance: details['currentBalance']?.toString(),
      accountNumber: details['accountNumber']?.toString(),
      existingTransactions: existingTransactions,
    );
  }

  // Static processing logic so it can be used by background handler too.
  static Future<Transaction?> processMessage(
    String messageBody,
    String senderAddress, {
    DateTime? messageDate,
    bool notifyUser = false,
  }) async {
    final result = await _processMessageInternal(
      messageBody,
      senderAddress,
      messageDate: messageDate,
      notifyUser: notifyUser,
      recordFailure: true,
    );
    return result.transaction;
  }

  static Future<ParseResult> retryFailedParse(
    String messageBody,
    String senderAddress, {
    DateTime? messageDate,
  }) async {
    return _processMessageInternal(
      messageBody,
      senderAddress,
      messageDate: messageDate,
      notifyUser: false,
      recordFailure: false,
    );
  }

  static Future<ParseResult> _processMessageInternal(
    String messageBody,
    String senderAddress, {
    DateTime? messageDate,
    bool notifyUser = false,
    bool recordFailure = true,
  }) async {
    print("debug: Processing message: $messageBody");

    Bank? bank = await getRelevantBank(senderAddress);
    if (bank == null) {
      print(
          "dubg: No bank found for address $senderAddress - skipping processing.");
      return const ParseResult(
        status: ParseStatus.noBank,
        reason: "No matching bank",
      );
    }

    // 1. Load Patterns
    final SmsConfigService configService = SmsConfigService();
    final patterns = await configService.getPatterns();
    final relevantPatterns =
        patterns.where((p) => p.bankId == bank.id).toList();
    // 2. Parse
    configService.debugSms(messageBody);
    var details = await PatternParser.extractTransactionDetails(
        configService.cleanSmsText(messageBody),
        senderAddress,
        messageDate,
        relevantPatterns);

    if (details == null) {
      print("debug: No matching pattern found for message from $senderAddress");
      if (recordFailure) {
        await FailedParseRepository().add(FailedParse(
            address: senderAddress,
            body: messageBody,
            reason: "No matching pattern",
            timestamp: DateTime.now().toIso8601String()));
      }
      return const ParseResult(
        status: ParseStatus.noPattern,
        reason: "No matching pattern",
      );
    }

    print("debug: Extracted details: $details");

    // Use message date if provided, otherwise use extracted time or current time
    if (messageDate != null && details['time'] == null) {
      details['time'] = messageDate.toIso8601String();
    } else if (messageDate != null && details['time'] != null) {
      // If pattern extracted a time but we have message date, prefer message date for historical accuracy
      details['time'] = messageDate.toIso8601String();
    }

    // 3. Check duplicate transaction
    TransactionRepository txRepo = TransactionRepository();
    List<Transaction> existingTx = await txRepo.getTransactions();

    String? newRef = details['reference'];
    if (newRef != null && existingTx.any((t) => t.reference == newRef)) {
      print("debug: Duplicate transaction skipped");
      if (_isAtmWithdrawal(details, messageBody)) {
        try {
          final existing = existingTx
              .firstWhere((transaction) => transaction.reference == newRef);
          await _createCashTransactionForAtmWithdrawal(existing, existingTx);
        } catch (e) {
          print("debug: Error reconciling cash transfer: $e");
        }
      }
      if (recordFailure) {
        await FailedParseRepository().add(FailedParse(
            address: senderAddress,
            body: messageBody,
            reason: "Duplicate transaction $newRef",
            timestamp: DateTime.now().toIso8601String()));
      }
      return ParseResult(
        status: ParseStatus.duplicate,
        reason: "Duplicate transaction $newRef",
      );
    }

    if (_isDashenExpenseDuplicate(details, existingTx)) {
      print("debug: Duplicate Dashen debit skipped by amount and balance");
      if (recordFailure) {
        await FailedParseRepository().add(FailedParse(
            address: senderAddress,
            body: messageBody,
            reason: "Duplicate Dashen debit by amount and balance",
            timestamp: DateTime.now().toIso8601String()));
      }
      return const ParseResult(
        status: ParseStatus.duplicate,
        reason: "Duplicate Dashen debit by amount and balance",
      );
    }

    // 4. Update Account Balance
    // We need to match the Bank ID from the pattern, not just assume 1 (CBE)
    int bankId = details['bankId'] ?? bank.id;
    final banks = await _bankConfigService.getBanks();
    final currentBank = _bankById(banks, bankId);
    if (currentBank == null) {
      print("debug: No bank config found for bank $bankId");
    } else if (currentBank.uniformMasking == false) {
      AccountRepository accRepo = AccountRepository();
      List<Account> accounts = await accRepo.getAccounts();
      final account = _accountForBank(accounts, bankId);
      if (account == null) {
        print("debug: No matching account found for bank $bankId");
      } else {
        final newBalance = details['currentBalance'] != null
            ? sanitizeAmount(details['currentBalance'])
            : account.balance;
        await _saveUpdatedAccountBalance(accRepo, account, newBalance);
      }
    } else if (details['accountNumber'] != null) {
      AccountRepository accRepo = AccountRepository();
      List<Account> accounts = await accRepo.getAccounts();

      final extractedAccount = details['accountNumber'].toString();
      final account = currentBank.uniformMasking == true
          ? _maskedAccountMatch(
              accounts,
              bankId: bankId,
              extractedAccount: extractedAccount,
              maskPattern: currentBank.maskPattern,
            )
          : null;

      if (account != null) {
        final newBalance = details['currentBalance'] != null
            ? sanitizeAmount(details['currentBalance'])
            : account.balance;
        await _saveUpdatedAccountBalance(accRepo, account, newBalance);
      } else {
        print(
            "No matching account found for bank $bankId and account $extractedAccount");
      }
    }

    // 5. Save Transaction
    // Need to ensure details has all fields or handle parsing
    // Transaction.fromJson expects Strings mostly?
    Transaction newTx = Transaction.fromJson(details);
    await txRepo.saveTransaction(newTx);

    print("debug: New transaction saved: ${newTx.reference}");

    if (_isAtmWithdrawal(details, messageBody)) {
      try {
        await _createCashTransactionForAtmWithdrawal(newTx, existingTx);
      } catch (e) {
        print("debug: Error creating cash transfer: $e");
      }
    }

    if (notifyUser) {
      await NotificationService.instance.showTransactionNotification(
        transaction: newTx,
        bankId: bankId,
      );
    }

    if (newTx.type == 'DEBIT') {
      try {
        await BudgetAlertService().checkAndNotifyBudgetAlerts();
      } catch (e) {
        print("debug: Error checking budget alerts after SMS transaction: $e");
      }
    }

    try {
      await WidgetService.refreshWidget();
    } catch (e) {
      print("debug: Error refreshing widget after SMS transaction: $e");
    }

    return ParseResult(
      status: ParseStatus.success,
      transaction: newTx,
    );
  }
}
