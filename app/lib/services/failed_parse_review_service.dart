import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/failed_parse.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/failed_parse_repository.dart';

class FailedParseReviewService {
  FailedParseReviewService._();

  static final FailedParseReviewService instance = FailedParseReviewService._();

  static const String _prefsKey = 'failed_parse_review_candidates_v1';

  Future<String> storeCandidate({
    required Bank bank,
    required String address,
    required String body,
    DateTime? messageDate,
  }) async {
    final timestamp = (messageDate ?? DateTime.now()).toIso8601String();
    final candidate = _PendingFailedParseReview(
      id: _buildId(address, timestamp),
      bankId: bank.id,
      bankName: bank.shortName,
      address: address,
      body: body,
      timestamp: timestamp,
    );

    final candidates = await _readCandidates();
    candidates[candidate.id] = candidate;
    await _writeCandidates(candidates);
    return candidate.id;
  }

  Future<void> confirmCandidate(String id) async {
    final candidates = await _readCandidates();
    final candidate = candidates.remove(id);
    await _writeCandidates(candidates);
    if (candidate == null) return;

    final hasRegisteredAccount = (await AccountRepository().getAccounts())
        .any((account) => account.bank == candidate.bankId);
    if (!hasRegisteredAccount) return;

    final repo = FailedParseRepository();
    final existing = await repo.getAll();
    final alreadyRecorded = existing.any(
      (item) =>
          item.reason == FailedParse.noMatchingPatternReason &&
          item.address == candidate.address &&
          item.body == candidate.body &&
          item.timestamp == candidate.timestamp,
    );
    if (alreadyRecorded) return;

    await repo.add(
      FailedParse(
        address: candidate.address,
        body: candidate.body,
        reason: FailedParse.noMatchingPatternReason,
        timestamp: candidate.timestamp,
      ),
    );
  }

  Future<void> discardCandidate(String id) async {
    final candidates = await _readCandidates();
    if (candidates.remove(id) == null) return;
    await _writeCandidates(candidates);
  }

  Future<Map<String, _PendingFailedParseReview>> _readCandidates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, _PendingFailedParseReview>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <String, _PendingFailedParseReview>{};
      }

      final now = DateTime.now();
      final candidates = <String, _PendingFailedParseReview>{};
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final candidate = _PendingFailedParseReview.fromJson(
          Map<String, dynamic>.from(entry),
        );
        final timestamp = DateTime.tryParse(candidate.timestamp);
        if (timestamp != null && now.difference(timestamp).inDays > 14) {
          continue;
        }
        candidates[candidate.id] = candidate;
      }
      return candidates;
    } catch (_) {
      return <String, _PendingFailedParseReview>{};
    }
  }

  Future<void> _writeCandidates(
    Map<String, _PendingFailedParseReview> candidates,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(candidates.values.map((entry) => entry.toJson()).toList()),
    );
  }

  String _buildId(String address, String timestamp) {
    final timePart = timestamp.hashCode.abs().toRadixString(36);
    final addressPart = address.hashCode.abs().toRadixString(36);
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$timePart$addressPart';
  }
}

class _PendingFailedParseReview {
  final String id;
  final int bankId;
  final String bankName;
  final String address;
  final String body;
  final String timestamp;

  const _PendingFailedParseReview({
    required this.id,
    required this.bankId,
    required this.bankName,
    required this.address,
    required this.body,
    required this.timestamp,
  });

  factory _PendingFailedParseReview.fromJson(Map<String, dynamic> json) {
    return _PendingFailedParseReview(
      id: (json['id'] ?? '').toString(),
      bankId: (json['bankId'] as num?)?.toInt() ?? 0,
      bankName: (json['bankName'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      timestamp: (json['timestamp'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bankId': bankId,
        'bankName': bankName,
        'address': address,
        'body': body,
        'timestamp': timestamp,
      };
}
