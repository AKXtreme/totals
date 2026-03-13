import 'package:totals/models/transaction.dart';

bool hasExactAmountAndBalanceDuplicate({
  required int bankId,
  required String type,
  required double amount,
  required String? currentBalance,
  required String? accountNumber,
  required Iterable<Transaction> existingTransactions,
}) {
  final normalizedType = type.trim().toUpperCase();
  final normalizedAccount = _normalizeAccount(accountNumber);
  final normalizedBalance = _parseBalance(currentBalance);
  if (normalizedBalance == null) return false;

  for (final transaction in existingTransactions) {
    if (transaction.bankId != bankId) continue;
    if ((transaction.type ?? '').trim().toUpperCase() != normalizedType) {
      continue;
    }
    if ((transaction.amount - amount).abs() > 0.0001) continue;

    final existingBalance = _parseBalance(transaction.currentBalance);
    if (existingBalance == null ||
        (existingBalance - normalizedBalance).abs() > 0.0001) {
      continue;
    }

    if (normalizedAccount == null) {
      return true;
    }

    if (_normalizeAccount(transaction.accountNumber) == normalizedAccount) {
      return true;
    }
  }

  return false;
}

double? _parseBalance(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.trim().replaceAll(',', '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String? _normalizeAccount(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  return cleaned;
}
