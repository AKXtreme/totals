import 'package:flutter/material.dart';
import 'package:totals/components/custom_inputfield.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/models/user_account.dart';
import 'package:totals/services/bank_config_service.dart';

class AddUserAccountForm extends StatefulWidget {
  final void Function() onAccountAdded;

  const AddUserAccountForm({
    required this.onAccountAdded,
    super.key,
  });

  @override
  State<AddUserAccountForm> createState() => _AddUserAccountFormState();
}

class _AddUserAccountFormState extends State<AddUserAccountForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _accountNumber = TextEditingController();
  final TextEditingController _accountHolderName = TextEditingController();
  final BankConfigService _bankConfigService = BankConfigService();
  int? selected_bank;
  bool isFormValid = false;
  List<Bank> _banks = [];
  bool _isLoadingBanks = true;

  @override
  void initState() {
    super.initState();
    _accountNumber.addListener(_validateForm);
    _accountHolderName.addListener(_validateForm);
    _loadBanks();
  }

  @override
  void dispose() {
    _accountNumber.dispose();
    _accountHolderName.dispose();
    super.dispose();
  }

  String _normalizeBankToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _bankDedupeKey(Bank bank) {
    final short = _normalizeBankToken(bank.shortName);
    final name = _normalizeBankToken(bank.name);
    if (short.contains('mpesa') || name.contains('mpesa')) {
      return 'mpesa';
    }
    if (short.isNotEmpty) return short;
    if (name.isNotEmpty) return name;
    return bank.image.toLowerCase();
  }

  List<Bank> _dedupeBanks(List<Bank> banks) {
    final dedupedByKey = <String, Bank>{};
    for (final bank in banks) {
      final key = _bankDedupeKey(bank);
      final existing = dedupedByKey[key];
      if (existing == null) {
        dedupedByKey[key] = bank;
        continue;
      }

      final shouldReplace = key == 'mpesa' && bank.id == 8 && existing.id != 8;
      if (shouldReplace) dedupedByKey[key] = bank;
    }
    return dedupedByKey.values.toList();
  }

  Future<void> _loadBanks() async {
    try {
      final configuredBanks = await _bankConfigService.getBanks();
      final mergedById = <int, Bank>{
        for (final bank in configuredBanks) bank.id: bank,
      };
      for (final legacyBank in AllBanksFromAssets.getAllBanks()) {
        mergedById.putIfAbsent(legacyBank.id, () => legacyBank);
      }
      final banks = _dedupeBanks(mergedById.values.toList());
      if (mounted) {
        setState(() {
          _banks = banks;
          _isLoadingBanks = false;
          if (banks.isEmpty) {
            selected_bank = null;
          } else if (selected_bank == null ||
              !banks.any((bank) => bank.id == selected_bank)) {
            selected_bank = banks.first.id;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _banks = _dedupeBanks(AllBanksFromAssets.getAllBanks());
          _isLoadingBanks = false;
          if (_banks.isEmpty) {
            selected_bank = null;
          } else {
            selected_bank = _banks.first.id;
          }
        });
      }
    }
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate() && selected_bank != null) {
      try {
        final accountRepo = UserAccountRepository();
        final accountExists = await accountRepo.userAccountExists(
          _accountNumber.text.trim(),
          selected_bank!,
        );

        if (accountExists) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This account already exists'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        final account = UserAccount(
          accountNumber: _accountNumber.text.trim(),
          bankId: selected_bank!,
          accountHolderName: _accountHolderName.text.trim(),
          createdAt: DateTime.now().toIso8601String(),
        );

        await accountRepo.saveUserAccount(account);

        if (mounted) {
          Navigator.of(context).pop();
          widget.onAccountAdded();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account added successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding account: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _validateForm() {
    setState(() {
      isFormValid =
          _accountHolderName.text.isNotEmpty && _accountNumber.text.isNotEmpty;
    });
  }

  void _showBankSelectionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Select Bank",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: _isLoadingBanks
                    ? const Center(child: CircularProgressIndicator())
                    : _banks.isEmpty
                        ? Center(
                            child: Text(
                              "No banks available",
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.8,
                            ),
                            itemCount: _banks.length,
                            itemBuilder: (context, index) {
                              final bank = _banks[index];
                              final isSelected = selected_bank == bank.id;
                              return GestureDetector(
                                onTap: () {
                                  if (mounted) {
                                    setState(() {
                                      selected_bank = bank.id;
                                    });
                                    Navigator.pop(context);
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withOpacity(0.1)
                                        : Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .outline
                                              .withOpacity(0.2),
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                        ),
                                        child: ClipOval(
                                          child: Image.asset(
                                            bank.image,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              return Container(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceVariant,
                                                child: Icon(
                                                  Icons.account_balance,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        bank.shortName,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoadingBanks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_banks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              "No banks available",
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (selected_bank == null || _banks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final selectedBankData = _banks.firstWhere(
      (element) => element.id == selected_bank,
      orElse: () => _banks.first,
    );

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Add Quick Access Account",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        colorScheme.surfaceVariant.withOpacity(0.3),
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Bank Selector
            Text(
              "Bank",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showBankSelectionModal,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.1),
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          selectedBankData.image,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: colorScheme.surfaceVariant,
                              child: Icon(
                                Icons.account_balance,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        selectedBankData.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Account Number
            CustomTextField(
              controller: _accountNumber,
              labelText: "Account Number",
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Enter account number";
                }
                if (value.trim().isEmpty) {
                  return "Enter account number";
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // Account Holder Name
            CustomTextField(
              controller: _accountHolderName,
              labelText: "Account Holder Name",
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Enter account holder name";
                }
                if (value.trim().isEmpty) {
                  return "Enter account holder name";
                }
                return null;
              },
            ),

            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: isFormValid ? _submitForm : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: colorScheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor: colorScheme.surfaceVariant,
                      disabledForegroundColor: colorScheme.onSurfaceVariant,
                    ),
                    child: const Text(
                      "Add Account",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
