import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/failed_parse.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/failed_parse_review_service.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/utils/gradients.dart';

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

  Widget _buildOverview() {
    final groups = _groups;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (groups.isEmpty) {
      return Center(
        child: Text(
          'No confirmed transactions without patterns.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Text(
            'Banks with transaction messages that still need parsing patterns.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: groups.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.08,
            ),
            itemBuilder: (context, index) {
              final group = groups[index];
              return _FailedParseBankCard(
                group: group,
                onTap: () => _openGroup(group),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetail(_FailedParseGroup group) {
    final visibleItems = _visibleItems;
    final hasSearch = _searchController.text.trim().isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search sender or message…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _copy(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.address,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                FailedParse.noMatchingPatternReason,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.body,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                _formatTimestamp(item.timestamp),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tap to copy the full SMS',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _retrying ? null : () => _retrySingle(item),
                    icon: const Icon(
                      Icons.refresh_rounded,
                      size: 16,
                    ),
                    label: const Text('Retry'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
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

  @override
  Widget build(BuildContext context) {
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
      appBar: AppBar(
        leading: selectedGroup == null
            ? null
            : IconButton(
                onPressed: _closeGroup,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(
          selectedGroup == null
              ? 'Failed parsings'
              : '${selectedGroup.label} patterns',
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Send test notification',
            onPressed: _sendTestNotification,
            icon: const Icon(Icons.notification_add_rounded),
          ),
          IconButton(
            tooltip: retryTooltip,
            onPressed: _retrying || visibleItems.isEmpty
                ? null
                : () => _retryBulk(visibleItems),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: clearTooltip,
            onPressed:
                visibleItems.isEmpty ? null : () => _clearItems(visibleItems),
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_retrying) const LinearProgressIndicator(minHeight: 2),
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

class _FailedParseBankCard extends StatelessWidget {
  final _FailedParseGroup group;
  final VoidCallback onTap;

  const _FailedParseBankCard({
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnknown = group.bank == null;
    final theme = Theme.of(context);
    final textColor = isUnknown ? theme.colorScheme.onSurface : Colors.white;
    final secondaryTextColor = isUnknown
        ? theme.colorScheme.onSurfaceVariant
        : Colors.white.withOpacity(0.85);
    final decoration = isUnknown
        ? BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.dividerColor),
          )
        : BoxDecoration(
            gradient:
                group.bank!.colors != null && group.bank!.colors!.isNotEmpty
                    ? GradientUtils.getGradientFromColors(group.bank!.colors)
                    : GradientUtils.getGradient(group.bank!.id),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: decoration,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _BankLogo(bank: group.bank, darkForeground: !isUnknown),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isUnknown
                            ? theme.colorScheme.primary.withOpacity(0.12)
                            : Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${group.items.length}',
                        style: TextStyle(
                          color: isUnknown
                              ? theme.colorScheme.primary
                              : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      group.items.length == 1
                          ? '1 transaction without a pattern'
                          : '${group.items.length} transactions without patterns',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FailedParseSummaryCard extends StatelessWidget {
  final _FailedParseGroup group;

  const _FailedParseSummaryCard({
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final bank = group.bank;
    final isUnknown = bank == null;
    final decoration = isUnknown
        ? BoxDecoration(
            color:
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).dividerColor),
          )
        : BoxDecoration(
            gradient: bank.colors != null && bank.colors!.isNotEmpty
                ? GradientUtils.getGradientFromColors(bank.colors)
                : GradientUtils.getGradient(bank.id),
            borderRadius: BorderRadius.circular(18),
          );
    final textColor =
        isUnknown ? Theme.of(context).colorScheme.onSurface : Colors.white;
    final secondaryTextColor = isUnknown
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Colors.white.withOpacity(0.84);

    return Container(
      decoration: decoration,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _BankLogo(bank: bank, darkForeground: !isUnknown, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  group.items.length == 1
                      ? '1 confirmed transaction without a matching pattern'
                      : '${group.items.length} confirmed transactions without matching patterns',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor,
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

class _BankLogo extends StatelessWidget {
  final Bank? bank;
  final bool darkForeground;
  final double size;

  const _BankLogo({
    required this.bank,
    required this.darkForeground,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size * 0.3);
    final backgroundColor = darkForeground
        ? Colors.white.withOpacity(0.18)
        : Theme.of(context).colorScheme.surface;

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
              Icons.account_balance_rounded,
              size: size * 0.52,
              color: Theme.of(context).colorScheme.primary,
            )
          : Padding(
              padding: EdgeInsets.all(size * 0.18),
              child: Image.asset(
                bank!.image,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return Icon(
                    Icons.account_balance_rounded,
                    size: size * 0.52,
                    color: darkForeground
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary,
                  );
                },
              ),
            ),
    );
  }
}
