import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart';
import 'package:totals/repositories/budget_repository.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/services/budget_service.dart';

/// Handler for budget-related API endpoints.
class BudgetsHandler {
  final BudgetRepository _budgetRepo = BudgetRepository();
  final BudgetService _budgetService = BudgetService();
  final CategoryRepository _categoryRepo = CategoryRepository();

  Router get router {
    final router = Router();

    router.get('/', _getBudgets);
    router.get('/<id>', _getBudgetById);
    router.post('/', _createBudget);
    router.put('/<id>', _updateBudget);
    router.delete('/<id>', _deleteBudget);

    return router;
  }

  Future<Response> _getBudgets(Request request) async {
    try {
      final query = request.url.queryParameters;
      final active = _parseNullableBool(query['active']);
      final includeStatus =
          _parseNullableBool(query['includeStatus'] ?? query['withStatus']) ??
              false;
      final type = _normalizeBudgetType(query['type'], allowCategory: true);

      final budgets = await _loadBudgets(active: active, type: type);
      final categoriesById = await _loadCategoriesById();
      final payload = await Future.wait(
        budgets.map(
          (budget) => _serializeBudget(
            budget,
            categoriesById: categoriesById,
            includeStatus: includeStatus,
          ),
        ),
      );

      return Response.ok(
        jsonEncode(payload),
        headers: _jsonHeaders,
      );
    } on _RequestValidationException catch (e) {
      return _errorResponse(e.message, 400);
    } catch (e) {
      return _errorResponse('Failed to fetch budgets: $e', 500);
    }
  }

