import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/user_account.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/services/bank_config_service.dart';

/// Handler for quick-access/shared account API endpoints.
class SharedAccountsHandler {
  final UserAccountRepository _userAccountRepo = UserAccountRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank>? _cachedBanks;

  Router get router {
    final router = Router();

    router.get('/', _getSharedAccounts);
    router.get('/<bankId>/<accountNumber>', _getSharedAccountByBankAndNumber);
    router.post('/', _createSharedAccount);
    router.delete('/<bankId>/<accountNumber>', _deleteSharedAccount);

    return router;
  }

  Future<Response> _getSharedAccounts(Request request) async {
    try {
      final accounts = await _userAccountRepo.getUserAccounts();
      final enrichedAccounts = await Future.wait(
        accounts.map(_serializeSharedAccount),
      );

      return Response.ok(
        jsonEncode(enrichedAccounts),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return _errorResponse('Failed to fetch shared accounts: $e', 500);
    }
  }

  Future<Response> _getSharedAccountByBankAndNumber(
    Request request,
    String bankId,
    String accountNumber,
  ) async {
    try {
      final parsedBankId = int.tryParse(bankId);
      if (parsedBankId == null) {
        return _errorResponse('Invalid bank ID', 400);
      }

      final accounts = await _userAccountRepo.getUserAccounts();
      UserAccount? account;
      for (final candidate in accounts) {
        if (candidate.bankId == parsedBankId &&
            candidate.accountNumber == accountNumber) {
          account = candidate;
          break;
        }
      }

      if (account == null) {
        return _errorResponse('Shared account not found', 404);
      }

      return Response.ok(
        jsonEncode(await _serializeSharedAccount(account)),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return _errorResponse('Failed to fetch shared account: $e', 500);
    }
  }

  Future<Response> _createSharedAccount(Request request) async {
    try {
      final body = await _readJsonBody(request);
      final accountNumber = (body['accountNumber'] as String?)?.trim() ?? '';
      final accountHolderName =
          (body['accountHolderName'] as String?)?.trim() ?? '';
      final parsedBankId = _parseInt(body['bankId'] ?? body['bank']);

      if (accountNumber.isEmpty) {
        throw const _RequestValidationException(
          'accountNumber is required.',
        );
      }
      if (accountHolderName.isEmpty) {
        throw const _RequestValidationException(
          'accountHolderName is required.',
        );
      }
      if (parsedBankId == null || parsedBankId <= 0) {
        throw const _RequestValidationException('bankId is required.');
      }

      final bank = await _getBankById(parsedBankId);
      if (bank == null) {
        throw _RequestValidationException(
          'Unknown bankId: $parsedBankId.',
        );
      }

      final alreadyExists = await _userAccountRepo.userAccountExists(
        accountNumber,
        parsedBankId,
      );
      if (alreadyExists) {
        return _errorResponse(
          'Shared account already exists.',
          409,
        );
      }

      final createdAt = body.containsKey('createdAt')
          ? (_parseNullableDate(body['createdAt']) ?? DateTime.now())
          : DateTime.now();
      final account = UserAccount(
        accountNumber: accountNumber,
        bankId: parsedBankId,
        accountHolderName: accountHolderName,
        createdAt: createdAt.toIso8601String(),
      );

      final id = await _userAccountRepo.saveUserAccount(account);
      final savedAccount = UserAccount(
        id: id,
        accountNumber: account.accountNumber,
        bankId: account.bankId,
        accountHolderName: account.accountHolderName,
        createdAt: account.createdAt,
      );

      return Response(
        201,
        body: jsonEncode(await _serializeSharedAccount(savedAccount)),
        headers: _jsonHeaders,
      );
    } on _RequestValidationException catch (e) {
      return _errorResponse(e.message, 400);
    } on FormatException catch (e) {
      return _errorResponse('Invalid JSON body: ${e.message}', 400);
    } catch (e) {
      return _errorResponse('Failed to create shared account: $e', 500);
    }
  }

  Future<Response> _deleteSharedAccount(
    Request request,
    String bankId,
    String accountNumber,
  ) async {
    try {
      final parsedBankId = int.tryParse(bankId);
      if (parsedBankId == null) {
        return _errorResponse('Invalid bank ID', 400);
      }

      final exists = await _userAccountRepo.userAccountExists(
        accountNumber,
        parsedBankId,
      );
      if (!exists) {
        return _errorResponse('Shared account not found', 404);
      }

      await _userAccountRepo.deleteUserAccountByNumberAndBank(
        accountNumber,
        parsedBankId,
      );

      return Response.ok(
        jsonEncode({
          'deleted': true,
          'bankId': parsedBankId,
          'accountNumber': accountNumber,
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return _errorResponse('Failed to delete shared account: $e', 500);
    }
  }

  Future<Map<String, dynamic>> _serializeSharedAccount(
    UserAccount account,
  ) async {
    final bank = await _getBankById(account.bankId);

    return {
      'id': account.id,
      'accountNumber': account.accountNumber,
      'bankId': account.bankId,
      'bankName': bank?.name ?? 'Unknown Bank',
      'bankShortName': bank?.shortName ?? 'N/A',
      'bankImage': bank?.image ?? '',
      'accountHolderName': account.accountHolderName,
      'createdAt': account.createdAt,
    };
  }

  Future<Map<String, dynamic>> _readJsonBody(Request request) async {
    final rawBody = await request.readAsString();
    if (rawBody.trim().isEmpty) {
      throw const _RequestValidationException('Request body is required.');
    }

    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) {
      throw const _RequestValidationException(
        'Request body must be a JSON object.',
      );
    }

    return decoded;
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is String && value.trim().isEmpty) return null;
    final parsed = _parseDate(value);
    if (parsed == null) {
      throw const _RequestValidationException(
        'Invalid date value. Use ISO 8601 format.',
      );
    }
    return parsed;
  }

  Future<Bank?> _getBankById(int bankId) async {
    if (bankId == CashConstants.bankId) {
      return Bank(
        id: CashConstants.bankId,
        name: CashConstants.bankName,
        shortName: CashConstants.bankShortName,
        codes: const [],
        image: CashConstants.bankImage,
        colors: CashConstants.bankColors,
      );
    }

    try {
      _cachedBanks ??= await _bankConfigService.getBanks();
      return _cachedBanks!.firstWhere((bank) => bank.id == bankId);
    } catch (_) {
      return null;
    }
  }

  Response _errorResponse(String message, int statusCode) {
    return Response(
      statusCode,
      body: jsonEncode({
        'error': true,
        'message': message,
      }),
      headers: _jsonHeaders,
    );
  }

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };
}

class _RequestValidationException implements Exception {
  final String message;

  const _RequestValidationException(this.message);

  @override
  String toString() => message;
}
