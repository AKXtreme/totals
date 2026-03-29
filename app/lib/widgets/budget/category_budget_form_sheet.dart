import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/providers/transaction_provider.dart';

class CategoryBudgetFormSheet extends StatefulWidget {
  final Budget? budget;

  const CategoryBudgetFormSheet({
    super.key,
    this.budget,
  });

  @override
  State<CategoryBudgetFormSheet> createState() =>
      _CategoryBudgetFormSheetState();
}

class _CategoryBudgetFormSheetState extends State<CategoryBudgetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _alertThresholdController = TextEditingController(text: '80');

  int? _selectedCategoryId;
  String _selectedTimeFrame = 'monthly';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.budget != null) {
      _amountController.text = widget.budget!.amount.toStringAsFixed(2);
      _alertThresholdController.text =
          widget.budget!.alertThreshold.toStringAsFixed(1);
      _selectedCategoryId = widget.budget!.categoryId;
      // Ensure timeFrame is one of the valid options (daily, monthly, yearly, never)
      final savedTimeFrame = widget.budget!.timeFrame ?? 'monthly';
      if (['daily', 'monthly', 'yearly', 'never'].contains(savedTimeFrame)) {
        _selectedTimeFrame = savedTimeFrame;
      } else {
        // Handle legacy 'unlimited' value by converting to 'never'
        if (savedTimeFrame == 'unlimited') {
          _selectedTimeFrame = 'never';
        } else {
          _selectedTimeFrame = 'monthly'; // Default to monthly if invalid
        }
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _alertThresholdController.dispose();
    super.dispose();
  }

  DateTime _getPeriodStart() {
    final now = DateTime.now();
    switch (_selectedTimeFrame) {
      case 'daily':
        return DateTime(now.year, now.month, now.day);
      case 'monthly':
        return DateTime(now.year, now.month, 1);
      case 'yearly':
        return DateTime(now.year, 1, 1);
      case 'never':
        return DateTime.now();
      default:
        return DateTime.now();
    }
  }

  Future<void> _saveBudget() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final amount = double.parse(_amountController.text);
      final alertThreshold = double.parse(_alertThresholdController.text);

      final transactionProvider =
          Provider.of<TransactionProvider>(context, listen: false);
      final category = transactionProvider.categories.firstWhere(
        (c) => c.id == _selectedCategoryId,
      );
      final selectedCategoryIds = widget.budget?.categoryIds != null &&
              widget.budget!.categoryIds!.isNotEmpty
          ? List<int>.from(widget.budget!.categoryIds!)
          : (_selectedCategoryId != null ? <int>[_selectedCategoryId!] : null);

      final budget = Budget(
        id: widget.budget?.id,
        name: '${category.name} Budget',
        type: 'category',
        amount: amount,
        categoryId: _selectedCategoryId,
        categoryIds: selectedCategoryIds,
        startDate: widget.budget?.startDate ?? _getPeriodStart(),
        rollover: false,
        alertThreshold: alertThreshold,
        isActive: widget.budget?.isActive ?? true,
        createdAt: widget.budget?.createdAt ?? DateTime.now(),
        timeFrame: _selectedTimeFrame,
      );

      final provider = Provider.of<BudgetProvider>(context, listen: false);
      if (widget.budget == null) {
        await provider.createBudget(budget);
      } else {
        await provider.updateBudget(budget);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteBudget() async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Delete Budget'),
        content: const Text('Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await Provider.of<BudgetProvider>(context, listen: false)
          .deleteBudget(widget.budget!.id!);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Budget deleted')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = Provider.of<TransactionProvider>(context)
        .categories
        .where((c) => c.flow == 'expense')
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pull Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              Text(
                widget.budget == null ? 'New Budget' : 'Edit Budget',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),

              // Category Chip Selector
              _buildSectionLabel("Category"),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = _selectedCategoryId == cat.id;
                    return ChoiceChip(
                      showCheckmark: false,
                      label: Text(cat.name),
                      selected: isSelected,
                      onSelected: widget.budget != null
                          ? null
                          : (selected) {
                              setState(() => _selectedCategoryId = cat.id);
                            },
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      selectedColor: theme.colorScheme.primary,
                      backgroundColor:
                          theme.colorScheme.surfaceVariant.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: BorderSide.none,
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Time Frame Segmented Control
              _buildSectionLabel("Reset Frequency"),
              const SizedBox(height: 12),
              CupertinoSlidingSegmentedControl<String>(
                groupValue: _selectedTimeFrame,
                backgroundColor:
                    theme.colorScheme.surfaceVariant.withOpacity(0.3),
                thumbColor: theme.colorScheme.surface,
                children: {
                  'daily': _buildSegmentText('Daily'),
                  'monthly': _buildSegmentText('Monthly'),
                  'yearly': _buildSegmentText('Yearly'),
                  'never': _buildSegmentText('Never'),
                },
                onValueChanged: (val) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedTimeFrame = val!);
                },
              ),
              const SizedBox(height: 24),

              // Amount Input
              _buildModernField(
                controller: _amountController,
                label: "Budget Limit",
                icon: Icons.account_balance_wallet_rounded,
                prefix: "ETB ",
                hint: "0.00",
              ),
              const SizedBox(height: 20),

              // Alert Threshold Input
              _buildModernField(
                controller: _alertThresholdController,
                label: "Alert Threshold",
                icon: Icons.notifications_active_rounded,
                suffix: "%",
                hint: "80",
              ),
              const SizedBox(height: 32),

              // Buttons
              Row(
                children: [
                  if (widget.budget != null) ...[
                    IconButton.filledTonal(
                      onPressed: _isLoading ? null : _deleteBudget,
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.red),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.red.withOpacity(0.1),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveBudget,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              widget.budget == null
                                  ? 'Create Budget'
                                  : 'Update Budget',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
      ),
    );
  }

  Widget _buildSegmentText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildModernField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? prefix,
    String? suffix,
    String? hint,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            suffixText: suffix,
            prefixIcon: Icon(icon, color: theme.colorScheme.primary),
            filled: true,
            fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: theme.colorScheme.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.all(20),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Required';
            if (double.tryParse(value) == null) return 'Invalid number';
            return null;
          },
        ),
      ],
    );
  }
}
