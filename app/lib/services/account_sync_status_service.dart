import 'package:flutter/foundation.dart';

class AccountSyncStatus {
  final String status;
  final double? progress;

  const AccountSyncStatus({
    required this.status,
    this.progress,
  });
}

class AccountSyncStatusService with ChangeNotifier {
  static final AccountSyncStatusService instance = AccountSyncStatusService._();
  AccountSyncStatusService._();

  // Map of accountNumber_bankId -> sync status
  final Map<String, AccountSyncStatus> _syncStatuses = {};

  String? getSyncStatus(String accountNumber, int bankId) {
    final key = '${accountNumber}_$bankId';
    return _syncStatuses[key]?.status;
  }

  double? getSyncProgress(String accountNumber, int bankId) {
    final key = '${accountNumber}_$bankId';
    return _syncStatuses[key]?.progress;
  }

  void setSyncStatus(
    String accountNumber,
    int bankId,
    String status, {
    double? progress,
  }) {
    final key = '${accountNumber}_$bankId';
    _syncStatuses[key] = AccountSyncStatus(
      status: status,
      progress:
          progress == null ? null : progress.clamp(0.0, 1.0).toDouble(),
    );
    notifyListeners();
  }

  void clearSyncStatus(String accountNumber, int bankId) {
    final key = '${accountNumber}_$bankId';
    _syncStatuses.remove(key);
    notifyListeners();
  }

  void clearAll() {
    _syncStatuses.clear();
    notifyListeners();
  }

  /// Checks if any account for the given bank is currently syncing
  bool hasAnyAccountSyncing(int bankId) {
    final bankIdStr = '_$bankId';
    return _syncStatuses.keys.any((key) => key.endsWith(bankIdStr));
  }

  /// Gets the sync status for any account in the given bank
  /// Returns the first sync status found for that bank
  String? getSyncStatusForBank(int bankId) {
    final bankIdStr = '_$bankId';
    for (var entry in _syncStatuses.entries) {
      if (entry.key.endsWith(bankIdStr)) {
        return entry.value.status;
      }
    }
    return null;
  }

  double? getSyncProgressForBank(int bankId) {
    final bankIdStr = '_$bankId';
    for (var entry in _syncStatuses.entries) {
      if (entry.key.endsWith(bankIdStr)) {
        return entry.value.progress;
      }
    }
    return null;
  }
}
