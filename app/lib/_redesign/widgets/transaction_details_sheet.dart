import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/utils/text_utils.dart';

/// Shows the transaction details bottom sheet matching the redesign style.
Future<void> showTransactionDetailsSheet({
  required BuildContext context,
  required Transaction transaction,
  required TransactionProvider provider,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TransactionDetailsSheet(
      transaction: transaction,
      provider: provider,
    ),
  );
}

class _TransactionDetailsSheet extends StatefulWidget {
  final Transaction transaction;
  final TransactionProvider provider;

  const _TransactionDetailsSheet({
    required this.transaction,
    required this.provider,
  });

  @override
  State<_TransactionDetailsSheet> createState() =>
      _TransactionDetailsSheetState();
}

class _TransactionDetailsSheetState extends State<_TransactionDetailsSheet> {
  bool _categoryExpanded = false;

  Transaction get _tx => widget.transaction;
  TransactionProvider get _provider => widget.provider;

  bool get _isCredit => _tx.type == 'CREDIT';

  String get _bankFullName {
    final id = _tx.bankId;
    if (id == null) return 'Unknown';
    if (id == CashConstants.bankId) return CashConstants.bankName;
    try {
      return AppConstants.banks.firstWhere((b) => b.id == id).name;
    } catch (_) {
      return 'Bank $id';
    }
  }

  String get _bankShortName {
    final id = _tx.bankId;
    if (id == null) return 'Bank';
    if (id == CashConstants.bankId) return CashConstants.bankShortName;
    try {
      return AppConstants.banks.firstWhere((b) => b.id == id).shortName;
    } catch (_) {
      return 'Bank $id';
    }
  }

  String get _formattedAmount {
    final formatted = formatNumberAbbreviated(_tx.amount);
    final prefix = _isCredit ? '+ ' : '- ';
    return '${prefix}ETB ${formatted.replaceAll('k', 'K')}';
  }

  String? get _formattedDate {
    final dt = _parseTime(_tx.time);
    if (dt == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$month $day, ${dt.year} $h12:$minute $amPm';
  }

  String? get _formattedBalance {
    final raw = _tx.currentBalance;
    if (raw == null || raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (parsed == null) return raw;
    return 'ETB ${formatNumberAbbreviated(parsed).replaceAll('k', 'K')}';
  }

  String? get _formattedServiceCharge {
    final sc = _tx.serviceCharge;
    if (sc == null || sc == 0) return null;
    return 'ETB ${formatNumberWithComma(sc)}';
  }

  String? get _formattedVat {
    final v = _tx.vat;
    if (v == null || v == 0) return null;
    return 'ETB ${formatNumberWithComma(v)}';
  }

  DateTime? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  Category? get _currentCategory =>
      _provider.getCategoryById(_tx.categoryId);

  List<Category> get _availableCategories {
    final desiredFlow = _isCredit ? 'income' : 'expense';
    final filtered = _provider.categories
        .where((c) => c.flow.toLowerCase() == desiredFlow)
        .toList(growable: false);
    return filtered.isEmpty ? _provider.categories : filtered;
  }

  Future<void> _setCategory(Category category) async {
    if (category.id == null) return;
    await _provider.setCategoryForTransaction(_tx, category);
    if (mounted) {
      setState(() => _categoryExpanded = false);
    }
  }

  Future<void> _clearCategory() async {
    await _provider.clearCategoryForTransaction(_tx);
    if (mounted) {
      setState(() => _categoryExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = _currentCategory;
    final isSelfTransfer = _provider.isSelfTransfer(_tx);
    final selfTransferLabel = _provider.getSelfTransferLabel(_tx);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slate400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transaction Details',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.slate900,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.slate600,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Amount
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                _formattedAmount,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _isCredit ? AppColors.incomeSuccess : AppColors.red,
                ),
              ),
            ),

            // Bank name subtitle
            Text(
              _bankFullName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.slate600,
              ),
            ),

            const SizedBox(height: 20),

            // Scrollable detail rows + category
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DetailRow(label: 'Reference', value: _tx.reference),
                    _DetailRow(label: 'Bank', value: _bankShortName),
                    if (_tx.accountNumber != null &&
                        _tx.accountNumber!.isNotEmpty)
                      _DetailRow(
                          label: 'Account', value: _tx.accountNumber!),
                    if (_formattedDate != null)
                      _DetailRow(
                          label: 'Date & Time', value: _formattedDate!),
                    if (_formattedBalance != null)
                      _DetailRow(
                          label: 'Balance After', value: _formattedBalance!),
                    if (_formattedServiceCharge != null)
                      _DetailRow(
                          label: 'Service Charge',
                          value: _formattedServiceCharge!),
                    if (_formattedVat != null)
                      _DetailRow(label: 'VAT', value: _formattedVat!),

                    // Category row
                    if (isSelfTransfer)
                      _DetailRow(
                        label: 'Category',
                        value: selfTransferLabel ?? 'Self transfer',
                      )
                    else
                      _buildCategoryRow(category),

                    // Category picker chips
                    if (_categoryExpanded && !isSelfTransfer)
                      _buildCategoryPicker(category),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow(Category? category) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            'Category',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.slate500,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _categoryExpanded = !_categoryExpanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (category != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _categoryColor(category),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    category.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _categoryColor(category),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else
                  Text(
                    'Categorize',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.slate400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  _categoryExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: AppColors.slate400,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPicker(Category? current) {
    final categories = _availableCategories;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...categories.map((c) {
            final isSelected = current?.id != null && c.id == current!.id;
            return _CategoryPickerChip(
              label: c.name,
              color: _categoryColor(c),
              isSelected: isSelected,
              onTap: () => _setCategory(c),
            );
          }),
          if (current != null)
            _CategoryPickerChip(
              label: 'Remove',
              color: AppColors.red,
              isSelected: false,
              isRemove: true,
              onTap: _clearCategory,
            ),
        ],
      ),
    );
  }

  Color _categoryColor(Category category) {
    if (category.flow == 'income') {
      return category.essential
          ? AppColors.incomeSuccess
          : const Color(0xFF14B8A6);
    }
    // expense
    return category.essential ? AppColors.blue : AppColors.amber;
  }
}

// ── Detail row ──────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.slate500,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.slate900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category picker chip ────────────────────────────────────────────────────

class _CategoryPickerChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final bool isRemove;
  final VoidCallback onTap;

  const _CategoryPickerChip({
    required this.label,
    required this.color,
    required this.isSelected,
    this.isRemove = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isSelected
        ? color.withValues(alpha: 0.15)
        : Colors.transparent;
    final border = isSelected ? color : AppColors.border;
    final textColor = isRemove ? AppColors.red : color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isRemove) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
