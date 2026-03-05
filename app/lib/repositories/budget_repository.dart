import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/budget.dart';

class BudgetRepository {
  Future<List<Budget>> getAllBudgets() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }

  Future<List<Budget>> getActiveBudgets() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: 'isActive = ?',
      whereArgs: [1],
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }

  Future<List<Budget>> getBudgetsByType(String type) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: 'type = ? AND isActive = ?',
      whereArgs: [type, 1],
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }

  Future<List<Budget>> getCategoryBudgets() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: 'type = ? AND isActive = ?',
      whereArgs: ['category', 1],
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }

  Future<List<Budget>> getBudgetsByCategory(int categoryId) async {
    final budgets = await getActiveBudgets();
    return budgets.where((b) => b.includesCategory(categoryId)).toList();
  }

  Future<Budget?> getBudgetById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Budget.fromDb(maps.first);
  }

  Future<int> insertBudget(Budget budget) async {
    final db = await DatabaseHelper.instance.database;
    final data = budget.toDb();
    data.remove('id'); // Remove id for insert
    data['updatedAt'] = DateTime.now().toIso8601String();
    return await db.insert('budgets', data);
  }

  Future<int> updateBudget(Budget budget) async {
    final db = await DatabaseHelper.instance.database;
    final data = budget.toDb();
    data['updatedAt'] = DateTime.now().toIso8601String();
    return await db.update(
      'budgets',
      data,
      where: 'id = ?',
      whereArgs: [budget.id],
    );
  }

  /// Applies edits only to the given month while preserving original values
  /// for months after the selected one.
  Future<void> updateBudgetForMonthOnly({
    required Budget originalBudget,
    required Budget editedBudget,
    required DateTime month,
    bool keepFutureSegment = true,
  }) async {
    if (originalBudget.id == null) {
      throw ArgumentError('Original budget must have an id.');
    }

    final db = await DatabaseHelper.instance.database;
    final monthStart = DateTime(month.year, month.month, 1);
    final nextMonthStart = DateTime(month.year, month.month + 1, 1);
    final monthEnd = nextMonthStart.subtract(const Duration(seconds: 1));
    final originalEnd = originalBudget.endDate;
    final hadPastSegment = originalBudget.startDate.isBefore(monthStart);
    final hasFutureSegment =
        keepFutureSegment && (originalEnd == null || originalEnd.isAfter(monthEnd));
    final nowIso = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final editedData = editedBudget
          .copyWith(
            startDate: monthStart,
            endDate: monthEnd,
          )
          .toDb();
      editedData.remove('id');
      editedData['updatedAt'] = nowIso;

      if (hadPastSegment) {
        await txn.update(
          'budgets',
          {
            'endDate': monthStart
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
            'updatedAt': nowIso,
          },
          where: 'id = ?',
          whereArgs: [originalBudget.id],
        );

        await txn.insert('budgets', editedData);
      } else {
        await txn.update(
          'budgets',
          editedData,
          where: 'id = ?',
          whereArgs: [originalBudget.id],
        );
      }

      if (hasFutureSegment) {
        final futureData = originalBudget
            .copyWith(
              id: null,
              startDate: nextMonthStart,
              endDate: originalEnd,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            )
            .toDb();
        futureData.remove('id');
        futureData['updatedAt'] = nowIso;
        await txn.insert('budgets', futureData);
      }
    });
  }

  Future<int> deleteBudget(int id) async {
    final db = await DatabaseHelper.instance.database;
    return await db.delete(
      'budgets',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deactivateBudget(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'budgets',
      {
        'isActive': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> activateBudget(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'budgets',
      {
        'isActive': 1,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAll() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('budgets');
  }

  // Get active budgets for current period
  Future<List<Budget>> getActiveBudgetsForCurrentPeriod(String type) async {
    final now = DateTime.now();
    final db = await DatabaseHelper.instance.database;

    DateTime periodStart;
    DateTime periodEnd;

    switch (type) {
      case 'daily':
        periodStart = DateTime(now.year, now.month, now.day);
        periodEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'monthly':
        periodStart = DateTime(now.year, now.month, 1);
        final nextMonth = DateTime(now.year, now.month + 1, 1);
        periodEnd = nextMonth.subtract(const Duration(seconds: 1));
        break;
      case 'yearly':
        periodStart = DateTime(now.year, 1, 1);
        periodEnd = DateTime(now.year, 12, 31, 23, 59, 59);
        break;
      default:
        periodStart = DateTime(now.year, now.month, 1);
        final nextMonth = DateTime(now.year, now.month + 1, 1);
        periodEnd = nextMonth.subtract(const Duration(seconds: 1));
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: 'type = ? AND isActive = ? AND startDate <= ? AND (endDate IS NULL OR endDate >= ?)',
      whereArgs: [
        type,
        1,
        periodEnd.toIso8601String(),
        periodStart.toIso8601String(),
      ],
      orderBy: 'createdAt DESC',
    );

    return maps.map<Budget>((map) => Budget.fromDb(map)).toList();
  }
}
