import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  String get _counterparty {
    final receiver = _tx.receiver?.trim();
    final creditor = _tx.creditor?.trim();
    if (receiver != null && receiver.isNotEmpty) return receiver;
    if (creditor != null && creditor.isNotEmpty) return creditor;
    return _bankFullName;
  }

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
    final formatted = formatNumberWithComma(_tx.amount);
    final prefix = _isCredit ? '+ ' : '- ';
    return '${prefix}ETB $formatted';
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
    final now = DateTime.now();
    final yearSuffix = dt.year != now.year ? ', ${dt.year}' : '';
    return '$month $day$yearSuffix · $h12:$minute $amPm';
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
    if (mounted) Navigator.pop(context);
  }

  Future<void> _clearCategory() async {
    await _provider.clearCategoryForTransaction(_tx);
    if (mounted) Navigator.pop(context);
  }

  void _copyReference() {
    Clipboard.setData(ClipboardData(text: _tx.reference));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reference copied')),
    );
  }

  Future<void> _showNewCategoryDialog() async {
    final nameController = TextEditingController();
    final flow = _isCredit ? 'income' : 'expense';
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (created == true && nameController.text.trim().isNotEmpty) {
      await _provider.createCategory(
        name: nameController.text.trim(),
        essential: false,
        flow: flow,
      );
      if (mounted) setState(() {});
    }
    nameController.dispose();
  }

  Future<void> _deleteTransaction() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text(
          'This will permanently remove this transaction. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context);
      await _provider
          .deleteTransactionsByReferences([_tx.reference]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = _currentCategory;
    final isSelfTransfer = _provider.isSelfTransfer(_tx);
    final selfTransferLabel = _provider.getSelfTransferLabel(_tx);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: AppColors.textTertiary(context),
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
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.textSecondary(context),
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

            // Counterparty name
            Text(
              _counterparty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),

            const SizedBox(height: 20),

            // Scrollable detail rows + category + delete
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DetailRow(
                      label: 'Reference',
                      value: _tx.reference,
                      marquee: true,
                      onTap: _copyReference,
                    ),
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

                    const SizedBox(height: 20),

                    // Delete button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _deleteTransaction,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Delete transaction'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.red,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: AppColors.red.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                    ),

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
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: AppColors.borderColor(context), width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _kLabelWidth,
            child: Text(
              'Category',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary(context),
              ),
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
                      color: AppColors.textTertiary(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  _categoryExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: AppColors.textTertiary(context),
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
              icon: iconForCategoryKey(c.iconKey),
              isSelected: isSelected,
              onTap: () => _setCategory(c),
            );
          }),
          if (current != null)
            _CategoryPickerChip(
              label: 'Remove',
              color: AppColors.red,
              icon: Icons.close_rounded,
              isSelected: false,
              isRemove: true,
              onTap: _clearCategory,
            ),
          _CategoryPickerChip(
            label: '+ New',
            color: AppColors.textSecondary(context),
            icon: Icons.add,
            isSelected: false,
            onTap: () => _showNewCategoryDialog(),
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
    return category.essential ? AppColors.blue : AppColors.amber;
  }
}

// ── Constants ───────────────────────────────────────────────────────────────

const double _kLabelWidth = 110;

// ── Detail row ──────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool marquee;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.label,
    required this.value,
    this.marquee = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textPrimary(context),
      fontWeight: FontWeight.w600,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: AppColors.borderColor(context), width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _kLabelWidth,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          const Spacer(),
          if (marquee)
            Flexible(
              child: GestureDetector(
                onTap: onTap,
                child: _MarqueeText(text: value, style: valueStyle),
              ),
            )
          else
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: valueStyle,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Marquee text (auto-scrolls if overflowing) ──────────────────────────────

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _MarqueeText({required this.text, this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _animController;
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  void _checkOverflow() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      setState(() => _overflows = true);
      _startScroll(maxScroll);
    }
  }

  void _startScroll(double extent) {
    _animController.addListener(() {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_animController.value * extent);
    });
    _animController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        if (!_overflows) {
          return const LinearGradient(
            colors: [Colors.white, Colors.white],
          ).createShader(bounds);
        }
        return const LinearGradient(
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.05, 0.95, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(widget.text, style: widget.style),
      ),
    );
  }
}

// ── Category picker chip ────────────────────────────────────────────────────

class _CategoryPickerChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool isSelected;
  final bool isRemove;
  final VoidCallback onTap;

  const _CategoryPickerChip({
    required this.label,
    required this.color,
    required this.icon,
    required this.isSelected,
    this.isRemove = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isSelected
        ? color.withValues(alpha: 0.15)
        : Colors.transparent;
    final border =
        isSelected ? color : AppColors.borderColor(context);
    final textColor = isRemove
        ? AppColors.red
        : AppColors.textPrimary(context);

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
