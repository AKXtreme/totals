import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/providers/budget_provider.dart';

class BudgetFormSheet extends StatefulWidget {
  final Budget? budget;
  final String? initialType;
  final int? initialCategoryId;

  const BudgetFormSheet({
    super.key,
    this.budget,
    this.initialType,
    this.initialCategoryId,
  });

  @override
  State<BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends State<BudgetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _alertThresholdController = TextEditingController(text: '80');

  String _selectedType = 'monthly';
  int? _selectedCategoryId;
  bool _rollover = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.budget != null) {
      _nameController.text = widget.budget!.name;
      _amountController.text = widget.budget!.amount.toStringAsFixed(2);
      _alertThresholdController.text =
          widget.budget!.alertThreshold.toStringAsFixed(1);
      _selectedType = widget.budget!.type;
      _selectedCategoryId = widget.budget!.categoryId;
      _rollover = widget.budget!.rollover;
    } else {
      if (widget.initialType != null) {
        _selectedType = widget.initialType!;
      }
      // Note: category budgets are handled by CategoryBudgetFormSheet
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _alertThresholdController.dispose();
    super.dispose();
  }

  DateTime _getPeriodStart() {
    final now = DateTime.now();
    switch (_selectedType) {
      case 'daily':
        return DateTime(now.year, now.month, now.day);
      case 'monthly':
        return DateTime(now.year, now.month, 1);
      case 'yearly':
        return DateTime(now.year, 1, 1);
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  Future<void> _saveBudget() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final amount = double.parse(_amountController.text);
      final alertThreshold = double.parse(_alertThresholdController.text);
      final selectedCategoryIds = widget.budget?.categoryIds != null &&
              widget.budget!.categoryIds!.isNotEmpty
          ? List<int>.from(widget.budget!.categoryIds!)
          : (_selectedCategoryId != null ? <int>[_selectedCategoryId!] : null);

      final budget = Budget(
        id: widget.budget?.id,
        name: _nameController.text.trim(),
        type: _selectedType,
        amount: amount,
        categoryId: _selectedCategoryId,
        categoryIds: selectedCategoryIds,
        startDate: widget.budget?.startDate ?? _getPeriodStart(),
        rollover: _rollover,
        alertThreshold: alertThreshold,
        isActive: widget.budget?.isActive ?? true,
        createdAt: widget.budget?.createdAt ?? DateTime.now(),
      );

      final provider = Provider.of<BudgetProvider>(context, listen: false);
      widget.budget == null
          ? await provider.createBudget(budget)
          : await provider.updateBudget(budget);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              // Drag Handle
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
                widget.budget == null ? 'Create Budget' : 'Edit Budget',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 24),

              // --- TEXT INPUTS ---
              _buildModernField(
                controller: _nameController,
                label: "Budget Name",
                hint: "e.g. Monthly Groceries",
                icon: Icons.edit_note_rounded,
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: _buildModernField(
                      controller: _amountController,
                      label: "Amount",
                      prefix: "ETB ",
                      icon: Icons.payments_rounded,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildModernField(
                      controller: _alertThresholdController,
                      label: "Alert at %",
                      suffix: "%",
                      icon: Icons.notification_important_rounded,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // --- ROLLOVER SWITCH ---
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SwitchListTile.adaptive(
                  title: const Text('Enable Rollover',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Carry over leftovers to next month'),
                  value: _rollover,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (val) => setState(() => _rollover = val),
                ),
              ),
              const SizedBox(height: 32),

              // --- ACTIONS ---
              Row(
                children: [
                  if (widget.budget != null)
                    IconButton.filledTonal(
                      onPressed: _isLoading ? null : _deleteBudget,
                      icon: const Icon(Icons.delete_sweep_rounded,
                          color: Colors.red),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.red.withOpacity(0.08),
                      ),
                    ),
                  if (widget.budget != null) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveBudget,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const CupertinoActivityIndicator(
                              color: Colors.white)
                          : Text(
                              widget.budget == null
                                  ? 'Create Budget'
                                  : 'Save Changes',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
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

  Widget _buildSegment(String text, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : null,
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
      ),
    );
  }

  Widget _buildModernField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? prefix,
    String? suffix,
    String? hint,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            suffixText: suffix,
            prefixIcon: Icon(icon, size: 20, color: theme.colorScheme.primary),
            filled: true,
            fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
          ),
          validator: (val) => (val == null || val.isEmpty) ? 'Required' : null,
        ),
      ],
    );
  }

  Future<void> _deleteBudget() async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text('Delete Budget?'),
        content: Text('Delete "${widget.budget!.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await Provider.of<BudgetProvider>(context, listen: false)
          .deleteBudget(widget.budget!.id!);
      if (mounted) Navigator.pop(context);
    }
  }
}
