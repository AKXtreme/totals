import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/text_utils.dart';

class TodaysTransactionsPage extends StatefulWidget {
  const TodaysTransactionsPage({super.key});

  @override
  State<TodaysTransactionsPage> createState() =>
      _TodaysTransactionsPageState();
}

class _TodaysTransactionsPageState extends State<TodaysTransactionsPage> {
  final Set<String> _selectedRefs = {};

  bool get _isSelecting => _selectedRefs.isNotEmpty;

  void _toggle(Transaction tx) {
    setState(() {
      if (_selectedRefs.contains(tx.reference)) {
        _selectedRefs.remove(tx.reference);
      } else {
        _selectedRefs.add(tx.reference);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedRefs.clear());

  Future<void> _deleteSelected(TransactionProvider provider) async {
    if (_selectedRefs.isEmpty) return;
    final count = _selectedRefs.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count transaction${count > 1 ? 's' : ''}?'),
        content: const Text('This cannot be undone.'),
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
    if (confirmed == true) {
      await provider.deleteTransactionsByReferences(_selectedRefs.toList());
      _clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final transactions = provider.todayTransactions;

        return Scaffold(
          backgroundColor: AppColors.background(context),
          appBar: AppBar(
            backgroundColor: AppColors.background(context),
            surfaceTintColor: Colors.transparent,
            leading: _isSelecting
                ? IconButton(
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close),
                  )
                : IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
            title: Text(
              _isSelecting
                  ? '${_selectedRefs.length} selected'
                  : "Today's Transactions",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: _isSelecting
                    ? AppColors.primaryDark
                    : AppColors.textPrimary(context),
              ),
            ),
            actions: [
              if (_isSelecting)
                IconButton(
                  onPressed: () => _deleteSelected(provider),
                  icon: Icon(Icons.delete_outline_rounded,
                      color: AppColors.red),
                ),
            ],
          ),
          body: transactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 48,
                        color: AppColors.textTertiary(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No transactions today',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final bankLabel = _bankLabel(tx.bankId);
                    final category =
                        provider.getCategoryById(tx.categoryId);
                    final selfTransferLabel =
                        provider.getSelfTransferLabel(tx);
                    final categoryLabel =
                        selfTransferLabel ?? category?.name ?? 'Categorize';
                    final isCategorized =
                        selfTransferLabel != null || category != null;
                    final isCredit = tx.type == 'CREDIT';
                    final selected =
                        _selectedRefs.contains(tx.reference);

                    return _TransactionTile(
                      bank: bankLabel,
                      category: categoryLabel,
                      isCategorized: isCategorized,
                      amount: _amountLabel(tx.amount, isCredit: isCredit),
                      amountColor: isCredit
                          ? AppColors.incomeSuccess
                          : AppColors.red,
                      name: _counterparty(tx),
                      timestamp: _timeLabel(tx),
                      selected: selected,
                      onTap: _isSelecting
                          ? () => _toggle(tx)
                          : () => showTransactionDetailsSheet(
                                context: context,
                                transaction: tx,
                                provider: provider,
                              ),
                      onLongPress: () => _toggle(tx),
                    );
                  },
                ),
        );
      },
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

String _bankLabel(int? bankId) {
  if (bankId == null) return 'Bank';
  if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
  try {
    final bank = AppConstants.banks.firstWhere((b) => b.id == bankId);
    return bank.shortName;
  } catch (_) {
    return 'Bank $bankId';
  }
}

String _amountLabel(double amount, {required bool isCredit}) {
  final formatted = formatNumberWithComma(amount);
  return '${isCredit ? '+' : '-'} ETB $formatted';
}

String _counterparty(Transaction tx) {
  final receiver = tx.receiver?.trim();
  final creditor = tx.creditor?.trim();
  if (receiver != null && receiver.isNotEmpty) return receiver.toUpperCase();
  if (creditor != null && creditor.isNotEmpty) return creditor.toUpperCase();
  return 'UNKNOWN';
}

String _timeLabel(Transaction tx) {
  if (tx.time == null || tx.time!.isEmpty) return '';
  try {
    final dt = DateTime.parse(tx.time!).toLocal();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  } catch (_) {
    return '';
  }
}

// ── Tile ────────────────────────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final String bank;
  final String category;
  final bool isCategorized;
  final String amount;
  final Color amountColor;
  final String name;
  final String timestamp;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _TransactionTile({
    required this.bank,
    required this.category,
    required this.isCategorized,
    required this.amount,
    required this.amountColor,
    required this.name,
    required this.timestamp,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primaryLight.withValues(alpha: 0.08)
            : AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? AppColors.primaryLight
              : AppColors.borderColor(context),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (selected) ...[
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _CategoryChip(
                      label: category,
                      filled: isCategorized,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary(context),
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (timestamp.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      timestamp,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary(context),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool filled;

  const _CategoryChip({required this.label, required this.filled});

  @override
  Widget build(BuildContext context) {
    final background = filled
        ? AppColors.primaryLight
        : AppColors.primaryLight.withValues(alpha: 0.12);
    final foreground = filled ? AppColors.white : AppColors.primaryDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
