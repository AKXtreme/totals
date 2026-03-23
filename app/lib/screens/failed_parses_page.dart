import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/failed_parse.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/failed_parse_review_service.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/sms_service.dart';

class FailedParsesPage extends StatefulWidget {
  const FailedParsesPage({super.key});

  @override
  State<FailedParsesPage> createState() => _FailedParsesPageState();
}

class _FailedParsesPageState extends State<FailedParsesPage> {
  final FailedParseRepository _repo = FailedParseRepository();
  final TextEditingController _searchController = TextEditingController();
  final BankConfigService _bankConfigService = BankConfigService();
  final Map<String, Bank?> _bankByAddress = {};

  bool _loading = true;
  bool _retrying = false;
  List<FailedParse> _items = const [];
  List<Bank> _banks = const [];
  String? _selectedGroupKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repo.getAll(),
        _bankConfigService.getBanks(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<FailedParse>;
        _banks = results[1] as List<Bank>;
        _loading = false;
        _bankByAddress.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load failed parsings: $e')),
      );
    }
  }

  List<FailedParse> get _missingPatternItems {
    return _items
        .where((item) => item.isMissingPattern)
        .toList(growable: false);
  }

  _FailedParseGroup? get _selectedGroup {
    final key = _selectedGroupKey;
    if (key == null) return null;
    for (final group in _groups) {
      if (group.key == key) return group;
    }
    return null;
  }

  List<FailedParse> get _visibleItems {
    final selectedGroup = _selectedGroup;
    if (selectedGroup == null) {
      return _missingPatternItems;
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return selectedGroup.items;

    return selectedGroup.items.where((item) {
      return item.address.toLowerCase().contains(query) ||
          item.body.toLowerCase().contains(query) ||
          item.timestamp.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  List<_FailedParseGroup> get _groups {
    final grouped = <String, List<FailedParse>>{};
    final bankByKey = <String, Bank?>{};

    for (final item in _missingPatternItems) {
      final bank = _resolveBank(item);
      final key = bank == null ? 'unknown' : 'bank:${bank.id}';
      grouped.putIfAbsent(key, () => <FailedParse>[]).add(item);
      bankByKey[key] = bank;
    }

    final groups = grouped.entries.map((entry) {
      final bank = bankByKey[entry.key];
      return _FailedParseGroup(
        key: entry.key,
        bank: bank,
        items: List<FailedParse>.unmodifiable(entry.value),
      );
    }).toList(growable: false);

    groups.sort((a, b) {
      final byCount = b.items.length.compareTo(a.items.length);
      if (byCount != 0) return byCount;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return groups;
  }

  Bank? _resolveBank(FailedParse item) {
    if (_banks.isEmpty) return null;
    final cacheKey = item.address;
    return _bankByAddress.putIfAbsent(cacheKey, () {
      final normalizedAddress = _normalizeToken(item.address);
      for (final bank in _banks) {
        for (final code in bank.codes) {
          if (normalizedAddress.contains(_normalizeToken(code))) {
            return bank;
          }
        }
      }
      return null;
    });
  }

  String _normalizeToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<void> _clearItems(List<FailedParse> items) async {
    final ids = items.map((item) => item.id).whereType<int>().toList();
    if (ids.isEmpty) return;

    await _repo.deleteByIds(ids);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ids.length == 1
              ? 'Cleared 1 transaction without a pattern'
              : 'Cleared ${ids.length} transactions without patterns',
        ),
      ),
    );
  }

  Future<void> _copy(FailedParse item) async {
    final text = [
      'Sender: ${item.address}',
      'Reason: ${item.reason}',
      'Time: ${item.timestamp}',
      '',
      item.body,
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  String _formatTimestamp(String timestamp) {
    final dateTime = DateTime.tryParse(timestamp);
    if (dateTime == null) return timestamp;
    return DateFormat('h:mm a, MMM dd yyyy').format(dateTime).toLowerCase();
  }

  Future<void> _sendTestNotification() async {
    final bank = await _pickTestBank();
    if (!mounted) return;
    if (bank == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No bank available for a test notification')),
      );
      return;
    }

    final timestamp = DateTime.now();
    final senderAddress =
        bank.codes.isNotEmpty ? bank.codes.first : bank.shortName;
    final sampleMessage =
        'TEST ONLY: Account ****1234 was debited ETB 245.50 at Demo Coffee. '
        'Available balance ETB 4,820.10. Ref TEST-${timestamp.millisecondsSinceEpoch}.';

    await NotificationService.instance.requestPermissionsIfNeeded();
    final reviewId = await FailedParseReviewService.instance.storeCandidate(
      bank: bank,
      address: senderAddress,
      body: sampleMessage,
      messageDate: timestamp,
    );
    final shown =
        await NotificationService.instance.showFailedParseReviewNotification(
      reviewId: reviewId,
      bankName: bank.shortName,
      messageBody: sampleMessage,
    );

    if (!mounted) return;
    if (!shown) {
      await FailedParseReviewService.instance.discardCandidate(reviewId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send test notification')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test notification sent')),
    );
  }

  Future<Bank?> _pickTestBank() async {
    if (_banks.isEmpty) {
      try {
        final banks = await _bankConfigService.getBanks();
        if (mounted) {
          setState(() {
            _banks = banks;
            _bankByAddress.clear();
          });
        }
      } catch (_) {
        // Fall through to the current state below.
      }
    }

    final accounts = await AccountRepository().getAccounts();
    final registeredBankIds = accounts.map((account) => account.bank).toSet();

    for (final bank in _banks) {
      if (registeredBankIds.contains(bank.id)) return bank;
    }
    if (_banks.isNotEmpty) return _banks.first;
    return null;
  }

  Future<void> _retrySingle(FailedParse item) async {
    if (_retrying) return;
    setState(() => _retrying = true);
    ParseResult? result;
    Object? error;

    try {
      result = await SmsService.retryFailedParse(
        item.body,
        item.address,
        messageDate: DateTime.tryParse(item.timestamp),
      );
      if (result.status == ParseStatus.success && item.id != null) {
        await _repo.deleteById(item.id!);
      }
      await _load();
    } catch (e) {
      error = e;
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }

    if (!mounted) return;
    String message;
    if (error != null) {
      message = 'Retry failed: $error';
    } else if (result?.status == ParseStatus.success) {
      message = 'Retry succeeded';
    } else if (result?.status == ParseStatus.duplicate) {
      message = 'Duplicate still exists';
    } else {
      message = 'Retry failed: ${result?.reason ?? 'Unknown error'}';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _retryBulk(List<FailedParse> items) async {
    if (_retrying || items.isEmpty) return;
    setState(() => _retrying = true);

    int success = 0;
    int duplicate = 0;
    int failed = 0;
    int errors = 0;
    final idsToDelete = <int>[];
    Object? batchError;

    try {
      for (final item in items) {
        try {
          final result = await SmsService.retryFailedParse(
            item.body,
            item.address,
            messageDate: DateTime.tryParse(item.timestamp),
          );
          if (result.status == ParseStatus.success) {
            success++;
            if (item.id != null) {
              idsToDelete.add(item.id!);
            }
          } else if (result.status == ParseStatus.duplicate) {
            duplicate++;
          } else {
            failed++;
          }
        } catch (_) {
          errors++;
        }
      }

      if (idsToDelete.isNotEmpty) {
        await _repo.deleteByIds(idsToDelete);
      }
      await _load();
    } catch (e) {
      batchError = e;
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }

    if (!mounted) return;
    if (batchError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retry failed: $batchError')),
      );
      return;
    }

    final total = items.length;
    final summary = [
      'Retried $total',
      if (success > 0) 'success: $success',
      if (duplicate > 0) 'duplicates: $duplicate',
      if (failed > 0) 'failed: $failed',
      if (errors > 0) 'errors: $errors',
    ].join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

  void _openGroup(_FailedParseGroup group) {
    _searchController.clear();
    setState(() => _selectedGroupKey = group.key);
  }

  void _closeGroup() {
    _searchController.clear();
    setState(() => _selectedGroupKey = null);
  }

  // ── Overview ──────────────────────────────────────────────────────────────

  Widget _buildOverview() {
    final theme = Theme.of(context);
    final groups = _groups;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryLight,
          strokeWidth: 2.5,
        ),
      );
    }

    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.check_circle_rounded,
              size: 48,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(height: 12),
            Text(
              'No failed parsings',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'All transaction messages are being parsed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryLight,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final group = groups[index];
          return _FailedParseBankCard(
            group: group,
            onTap: () => _openGroup(group),
          );
        },
      ),
    );
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  Widget _buildDetail(_FailedParseGroup group) {
    final visibleItems = _visibleItems;
    final hasSearch = _searchController.text.trim().isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: AppColors.textPrimary(context)),
            decoration: InputDecoration(
              hintText: 'Search sender or message\u2026',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
              prefixIcon: Icon(
                AppIcons.filter_list,
                color: AppColors.textTertiary(context),
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: Icon(
                        AppIcons.close_rounded,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
              filled: true,
              fillColor: AppColors.cardColor(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderColor(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderColor(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.primaryLight,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _FailedParseSummaryCard(group: group),
        ),
        Expanded(
          child: visibleItems.isEmpty
              ? Center(
                  child: Text(
                    hasSearch
                        ? 'No transactions match your search.'
                        : 'No transactions without patterns for this bank.',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primaryLight,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                    itemCount: visibleItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _buildParseCard(visibleItems[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildParseCard(FailedParse item) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _copy(item),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.address,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    AppIcons.upload_rounded,
                    size: 16,
                    color: AppColors.textTertiary(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  FailedParse.noMatchingPatternReason,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.amber,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.body,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    AppIcons.schedule_rounded,
                    size: 12,
                    color: AppColors.textTertiary(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatTimestamp(item.timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ),
                  Material(
                    color: AppColors.primaryLight.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _retrying ? null : () => _retrySingle(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.refresh,
                              size: 13,
                              color: AppColors.primaryLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ],
                        ),
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

  // ── Scaffold ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedGroup = _selectedGroup;
    final visibleItems = _visibleItems;
    final retryTooltip = selectedGroup == null
        ? 'Retry all banks'
        : _searchController.text.trim().isNotEmpty
            ? 'Retry filtered'
            : 'Retry ${selectedGroup.label}';
    final clearTooltip = selectedGroup == null
        ? 'Clear all banks'
        : _searchController.text.trim().isNotEmpty
            ? 'Clear filtered'
            : 'Clear ${selectedGroup.label}';

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        leading: IconButton(
          onPressed: selectedGroup == null
              ? () => Navigator.pop(context)
              : _closeGroup,
          icon: const Icon(AppIcons.arrow_back_rounded),
        ),
        title: Text(
          selectedGroup == null
              ? 'Failed Parsings'
              : '${selectedGroup.label} Patterns',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary(context),
          ),
        ),
        backgroundColor: AppColors.background(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: retryTooltip,
            onPressed: _retrying || visibleItems.isEmpty
                ? null
                : () => _retryBulk(visibleItems),
            icon: Icon(
              AppIcons.refresh,
              color: _retrying || visibleItems.isEmpty
                  ? AppColors.textTertiary(context)
                  : AppColors.textSecondary(context),
            ),
          ),
          IconButton(
            tooltip: clearTooltip,
            onPressed:
                visibleItems.isEmpty ? null : () => _clearItems(visibleItems),
            icon: Icon(
              AppIcons.delete_outline_rounded,
              color: visibleItems.isEmpty
                  ? AppColors.textTertiary(context)
                  : AppColors.textSecondary(context),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_retrying)
            LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primaryLight,
              backgroundColor: AppColors.primaryLight.withValues(alpha: 0.15),
            ),
          Expanded(
            child: selectedGroup == null
                ? _buildOverview()
                : _buildDetail(selectedGroup),
          ),
        ],
      ),
    );
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class _FailedParseGroup {
  final String key;
  final Bank? bank;
  final List<FailedParse> items;

  const _FailedParseGroup({
    required this.key,
    required this.bank,
    required this.items,
  });

  String get label => bank?.shortName ?? 'Unknown bank';
}

// ── Bank Card (Overview) ──────────────────────────────────────────────────────

class _FailedParseBankCard extends StatelessWidget {
  final _FailedParseGroup group;
  final VoidCallback onTap;

  const _FailedParseBankCard({
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              _BankLogo(bank: group.bank, darkForeground: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      group.items.length == 1
                          ? '1 unmatched transaction'
                          : '${group.items.length} unmatched transactions',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.items.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                AppIcons.chevron_right_rounded,
                color: AppColors.textTertiary(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary Card (Detail header) ─────────────────────────────────────────────

class _FailedParseSummaryCard extends StatelessWidget {
  final _FailedParseGroup group;

  const _FailedParseSummaryCard({
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final bank = group.bank;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _BankLogo(bank: bank, darkForeground: false, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  group.items.length == 1
                      ? '1 transaction without a matching pattern'
                      : '${group.items.length} transactions without matching patterns',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary(context),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bank Logo ─────────────────────────────────────────────────────────────────

class _BankLogo extends StatelessWidget {
  final Bank? bank;
  final bool darkForeground;
  final double size;

  const _BankLogo({
    required this.bank,
    required this.darkForeground,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(10);
    final backgroundColor = darkForeground
        ? Colors.white.withValues(alpha: 0.18)
        : AppColors.mutedFill(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: bank == null
          ? Icon(
              AppIcons.account_balance_rounded,
              size: size * 0.52,
              color: AppColors.primaryLight,
            )
          : Padding(
              padding: EdgeInsets.all(size * 0.18),
              child: Image.asset(
                bank!.image,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return Icon(
                    AppIcons.account_balance_rounded,
                    size: size * 0.52,
                    color: darkForeground
                        ? Colors.white
                        : AppColors.primaryLight,
                  );
                },
              ),
            ),
    );
  }
}
