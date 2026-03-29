import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:totals/models/category.dart';
import 'package:totals/repositories/category_repository.dart';

/// Handler for category-related API endpoints
class CategoriesHandler {
  final CategoryRepository _categoryRepo = CategoryRepository();

  /// Returns a configured router with all category routes
  Router get router {
    final router = Router();

    // GET /api/categories - List all categories
    router.get('/', _getCategories);

    // GET /api/categories/<id> - Get single category by ID
    router.get('/<id>', _getCategoryById);

    return router;
  }

  /// GET /api/categories
  /// Returns all categories, optionally filtered by flow
  Future<Response> _getCategories(Request request) async {
    try {
      await _categoryRepo.ensureSeeded();

      final flow = request.url.queryParameters['flow']?.trim().toLowerCase();
      if (flow != null &&
          flow.isNotEmpty &&
          flow != 'expense' &&
          flow != 'income') {
        return _errorResponse(
          "Invalid flow. Expected 'expense' or 'income'.",
          400,
        );
      }

      final categories = await _categoryRepo.getCategories();
      final filteredCategories = flow == null || flow.isEmpty
          ? categories
          : categories
              .where((category) => category.flow.toLowerCase() == flow)
              .toList();

      return Response.ok(
        jsonEncode(filteredCategories.map(_serializeCategory).toList()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch categories: $e', 500);
    }
  }

  /// GET /api/categories/:id
  /// Returns a single category by ID
  Future<Response> _getCategoryById(Request request, String id) async {
    try {
      final parsedId = int.tryParse(id);
      if (parsedId == null) {
        return _errorResponse('Invalid category ID', 400);
      }

      await _categoryRepo.ensureSeeded();
      final categories = await _categoryRepo.getCategories();

      Category? category;
      for (final candidate in categories) {
        if (candidate.id == parsedId) {
          category = candidate;
          break;
        }
      }

      if (category == null) {
        return _errorResponse('Category not found', 404);
      }

      return Response.ok(
        jsonEncode(_serializeCategory(category)),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch category: $e', 500);
    }
  }

  Map<String, dynamic> _serializeCategory(Category category) {
    return {
      ...category.toJson(),
      'typeLabel': category.typeLabel(),
    };
  }

  /// Helper to create standardized error responses
  Response _errorResponse(String message, int statusCode) {
    return Response(
      statusCode,
      body: jsonEncode({
        'error': true,
        'message': message,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
