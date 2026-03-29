class AutoCategorizationRule {
  final int? id;
  final String counterparty;
  final String normalizedCounterparty;
  final String flow;
  final int categoryId;
  final String createdAt;

  const AutoCategorizationRule({
    this.id,
    required this.counterparty,
    required this.normalizedCounterparty,
    required this.flow,
    required this.categoryId,
    required this.createdAt,
  });

  factory AutoCategorizationRule.fromDb(Map<String, dynamic> row) {
    return AutoCategorizationRule(
      id: row['id'] as int?,
      counterparty: (row['counterparty'] as String?) ?? '',
      normalizedCounterparty: (row['normalizedCounterparty'] as String?) ?? '',
      flow: ((row['flow'] as String?) ?? 'expense').trim().toLowerCase() ==
              'income'
          ? 'income'
          : 'expense',
      categoryId: row['categoryId'] as int? ?? 0,
      createdAt: (row['createdAt'] as String?) ?? '',
    );
  }

  factory AutoCategorizationRule.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    final rawFlow = (json['flow'] as String?)?.trim().toLowerCase();
    final counterparty = (json['counterparty'] as String?) ?? '';
    final normalizedCounterparty =
        (json['normalizedCounterparty'] as String?) ?? '';
    return AutoCategorizationRule(
      id: toInt(json['id']),
      counterparty: counterparty,
      normalizedCounterparty: normalizedCounterparty.isNotEmpty
          ? normalizedCounterparty
          : counterparty.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
      flow: rawFlow == 'income' ? 'income' : 'expense',
      categoryId: toInt(json['categoryId']) ?? 0,
      createdAt:
          (json['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'counterparty': counterparty,
      'normalizedCounterparty': normalizedCounterparty,
      'flow': flow,
      'categoryId': categoryId,
      'createdAt': createdAt,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'counterparty': counterparty,
      'normalizedCounterparty': normalizedCounterparty,
      'flow': flow,
      'categoryId': categoryId,
      'createdAt': createdAt,
    };
  }
}

class AutoCategoryPromptDismissal {
  final int? id;
  final String counterparty;
  final String normalizedCounterparty;
  final String flow;
  final String createdAt;

  const AutoCategoryPromptDismissal({
    this.id,
    required this.counterparty,
    required this.normalizedCounterparty,
    required this.flow,
    required this.createdAt,
  });

  factory AutoCategoryPromptDismissal.fromDb(Map<String, dynamic> row) {
    return AutoCategoryPromptDismissal(
      id: row['id'] as int?,
      counterparty: (row['counterparty'] as String?) ?? '',
      normalizedCounterparty: (row['normalizedCounterparty'] as String?) ?? '',
      flow: ((row['flow'] as String?) ?? 'expense').trim().toLowerCase() ==
              'income'
          ? 'income'
          : 'expense',
      createdAt: (row['createdAt'] as String?) ?? '',
    );
  }

  factory AutoCategoryPromptDismissal.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    final rawFlow = (json['flow'] as String?)?.trim().toLowerCase();
    final counterparty = (json['counterparty'] as String?) ?? '';
    final normalizedCounterparty =
        (json['normalizedCounterparty'] as String?) ?? '';
    return AutoCategoryPromptDismissal(
      id: toInt(json['id']),
      counterparty: counterparty,
      normalizedCounterparty: normalizedCounterparty.isNotEmpty
          ? normalizedCounterparty
          : counterparty.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
      flow: rawFlow == 'income' ? 'income' : 'expense',
      createdAt:
          (json['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'counterparty': counterparty,
      'normalizedCounterparty': normalizedCounterparty,
      'flow': flow,
      'createdAt': createdAt,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'counterparty': counterparty,
      'normalizedCounterparty': normalizedCounterparty,
      'flow': flow,
      'createdAt': createdAt,
    };
  }
}

class AutoCategorizationPromptDecision {
  final String counterparty;
  final String flow;
  final int categoryId;
  final AutoCategorizationRule? existingRule;

  const AutoCategorizationPromptDecision({
    required this.counterparty,
    required this.flow,
    required this.categoryId,
    required this.existingRule,
  });

  bool get updatesExistingRule => existingRule != null;
}
