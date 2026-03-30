import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/auto_categorization.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/receiver_category_service.dart';

class AutoCategorizationService {
  AutoCategorizationService._();

  static final AutoCategorizationService instance =
      AutoCategorizationService._();

  Future<bool> isEnabled() {
    return NotificationSettingsService.instance.isAutoCategorizationEnabled();
  }

  String normalizeCounterparty(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String normalizeFlow(String? flow) {
    return (flow ?? '').trim().toLowerCase() == 'income' ? 'income' : 'expense';
  }

  String flowForTransactionType(String? type) {
    return (type ?? '').trim().toUpperCase() == 'CREDIT' ? 'income' : 'expense';
  }

  String? resolvePrimaryCounterparty({
    required String? type,
    String? receiver,
    String? creditor,
  }) {
    String? normalizeDisplay(String? value) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      return trimmed.replaceAll(RegExp(r'\s+'), ' ');
    }

    final normalizedReceiver = normalizeDisplay(receiver);
    final normalizedCreditor = normalizeDisplay(creditor);
    final isCredit = (type ?? '').trim().toUpperCase() == 'CREDIT';
    if (isCredit) {
      return normalizedCreditor ?? normalizedReceiver;
    }
    return normalizedReceiver ?? normalizedCreditor;
  }

  Future<List<AutoCategorizationRule>> getRules({String? flow}) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedFlow = flow == null ? null : normalizeFlow(flow);
    final rows = await db.query(
      'auto_category_rules',
      where: normalizedFlow == null ? null : 'flow = ?',
      whereArgs: normalizedFlow == null ? null : [normalizedFlow],
      orderBy: 'counterparty COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(AutoCategorizationRule.fromDb).toList(growable: false);
  }

  Future<AutoCategorizationRule?> getRuleForCounterparty(
    String counterparty,
    String flow,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'auto_category_rules',
      where: 'normalizedCounterparty = ? AND flow = ?',
      whereArgs: [
        normalizeCounterparty(counterparty),
        normalizeFlow(flow),
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AutoCategorizationRule.fromDb(rows.first);
  }

  Future<void> upsertRule({
    required String counterparty,
    required String flow,
    required int categoryId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedCounterparty = normalizeCounterparty(counterparty);
    final displayCounterparty = counterparty.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    final normalizedFlow = normalizeFlow(flow);
    await db.insert(
      'auto_category_rules',
      {
        'counterparty': displayCounterparty,
        'normalizedCounterparty': normalizedCounterparty,
        'flow': normalizedFlow,
        'categoryId': categoryId,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteRule(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'auto_category_rules',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> dismissPrompt({
    required String counterparty,
    required String flow,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedCounterparty = normalizeCounterparty(counterparty);
    final displayCounterparty = counterparty.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    await db.insert(
      'auto_category_prompt_dismissals',
      {
        'counterparty': displayCounterparty,
        'normalizedCounterparty': normalizedCounterparty,
        'flow': normalizeFlow(flow),
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isPromptDismissed({
    required String counterparty,
    required String flow,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'auto_category_prompt_dismissals',
      columns: ['id'],
      where: 'normalizedCounterparty = ? AND flow = ?',
      whereArgs: [
        normalizeCounterparty(counterparty),
        normalizeFlow(flow),
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<AutoCategoryPromptDismissal>> getDismissals(
      {String? flow}) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedFlow = flow == null ? null : normalizeFlow(flow);
    final rows = await db.query(
      'auto_category_prompt_dismissals',
      where: normalizedFlow == null ? null : 'flow = ?',
      whereArgs: normalizedFlow == null ? null : [normalizedFlow],
      orderBy: 'counterparty COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(AutoCategoryPromptDismissal.fromDb).toList(growable: false);
  }

  Future<void> clearPromptDismissal({
    required String counterparty,
    required String flow,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'auto_category_prompt_dismissals',
      where: 'normalizedCounterparty = ? AND flow = ?',
      whereArgs: [
        normalizeCounterparty(counterparty),
        normalizeFlow(flow),
      ],
    );
  }

  Future<void> clearPromptDismissalById(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'auto_category_prompt_dismissals',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteRulesForCategory(int categoryId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'auto_category_rules',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
    );
  }

  Future<int?> getCategoryForTransaction({
    required String? type,
    String? receiver,
    String? creditor,
  }) async {
    if (!await isEnabled()) return null;

    final flow = flowForTransactionType(type);
    final counterparty = resolvePrimaryCounterparty(
      type: type,
      receiver: receiver,
      creditor: creditor,
    );
    if (counterparty != null) {
      final rule = await getRuleForCounterparty(counterparty, flow);
      if (rule != null) {
        return rule.categoryId;
      }
    }

    return ReceiverCategoryService.instance.getCategoryForTransaction(
      receiver: receiver,
      creditor: creditor,
    );
  }
}
