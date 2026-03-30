import 'dart:convert';

import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/models/bank.dart';

final List<Bank> _knownBanks = AllBanksFromAssets.getAllBanks();
final Set<int> _knownBankIds = {
  for (final bank in _knownBanks) bank.id,
};
final Map<String, int> _bankIdLookup = _buildBankIdLookup();

Map<String, int> _buildBankIdLookup() {
  final lookup = <String, int>{};
  for (final bank in _knownBanks) {
    _addBankLookup(lookup, bank.name, bank.id);
    _addBankLookup(lookup, bank.shortName, bank.id);
    for (final code in bank.codes) {
      _addBankLookup(lookup, code, bank.id);
    }
  }
  return lookup;
}

void _addBankLookup(Map<String, int> lookup, String value, int bankId) {
  final normalized = _normalizeBankLookupKey(value);
  if (normalized.isEmpty) return;
  lookup.putIfAbsent(normalized, () => bankId);
}

String _normalizeBankLookupKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String? _asText(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

class AccountShareEntry {
  final int bankId;
  final String accountNumber;
  final String? name;
  final String? bankName;
  final String? bankShortName;

  const AccountShareEntry({
    required this.bankId,
    required this.accountNumber,
    this.name,
    this.bankName,
    this.bankShortName,
  });

  Map<String, dynamic> toJson({String? fallbackName}) {
    final resolvedName = _asText(name) ?? _asText(fallbackName);
    return {
      if (resolvedName != null) 'name': resolvedName,
      'bankId': bankId.toString(),
      'number': accountNumber,
    };
  }

  static AccountShareEntry? tryFromJson(Map<String, dynamic> json) {
    final bankId = _resolveBankId(json);
    final accountNumber = (json['accountNumber'] ??
            json['number'] ??
            json['account'] ??
            json['accountNo'] ??
            json['account_number'])
        ?.toString()
        .trim();
    if (bankId == null || accountNumber == null || accountNumber.isEmpty) {
      return null;
    }
    return AccountShareEntry(
      bankId: bankId,
      accountNumber: accountNumber,
      name: _asText(
        json['name'] ?? json['accountName'] ?? json['label'] ?? json['title'],
      ),
      bankName: _extractBankName(json),
      bankShortName: _extractBankShortName(json),
    );
  }

  static int? _resolveBankId(Map<String, dynamic> json) {
    final explicitBankId = _asInt(json['bankId']) ??
        _asInt(json['bank_id']) ??
        _asInt(json['bankID']);
    if (explicitBankId != null) return explicitBankId;

    final bankValue = json['bank'];
    if (bankValue is int) return bankValue;
    if (bankValue is num) return bankValue.toInt();

    final bankText = _asText(bankValue);
    if (bankText != null) {
      final parsedId = int.tryParse(bankText);
      if (parsedId != null && _knownBankIds.contains(parsedId)) {
        return parsedId;
      }
    }

    final candidates = <String?>[
      bankText,
      _asText(json['bankName']),
      _asText(json['bankShort']),
      _asText(json['bankShortName']),
      _asText(json['shortName']),
    ];

    for (final candidate in candidates) {
      if (candidate == null) continue;
      final resolved = _bankIdLookup[_normalizeBankLookupKey(candidate)];
      if (resolved != null) return resolved;
    }

    return null;
  }

  static String? _extractBankName(Map<String, dynamic> json) {
    final bankValue = json['bank'];
    if (bankValue is String && int.tryParse(bankValue.trim()) == null) {
      return _asText(bankValue);
    }
    return _asText(json['bankName']);
  }

  static String? _extractBankShortName(Map<String, dynamic> json) {
    return _asText(
      json['bankShort'] ?? json['bankShortName'] ?? json['shortName'],
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }
}

class AccountSharePayload {
  static const int currentVersion = 2;
  static const String prefix = 'totals:accounts:';
  static const String _defaultName = 'Imported Account';

  final int version;
  final String name;
  final List<AccountShareEntry> accounts;

  const AccountSharePayload({
    this.version = currentVersion,
    required this.name,
    required this.accounts,
  });

  Map<String, dynamic> toJson() {
    return {
      'profile': name,
      'accounts': accounts.map((entry) => entry.toJson(fallbackName: name)).toList(),
    };
  }

  static String encode(AccountSharePayload payload) {
    return jsonEncode(payload.toJson());
  }

  static AccountSharePayload? decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith(prefix)) {
      final encoded = trimmed.substring(prefix.length);
      if (encoded.isEmpty) return null;
      final parsedFromPrefixedBase64 = _parseEncoded(encoded);
      if (parsedFromPrefixedBase64 != null) return parsedFromPrefixedBase64;

      // Backward-compatibility fallback for legacy prefixed raw JSON.
      final parsedFromPrefixedJson = _parseJsonPayload(encoded);
      if (parsedFromPrefixedJson != null) return parsedFromPrefixedJson;
      return null;
    }

    final parsedRawJson = _parseJsonPayload(trimmed);
    if (parsedRawJson != null) return parsedRawJson;

    final parsedRawBase64 = _parseEncoded(trimmed);
    if (parsedRawBase64 != null) return parsedRawBase64;

    return null;
  }

  static AccountSharePayload? _parseEncoded(String encoded) {
    final normalized = _normalizeBase64(encoded);
    if (normalized == null) return null;
    try {
      final decoded = utf8.decode(base64Url.decode(normalized));
      return _parseJsonPayload(decoded);
    } catch (_) {
      return null;
    }
  }

  static String? _normalizeBase64(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;
    final base64Candidate = cleaned.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = base64Candidate.length % 4;
    final padding = remainder == 0 ? '' : '=' * (4 - remainder);
    return base64Candidate + padding;
  }

  static AccountSharePayload? _parseJsonPayload(String rawJson) {
    final dynamic jsonValue;
    try {
      jsonValue = jsonDecode(rawJson);
    } catch (_) {
      return null;
    }

    if (jsonValue is Map) {
      return tryFromJson(Map<String, dynamic>.from(jsonValue));
    }
    if (jsonValue is List) {
      return tryFromLegacyList(jsonValue);
    }
    return null;
  }

  static AccountSharePayload? tryFromLegacyList(List<dynamic> list) {
    final entries = _parseEntries(list);
    if (entries.isEmpty) return null;
    return AccountSharePayload(
      version: 0,
      name: _defaultName,
      accounts: entries,
    );
  }

  static AccountSharePayload? tryFromJson(Map<String, dynamic> json) {
    final rawAccounts = json['accounts'] ?? json['entries'] ?? json['items'];
    final entries = _parseEntries(rawAccounts);
    if (entries.isEmpty) {
      // Also accept single-account payloads.
      final single = AccountShareEntry.tryFromJson(json);
      if (single != null) {
        entries.add(single);
      }
    }
    if (entries.isEmpty) return null;

    final name = _asText(json['profile']) ??
        _asText(json['name']) ??
        _asText(json['displayName']) ??
        _asText(json['accountHolderName']) ??
        _asText(json['holderName']) ??
        _asText(json['fullName']);
    final resolvedName =
        (name == null || name.isEmpty) ? _resolveNameFromEntries(entries) : name;
    final version = _asInt(json['version']) ??
        _asInt(json['schemaVersion']) ??
        _asInt(json['v']) ??
        currentVersion;

    return AccountSharePayload(
      version: version,
      name: resolvedName ?? _defaultName,
      accounts: entries,
    );
  }

  static List<AccountShareEntry> _parseEntries(dynamic rawAccounts) {
    if (rawAccounts is! List) return const <AccountShareEntry>[];
    final entries = <AccountShareEntry>[];
    for (final entry in rawAccounts) {
      if (entry is Map) {
        final parsed = AccountShareEntry.tryFromJson(
          Map<String, dynamic>.from(entry),
        );
        if (parsed != null) entries.add(parsed);
      }
    }
    return entries;
  }

  static String? _resolveNameFromEntries(List<AccountShareEntry> entries) {
    for (final entry in entries) {
      final resolved = _asText(entry.name);
      if (resolved != null) return resolved;
    }
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }
}