  Future<Response> _getBudgetById(Request request, String id) async {
    try {
      final parsedId = int.tryParse(id);
      if (parsedId == null) {
        return _errorResponse('Invalid budget ID', 400);
      }

      final includeStatus = _parseNullableBool(
            request.url.queryParameters['includeStatus'] ??
                request.url.queryParameters['withStatus'],
          ) ??
          false;

      final budget = await _budgetRepo.getBudgetById(parsedId);
      if (budget == null) {
        return _errorResponse('Budget not found', 404);
      }

      final categoriesById = await _loadCategoriesById();
      return Response.ok(
        jsonEncode(
          await _serializeBudget(
            budget,
            categoriesById: categoriesById,
            includeStatus: includeStatus,
          ),
        ),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return _errorResponse('Failed to fetch budget: $e', 500);
    }
  }

  Future<Response> _createBudget(Request request) async {
    try {
      final body = await _readJsonBody(request);
      final budget = await _budgetFromBody(body);
      final id = await _budgetRepo.insertBudget(budget);
      final savedBudget = budget.copyWith(id: id);
      final categoriesById = await _loadCategoriesById();

      return Response(
        201,
        body: jsonEncode(
          await _serializeBudget(
            savedBudget,
            categoriesById: categoriesById,
            includeStatus: true,
          ),
        ),
        headers: _jsonHeaders,
      );
    } on _RequestValidationException catch (e) {
      return _errorResponse(e.message, 400);
    } on FormatException catch (e) {
      return _errorResponse('Invalid JSON body: ${e.message}', 400);
    } catch (e) {
      return _errorResponse('Failed to create budget: $e', 500);
    }
  }

  Future<Response> _updateBudget(Request request, String id) async {
    try {
      final parsedId = int.tryParse(id);
      if (parsedId == null) {
        return _errorResponse('Invalid budget ID', 400);
      }

      final existingBudget = await _budgetRepo.getBudgetById(parsedId);
      if (existingBudget == null) {
        return _errorResponse('Budget not found', 404);
      }

      final body = await _readJsonBody(request);
      final updatedBudget = await _budgetFromBody(
        body,
        existingBudget: existingBudget,
      );

      await _budgetRepo.updateBudget(updatedBudget.copyWith(id: parsedId));
      final categoriesById = await _loadCategoriesById();

      return Response.ok(
        jsonEncode(
          await _serializeBudget(
            updatedBudget.copyWith(id: parsedId),
            categoriesById: categoriesById,
            includeStatus: true,
          ),
        ),
        headers: _jsonHeaders,
      );
    } on _RequestValidationException catch (e) {
      return _errorResponse(e.message, 400);
    } on FormatException catch (e) {
      return _errorResponse('Invalid JSON body: ${e.message}', 400);
    } catch (e) {
      return _errorResponse('Failed to update budget: $e', 500);
    }
  }

  Future<Response> _deleteBudget(Request request, String id) async {
    try {
      final parsedId = int.tryParse(id);
      if (parsedId == null) {
        return _errorResponse('Invalid budget ID', 400);
      }

      final existingBudget = await _budgetRepo.getBudgetById(parsedId);
      if (existingBudget == null) {
        return _errorResponse('Budget not found', 404);
      }

      await _budgetRepo.deleteBudget(parsedId);

      return Response.ok(
        jsonEncode({
          'deleted': true,
          'id': parsedId,
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return _errorResponse('Failed to delete budget: $e', 500);
    }
  }

  Future<List<Budget>> _loadBudgets({
    bool? active,
    String? type,
  }) async {
    List<Budget> budgets;
    if (active == null) {
      budgets = await _budgetRepo.getAllBudgets();
    } else if (active) {
      budgets = await _budgetRepo.getActiveBudgets();
    } else {
      budgets = await _budgetRepo.getAllBudgets();
      budgets = budgets.where((budget) => !budget.isActive).toList();
    }

    if (type != null && type.isNotEmpty) {
      budgets = budgets.where((budget) => budget.type == type).toList();
    }

    return budgets;
  }

  Future<Map<int, Category>> _loadCategoriesById() async {
    await _categoryRepo.ensureSeeded();
    final categories = await _categoryRepo.getCategories();
    return {
      for (final category in categories)
        if (category.id != null) category.id!: category,
    };
  }

  Future<Map<String, dynamic>> _serializeBudget(
    Budget budget, {
    required Map<int, Category> categoriesById,
    required bool includeStatus,
  }) async {
    final selectedCategoryIds = budget.selectedCategoryIds;
    final categories = selectedCategoryIds
        .map((id) => categoriesById[id])
        .whereType<Category>()
        .map(_serializeCategory)
        .toList();

    final payload = <String, dynamic>{
      ...budget.toJson(),
      'selectedCategoryIds': selectedCategoryIds,
      'appliesToAllExpenses': budget.appliesToAllExpenses,
      'categories': categories,
    };

    if (includeStatus) {
      final status = await _budgetService.getBudgetStatus(budget);
      payload['status'] = {
        'spent': status.spent,
        'remaining': status.remaining,
        'percentageUsed': status.percentageUsed,
        'isExceeded': status.isExceeded,
        'isApproachingLimit': status.isApproachingLimit,
        'periodStart': status.periodStart.toIso8601String(),
        'periodEnd': status.periodEnd.toIso8601String(),
      };
    }

    return payload;
  }

  Map<String, dynamic> _serializeCategory(Category category) {
    return {
      ...category.toJson(),
      'typeLabel': category.typeLabel(),
    };
  }

  Future<Budget> _budgetFromBody(
    Map<String, dynamic> body, {
    Budget? existingBudget,
  }) async {
    final now = DateTime.now();
    final name = _readRequiredName(body, existingBudget);
    final selectedCategoryIds = await _resolveSelectedCategoryIds(
      body,
      existingBudget: existingBudget,
    );
    final hasSelectedCategories = selectedCategoryIds.isNotEmpty;

    final requestedType = body.containsKey('type')
        ? body['type']
        : existingBudget?.type ?? 'monthly';
    final normalizedType =
        _normalizeBudgetType(requestedType, allowCategory: true) ?? 'monthly';

    if (!hasSelectedCategories && normalizedType == 'category') {
      throw const _RequestValidationException(
        'Category budgets require at least one category.',
      );
    }

    final effectiveType = hasSelectedCategories ? 'category' : normalizedType;
    final timeFrame = hasSelectedCategories
        ? (_normalizeTimeFrame(
              body.containsKey('timeFrame')
                  ? body['timeFrame']
                  : existingBudget?.timeFrame,
            ) ??
            'monthly')
        : null;

    final amount = _readPositiveDouble(
      body.containsKey('amount') ? body['amount'] : existingBudget?.amount,
      fieldName: 'amount',
    );
    final alertThreshold = _readDoubleInRange(
      body.containsKey('alertThreshold')
          ? body['alertThreshold']
          : existingBudget?.alertThreshold,
      fieldName: 'alertThreshold',
      min: 0,
      max: 100,
      defaultValue: 80.0,
    );
    final rollover = _parseBool(
          body.containsKey('rollover')
              ? body['rollover']
              : existingBudget?.rollover,
        ) ??
        false;
    final isActive = _parseBool(
          body.containsKey('isActive')
              ? body['isActive']
              : existingBudget?.isActive,
        ) ??
        true;

    final defaultStartDate = _defaultStartDateForBudget(
      effectiveType,
      timeFrame: timeFrame,
      reference: now,
    );
    final startDate = body.containsKey('startDate')
        ? (_parseNullableDate(body['startDate']) ?? defaultStartDate)
        : (existingBudget?.startDate ?? defaultStartDate);

    final endDate = body.containsKey('endDate')
        ? _parseNullableDate(body['endDate'])
        : existingBudget?.endDate;

    if (endDate != null && endDate.isBefore(startDate)) {
      throw const _RequestValidationException(
        'endDate cannot be before startDate.',
      );
    }

    final createdAt = existingBudget?.createdAt ??
        (body.containsKey('createdAt')
            ? (_parseNullableDate(body['createdAt']) ?? now)
            : now);

    final updatedAt = existingBudget != null
        ? now
        : (body.containsKey('updatedAt')
            ? (_parseNullableDate(body['updatedAt']) ?? now)
            : now);

    final normalizedCategoryIds =
        selectedCategoryIds.isEmpty ? null : selectedCategoryIds;
    final primaryCategoryId = normalizedCategoryIds?.first;

    return Budget(
      id: existingBudget?.id,
      name: name,
      type: effectiveType,
      amount: amount,
      categoryId: primaryCategoryId,
      categoryIds: normalizedCategoryIds,
      startDate: startDate,
      endDate: endDate,
      rollover: rollover,
      alertThreshold: alertThreshold,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      timeFrame: timeFrame,
    );
  }

  String _readRequiredName(
    Map<String, dynamic> body,
    Budget? existingBudget,
  ) {
    final rawName =
        body.containsKey('name') ? body['name'] : existingBudget?.name;
    if (rawName is! String || rawName.trim().isEmpty) {
      throw const _RequestValidationException('name is required.');
    }
    return rawName.trim();
  }

  Future<List<int>> _resolveSelectedCategoryIds(
    Map<String, dynamic> body, {
    Budget? existingBudget,
  }) async {
    final hasCategoryIds = body.containsKey('categoryIds') ||
        body.containsKey('selectedCategoryIds');
    final hasCategoryId = body.containsKey('categoryId');

    late final List<int> selectedIds;
    if (!hasCategoryIds && !hasCategoryId) {
      selectedIds = existingBudget?.selectedCategoryIds ?? const <int>[];
    } else {
      final ids = <int>{};
      final rawCategoryIds = body.containsKey('categoryIds')
          ? body['categoryIds']
          : body['selectedCategoryIds'];
      ids.addAll(_parseIntList(rawCategoryIds));

      if (hasCategoryId) {
        final categoryId = _parseInt(body['categoryId']);
        if (categoryId != null && categoryId > 0) {
          ids.add(categoryId);
        }
      }

      selectedIds = ids.toList(growable: false);
    }

    if (selectedIds.isEmpty) {
      return const <int>[];
    }

    final categoriesById = await _loadCategoriesById();
    final missingIds =
        selectedIds.where((id) => !categoriesById.containsKey(id)).toList();
    if (missingIds.isNotEmpty) {
      throw _RequestValidationException(
        'Unknown category IDs: ${missingIds.join(', ')}.',
      );
    }

    return selectedIds;
  }

  List<int> _parseIntList(dynamic value) {
    if (value == null) return const <int>[];

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <int>[];
      try {
        return _parseIntList(jsonDecode(trimmed));
      } catch (_) {
        return trimmed
            .split(',')
            .map((item) => _parseInt(item))
            .whereType<int>()
            .where((item) => item > 0)
            .toSet()
            .toList(growable: false);
      }
    }

    if (value is! List) {
      throw const _RequestValidationException(
        'categoryIds must be an array of integers.',
      );
    }

    return value
        .map(_parseInt)
        .whereType<int>()
        .where((item) => item > 0)
        .toSet()
        .toList(growable: false);
  }

  String? _normalizeBudgetType(
    dynamic value, {
    required bool allowCategory,
  }) {
    if (value == null) return null;
    if (value is! String) {
      throw const _RequestValidationException(
        'type must be a string.',
      );
    }

    final normalized = value.trim().toLowerCase();
    const baseTypes = {'daily', 'monthly', 'yearly'};
    if (baseTypes.contains(normalized)) {
      return normalized;
    }
    if (allowCategory && normalized == 'category') {
      return normalized;
    }

    throw _RequestValidationException(
      allowCategory
          ? "Invalid type. Expected one of: daily, monthly, yearly, category."
          : "Invalid type. Expected one of: daily, monthly, yearly.",
    );
  }

  String? _normalizeTimeFrame(dynamic value) {
    if (value == null) return null;
    if (value is! String) {
      throw const _RequestValidationException(
        'timeFrame must be a string.',
      );
    }

    final normalized = value.trim().toLowerCase();
    const allowed = {'daily', 'monthly', 'yearly', 'never'};
    if (!allowed.contains(normalized)) {
      throw const _RequestValidationException(
        'Invalid timeFrame. Expected one of: daily, monthly, yearly, never.',
      );
    }
    return normalized;
  }

  DateTime _defaultStartDateForBudget(
    String type, {
    required DateTime reference,
    String? timeFrame,
  }) {
    final effectiveType = type == 'category' ? (timeFrame ?? 'monthly') : type;
    switch (effectiveType) {
      case 'daily':
        return DateTime(reference.year, reference.month, reference.day);
      case 'yearly':
        return DateTime(reference.year, 1, 1);
      case 'never':
        return reference;
      case 'monthly':
      default:
        return DateTime(reference.year, reference.month, 1);
    }
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

  double? _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  bool? _parseNullableBool(dynamic value) {
    if (value == null) return null;
    final parsed = _parseBool(value);
    if (parsed == null) {
      throw const _RequestValidationException(
        "Boolean query values must be 'true' or 'false'.",
      );
    }
    return parsed;
  }

  double _readPositiveDouble(
    dynamic value, {
    required String fieldName,
  }) {
    final parsed = _parseDouble(value);
    if (parsed == null || parsed <= 0) {
      throw _RequestValidationException('$fieldName must be greater than 0.');
    }
    return parsed;
  }

  double _readDoubleInRange(
    dynamic value, {
    required String fieldName,
    required double min,
    required double max,
    required double defaultValue,
  }) {
    if (value == null) return defaultValue;
    final parsed = _parseDouble(value);
    if (parsed == null || parsed < min || parsed > max) {
      throw _RequestValidationException(
        '$fieldName must be between ${min.toStringAsFixed(0)} and '
        '${max.toStringAsFixed(0)}.',
      );
    }
    return parsed;
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
