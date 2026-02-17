import 'package:flutter/material.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/widgets/accounts_summary.dart';
import 'package:totals/widgets/total_balance_card.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/widgets/add_cash_transaction_sheet.dart';
import 'package:provider/provider.dart';
import 'package:totals/utils/text_utils.dart';

class BankDetail extends StatefulWidget {
  final int bankId;
  final List<AccountSummary> accountSummaries;

  const BankDetail({
    Key? key,
    required this.bankId,
    required this.accountSummaries,
  }) : super(key: key);

  @override
  State<BankDetail> createState() => _BankDetailState();
}

class _BankDetailState extends State<BankDetail> {
  // isBankDetailExpanded is no longer needed as TotalBalanceCard handles its own expansion.
  bool showTotalBalance = false;
  List<String> visibleTotalBalancesForSubCards = [];
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank> _banks = [];
  bool _isAdjustingCash = false;

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final banks = await _bankConfigService.getBanks();
      if (mounted) {
        setState(() {
          _banks = banks;
        });
      }
    } catch (e) {
      print("debug: Error loading banks: $e");
    }
  }

  Bank? _getBankInfo() {
    if (widget.bankId == CashConstants.bankId) {
      return Bank(
        id: CashConstants.bankId,
        name: CashConstants.bankName,
        shortName: CashConstants.bankShortName,
        codes: const [],
        image: CashConstants.bankImage,
        colors: CashConstants.bankColors,
      );
    }
    try {
      return _banks.firstWhere((element) => element.id == widget.bankId);
    } catch (e) {
      return null;
    }
  }

  String _formatEtb(double value) {
    return formatNumberWithComma(value).replaceFirst(RegExp(r'\.00$'), '');
  }

  double? _parseAmount(String raw) {
    final cleaned = raw.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _applyCashWalletTarget({
    required TransactionProvider provider,
    required String accountNumber,
    required double targetBalance,
    required String reason,
  }) async {
    if (_isAdjustingCash) return;

    setState(() {
      _isAdjustingCash = true;
    });

    try {
      final delta = await provider.setCashWalletBalance(
        targetBalance: targetBalance,
        accountNumber: accountNumber,
        reason: reason,
      );

      if (!mounted) return;

      if (delta.abs() < 0.0001) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cash wallet is already at that amount'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final direction = delta > 0 ? 'increased' : 'decreased';
        final amount = _formatEtb(delta.abs());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cash wallet $direction by ETB $amount'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update cash wallet: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAdjustingCash = false;
        });
      }
    }
  }

  Future<void> _confirmClearCashWallet({
    required TransactionProvider provider,
    required String accountNumber,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear cash wallet?'),
        content: const Text(
          'This will set your cash wallet balance to ETB 0 by adding an adjustment transaction.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _applyCashWalletTarget(
      provider: provider,
      accountNumber: accountNumber,
      targetBalance: 0,
      reason: 'Cash wallet cleared',
    );
  }

  Future<void> _showSetCashWalletDialog({
    required TransactionProvider provider,
    required String accountNumber,
    required double currentBalance,
  }) async {
    final controller = TextEditingController(text: _formatEtb(currentBalance));
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Set cash wallet amount'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Target balance',
                prefixText: 'ETB ',
                hintText: '0.00',
              ),
              validator: (value) {
                final parsed = _parseAmount(value ?? '');
                if (parsed == null) return 'Enter a valid amount';
                if (parsed < 0) return 'Amount cannot be negative';
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final parsed = _parseAmount(controller.text);
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('Set amount'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null) return;

    await _applyCashWalletTarget(
      provider: provider,
      accountNumber: accountNumber,
      targetBalance: result,
      reason: 'Cash wallet set to ETB ${_formatEtb(result)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final scheme = Theme.of(context).colorScheme;
    // Calculate totals for this bank
    double totalBalance = 0;
    double totalCredit = 0;
    double totalDebit = 0;

    for (var account in widget.accountSummaries) {
      totalBalance += account.balance;
      totalCredit += account.totalCredit;
      totalDebit += account.totalDebit;
    }

    final bankSummary = AllSummary(
      totalCredit: totalCredit,
      totalDebit: totalDebit,
      banks: 1,
      totalBalance: totalBalance,
      accounts: widget.accountSummaries.length,
    );

    final bankInfo = _getBankInfo();
    final bankName = bankInfo?.name ?? "Unknown Bank";
    final bankImage = bankInfo?.image ?? "assets/images/cbe.png";

    final isCashBank = widget.bankId == CashConstants.bankId;
    final cashAccountNumber = widget.accountSummaries.isNotEmpty
        ? widget.accountSummaries.first.accountNumber
        : CashConstants.defaultAccountNumber;

    return Column(
      children: [
        const SizedBox(height: 12),
        // Replaced custom Card with TotalBalanceCard (Blue Gradient ID 99)
        TotalBalanceCard(
          summary: bankSummary,
          showBalance: showTotalBalance,
          title: bankName.toUpperCase(),
          logoAsset: bankImage,
          gradientId: widget.bankId,
          colors: bankInfo?.colors, // Use colors from bank data if available
          subtitle: "${widget.accountSummaries.length} Accounts",
          onToggleBalance: () {
            setState(() {
              showTotalBalance = !showTotalBalance;
              // Migrate logic: toggling main balance also toggles all sub-cards
              visibleTotalBalancesForSubCards = visibleTotalBalancesForSubCards
                      .isEmpty
                  ? widget.accountSummaries.map((e) => e.accountNumber).toList()
                  : [];
            });
          },
        ),
        const SizedBox(height: 12),
        if (isCashBank) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick add',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => showAddCashTransactionSheet(
                          context: context,
                          provider: provider,
                          accountNumber: cashAccountNumber,
                          initialIsDebit: true,
                        ),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Expense'),
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => showAddCashTransactionSheet(
                          context: context,
                          provider: provider,
                          accountNumber: cashAccountNumber,
                          initialIsDebit: false,
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Income'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isAdjustingCash
                            ? null
                            : () => _confirmClearCashWallet(
                                  provider: provider,
                                  accountNumber: cashAccountNumber,
                                ),
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Clear wallet'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(color: scheme.error.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isAdjustingCash
                            ? null
                            : () => _showSetCashWalletDialog(
                                  provider: provider,
                                  accountNumber: cashAccountNumber,
                                  currentBalance: totalBalance,
                                ),
                        icon: const Icon(Icons.tune),
                        label: const Text('Set amount'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: AccountsSummaryList(
              accountSummaries: widget.accountSummaries,
              visibleTotalBalancesForSubCards: visibleTotalBalancesForSubCards),
        ),
      ],
    );
  }
}
