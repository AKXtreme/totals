import 'dart:convert';

class AccountShareEntry {
  final int bankId;
  final String accountNumber;

  const AccountShareEntry({
    required this.bankId,
    required this.accountNumber,
  });

  Map<String, dynamic> toJson() {
    return {
      'bankId': bankId,
      'accountNumber': accountNumber,
    };
  }

  static AccountShareEntry? tryFromJson(Map<String, dynamic> json) {
    final bankId = _asInt(json['bankId']) ??
        _asInt(json['bank']) ??
        _asInt(json['bank_id']) ??
        _asInt(json['bankID']);
    final accountNumber = (json['accountNumber'] ??
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
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class AccountSharePayload {
  static const int currentVersion = 1;
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
      'version': version,
      'name': name,
      'accounts': accounts.map((entry) => entry.toJson()).toList(),
    };
  }

  static String encode(AccountSharePayload payload) {
    final jsonString = jsonEncode(payload.toJson());
    final encoded = base64UrlEncode(utf8.encode(jsonString));
    return '$prefix$encoded';
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

    if (jsonValue is Map<String, dynamic>) {
      return tryFromJson(jsonValue);
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

    final name = (json['name'] ??
            json['displayName'] ??
            json['accountHolderName'] ??
            json['holderName'] ??
            json['fullName'])
        ?.toString()
        .trim();
    final resolvedName = (name == null || name.isEmpty) ? _defaultName : name;
    final version = _asInt(json['version']) ??
        _asInt(json['schemaVersion']) ??
        _asInt(json['v']) ??
        currentVersion;

    return AccountSharePayload(
      version: version,
      name: resolvedName,
      accounts: entries,
    );
  }

  static List<AccountShareEntry> _parseEntries(dynamic rawAccounts) {
    if (rawAccounts is! List) return const <AccountShareEntry>[];
    final entries = <AccountShareEntry>[];
    for (final entry in rawAccounts) {
      if (entry is Map<String, dynamic>) {
        final parsed = AccountShareEntry.tryFromJson(entry);
        if (parsed != null) entries.add(parsed);
      }
    }
    return entries;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
