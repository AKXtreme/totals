import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/_redesign/theme/app_icons.dart';

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
  bool _showNewCategoryForm = false;
  bool _showColorChoices = false;
  String _draftColorKey = _kCategoryColorOptions.first.key;
  final TextEditingController _newCategoryController = TextEditingController();
  final FocusNode _newCategoryFocus = FocusNode();
  final ScrollController _sheetScrollController = ScrollController();
  double _lastKeyboardInset = 0;

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
    return _provider.getBankName(_tx.bankId);
  }

  String get _bankShortName {
    return _provider.getBankShortName(_tx.bankId);
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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

  Category? get _currentCategory => _provider.getCategoryById(_tx.categoryId);

  List<Category> get _availableCategories {
    final desiredFlow = _isCredit ? 'income' : 'expense';
    final filtered = _provider.categories
        .where((c) => c.flow.toLowerCase() == desiredFlow)
        .toList(growable: false);
    final base = filtered.isEmpty ? _provider.categories : filtered;
    return base
        .where((c) => c.name.trim().toLowerCase() != 'self')
        .toList(growable: false);
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

  void _toggleNewCategoryForm() {
    final shouldShow = !_showNewCategoryForm;
    setState(() {
      _showNewCategoryForm = shouldShow;
      _showColorChoices = false;
      if (!shouldShow) {
        _newCategoryController.clear();
      }
    });
    if (!shouldShow) {
      _newCategoryFocus.unfocus();
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _newCategoryFocus.requestFocus();
      _scrollComposerIntoView();
    });
  }

  void _toggleColorChoices() {
    final willOpen = !_showColorChoices;
    setState(() => _showColorChoices = willOpen);
    if (!willOpen) return;
    _scrollComposerIntoView();
  }

  void _scrollComposerIntoView() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetScrollController.hasClients) return;
      final target = _sheetScrollController.position.maxScrollExtent;
      _sheetScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Category? _findCategoryByNameAndFlow({
    required String name,
    required String flow,
    Set<int>? excludeIds,
  }) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedFlow = flow.toLowerCase();
    return _provider.categories
        .where((c) =>
            c.flow.toLowerCase() == normalizedFlow &&
            c.name.trim().toLowerCase() == normalizedName &&
            (c.id == null || !(excludeIds?.contains(c.id) ?? false)))
        .fold<Category?>(
          null,
          (best, c) => best == null || (c.id ?? 0) > (best.id ?? 0) ? c : best,
        );
  }

  bool _categoryExistsForFlow({
    required String name,
    required String flow,
  }) {
    return _findCategoryByNameAndFlow(name: name, flow: flow) != null;
  }

  String? _extractColorKey(String? iconKey) {
    if (iconKey == null || iconKey.isEmpty) return null;
    const prefix = 'color:';
    if (!iconKey.startsWith(prefix)) return null;
    final value = iconKey.substring(prefix.length).trim();
    if (value.isEmpty) return null;
    return value;
  }

  Color _colorFromKey(String colorKey) {
    for (final option in _kCategoryColorOptions) {
      if (option.key == colorKey) return option.color;
    }
    return _kCategoryColorOptions.first.color;
  }

  int _fallbackColorIndex(Category category) {
    final seed = '${category.flow}:${category.name.toLowerCase()}';
    int hash = 0;
    for (final code in seed.codeUnits) {
      hash = (hash + code) & 0x7fffffff;
    }
    return hash % _kCategoryColorOptions.length;
  }

  Future<void> _setSelfCategory() async {
    const selfName = 'Self';
    final flow = _isCredit ? 'income' : 'expense';
    final existing = _findCategoryByNameAndFlow(name: selfName, flow: flow);
    if (existing != null) {
      await _setCategory(existing);
      return;
    }

    final knownCategoryIds =
        _provider.categories.map((c) => c.id).whereType<int>().toSet();

    try {
      await _provider.createCategory(
        name: selfName,
        essential: false,
        flow: flow,
        colorKey: 'gray',
      );
    } catch (_) {
      if (!mounted) return;
    }

    final created = _findCategoryByNameAndFlow(
      name: selfName,
      flow: flow,
      excludeIds: knownCategoryIds,
    );
    final target =
        created ?? _findCategoryByNameAndFlow(name: selfName, flow: flow);
    if (target != null) {
      await _setCategory(target);
    }
  }

  Future<void> _createNewCategoryInline() async {
    final createdName = _newCategoryController.text.trim();
    if (createdName.isEmpty) return;
    final flow = _isCredit ? 'income' : 'expense';
    if (_categoryExistsForFlow(name: createdName, flow: flow)) {
      _newCategoryFocus.requestFocus();
      return;
    }
    final knownCategoryIds =
        _provider.categories.map((c) => c.id).whereType<int>().toSet();
    try {
      await _provider.createCategory(
        name: createdName,
        essential: false,
        flow: flow,
        colorKey: _draftColorKey,
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().toLowerCase();
      if (message.contains('unique') ||
          message.contains('constraint') ||
          message.contains('already exists')) {
        _newCategoryFocus.requestFocus();
        setState(() {});
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create category')),
      );
      return;
    }
    if (!mounted) return;
    final createdCategory = _findCategoryByNameAndFlow(
      name: createdName,
      flow: flow,
      excludeIds: knownCategoryIds,
    );
    if (createdCategory != null) {
      await _setCategory(createdCategory);
      return;
    }
    setState(() {
      _showNewCategoryForm = false;
      _showColorChoices = false;
      _newCategoryController.clear();
    });
    _newCategoryFocus.unfocus();
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
      await _provider.deleteTransactionsByReferences([_tx.reference]);
    }
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    _newCategoryFocus.dispose();
    _sheetScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = _currentCategory;
    final isLockedSelfTransfer = _provider.isDetectedSelfTransfer(_tx);
    final selfTransferLabel = _provider.getSelfTransferLabel(_tx);
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardScrollBuffer = keyboardInset > 0 ? 88.0 : 24.0;
    if (keyboardInset > _lastKeyboardInset && _showNewCategoryForm) {
      _scrollComposerIntoView();
    }
    _lastKeyboardInset = keyboardInset;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
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
                      icon: const Icon(AppIcons.close, size: 20),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: _MarqueeText(
                    text: _counterparty,
                    centerWhenStatic: true,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Scrollable detail rows + category + delete
              Flexible(
                child: SingleChildScrollView(
                  controller: _sheetScrollController,
                  padding: EdgeInsets.fromLTRB(20, 0, 20, keyboardScrollBuffer),
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
                      // if (_tx.accountNumber != null &&
                      //     _tx.accountNumber!.isNotEmpty)
                      //   _DetailRow(label: 'Account', value: _tx.accountNumber!),
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
                      if (isLockedSelfTransfer)
                        _DetailRow(
                          label: 'Category',
                          value: selfTransferLabel ?? 'Self transfer',
                        )
                      else
                        _buildCategoryRow(category),

                      // Category picker chips
                      if (_categoryExpanded && !isLockedSelfTransfer)
                        _buildCategoryPicker(category),

                      const SizedBox(height: 20),

                      // Delete button
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _deleteTransaction,
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
      ),
    );
  }

  Widget _buildCategoryRow(Category? category) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: AppColors.borderColor(context), width: 1)),
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
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.5,
            ),
            child: GestureDetector(
              onTap: () =>
                  setState(() => _categoryExpanded = !_categoryExpanded),
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
                    Flexible(
                      child: Text(
                        category.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _categoryColor(category),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                        ? AppIcons.keyboard_arrow_up
                        : AppIcons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.textTertiary(context),
                  ),
                ],
              ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
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
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CategoryPickerChip(
                label: 'Self',
                color: _colorFromKey('gray'),
                isSelected: current?.name.trim().toLowerCase() == 'self',
                showColorDot: false,
                onTap: _setSelfCategory,
              ),
              _CategoryPickerChip(
                label: _showNewCategoryForm ? 'Cancel' : '+ New',
                color: _showNewCategoryForm
                    ? AppColors.red
                    : AppColors.textSecondary(context),
                isSelected: false,
                isRemove: _showNewCategoryForm,
                showColorDot: false,
                onTap: _toggleNewCategoryForm,
              ),
              if (current != null)
                _CategoryPickerChip(
                  label: 'Remove',
                  color: AppColors.red,
                  isSelected: false,
                  isRemove: true,
                  showColorDot: false,
                  onTap: _clearCategory,
                ),
            ],
          ),
          if (_showNewCategoryForm) _buildNewCategoryComposer(),
        ],
      ),
    );
  }

  Widget _buildNewCategoryComposer() {
    final selectedColor = _colorFromKey(_draftColorKey);
    final flow = _isCredit ? 'income' : 'expense';
    final draftName = _newCategoryController.text.trim();
    final isDuplicateName = draftName.isNotEmpty &&
        _categoryExistsForFlow(name: draftName, flow: flow);
    final canSubmit = draftName.isNotEmpty && !isDuplicateName;
    final textFieldBorderColor =
        isDuplicateName ? AppColors.red : AppColors.borderColor(context);
    final focusedBorderColor =
        isDuplicateName ? AppColors.red : AppColors.primaryLight;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newCategoryController,
                  focusNode: _newCategoryFocus,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _createNewCategoryInline(),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Category name',
                    hintStyle:
                        TextStyle(color: AppColors.textTertiary(context)),
                    filled: true,
                    fillColor: AppColors.surfaceColor(context),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: textFieldBorderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: textFieldBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: focusedBorderColor,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleColorChoices,
                child: Container(
                  height: 40,
                  width: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Icon(
                        _showColorChoices
                            ? AppIcons.keyboard_arrow_up
                            : AppIcons.keyboard_arrow_down,
                        size: 16,
                        color: AppColors.textSecondary(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: canSubmit ? _createNewCategoryInline : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Add',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (_showColorChoices) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _kCategoryColorOptions.map((option) {
                    final selected = option.key == _draftColorKey;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _draftColorKey = option.key;
                            _showColorChoices = false;
                          });
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: option.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? AppColors.textPrimary(context)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _categoryColor(Category category) {
    final explicitKey = _normalizeColorKey(category.colorKey) ??
        _extractColorKey(category.iconKey);
    if (explicitKey != null) {
      return _colorFromKey(explicitKey);
    }
    return _kCategoryColorOptions[_fallbackColorIndex(category)].color;
  }

  String? _normalizeColorKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

// ── Constants ───────────────────────────────────────────────────────────────

const double _kLabelWidth = 110;

class _CategoryColorOption {
  final String key;
  final Color color;

  const _CategoryColorOption({
    required this.key,
    required this.color,
  });
}

const List<_CategoryColorOption> _kCategoryColorOptions = [
  _CategoryColorOption(key: 'blue', color: AppColors.blue),
  _CategoryColorOption(key: 'emerald', color: AppColors.incomeSuccess),
  _CategoryColorOption(key: 'amber', color: AppColors.amber),
  _CategoryColorOption(key: 'red', color: AppColors.red),
  _CategoryColorOption(key: 'rose', color: Color(0xFFFB7185)),
  _CategoryColorOption(key: 'magenta', color: Color(0xFFD946EF)),
  _CategoryColorOption(key: 'violet', color: Color(0xFF8B5CF6)),
  _CategoryColorOption(key: 'indigo', color: Color(0xFF6366F1)),
  _CategoryColorOption(key: 'teal', color: Color(0xFF14B8A6)),
  _CategoryColorOption(key: 'mint', color: Color(0xFF34D399)),
  _CategoryColorOption(key: 'orange', color: Color(0xFFF97316)),
  _CategoryColorOption(key: 'tangerine', color: Color(0xFFFF8C42)),
  _CategoryColorOption(key: 'yellow', color: Color(0xFFEAB308)),
  _CategoryColorOption(key: 'cyan', color: Color(0xFF06B6D4)),
  _CategoryColorOption(key: 'sky', color: Color(0xFF0EA5E9)),
  _CategoryColorOption(key: 'lime', color: Color(0xFF84CC16)),
  _CategoryColorOption(key: 'pink', color: Color(0xFFEC4899)),
  _CategoryColorOption(key: 'brown', color: Color(0xFFA16207)),
  _CategoryColorOption(key: 'gray', color: Color(0xFF6B7280)),
];

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
            bottom:
                BorderSide(color: AppColors.borderColor(context), width: 1)),
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
  final bool centerWhenStatic;

  const _MarqueeText({
    required this.text,
    this.style,
    this.centerWhenStatic = false,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  final _px = ValueNotifier<double>(0.0);
  double _scrollDistance = 0;
  static const _gap = 20.0;
  static const _pxPerSec = 30.0;

  @override
  void dispose() {
    _ticker?.dispose();
    _px.dispose();
    super.dispose();
  }

  void _ensureScroll(double distance) {
    _scrollDistance = distance;
    if (_ticker != null) return;
    _ticker = createTicker((elapsed) {
      _px.value =
          (elapsed.inMicroseconds * _pxPerSec / 1000000.0) % _scrollDistance;
    })
      ..start();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();

      if (tp.width <= constraints.maxWidth) {
        final staticText = Text(widget.text, style: widget.style, maxLines: 1);
        if (!widget.centerWhenStatic) return staticText;
        return Align(
          alignment: Alignment.center,
          child: staticText,
        );
      }

      _ensureScroll(tp.width + _gap);

      return SizedBox(
        width: constraints.maxWidth,
        height: tp.height,
        child: ClipRect(
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.06, 0.94, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: _px,
                builder: (context, px, child) => Transform.translate(
                  offset: Offset(-px, 0),
                  child: child,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.text, style: widget.style),
                    const SizedBox(width: _gap),
                    Text(widget.text, style: widget.style),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ── Category picker chip ────────────────────────────────────────────────────

class _CategoryPickerChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final bool isRemove;
  final bool showColorDot;
  final VoidCallback onTap;

  const _CategoryPickerChip({
    required this.label,
    required this.color,
    required this.isSelected,
    this.isRemove = false,
    this.showColorDot = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? color.withValues(alpha: 0.15) : Colors.transparent;
    final border = isSelected ? color : AppColors.borderColor(context);
    final textColor = isRemove ? AppColors.red : AppColors.textPrimary(context);

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
            if (showColorDot) ...[
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
