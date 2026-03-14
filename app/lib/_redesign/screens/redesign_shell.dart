import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/_redesign/screens/home_page.dart';
import 'package:totals/_redesign/screens/lock_screen.dart';
import 'package:totals/_redesign/screens/money/money_page.dart';
import 'package:totals/_redesign/screens/budget_page.dart';
import 'package:totals/_redesign/screens/settings_page.dart';
import 'package:totals/_redesign/screens/tools_page.dart';
import 'package:totals/_redesign/widgets/redesign_bottom_nav.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/profile.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/bank_detection_startup_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_intent_bus.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/services/widget_launch_intent_service.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/_redesign/widgets/transaction_details_sheet.dart';
import 'package:totals/widgets/add_cash_transaction_sheet.dart';

class RedesignShell extends StatefulWidget {
  const RedesignShell({super.key});

  @override
  State<RedesignShell> createState() => RedesignShellState();
}

class RedesignShellState extends State<RedesignShell>
    with WidgetsBindingObserver {
  static const int _homeIndex = 0;
  static const int _moneyIndex = 1;
  static const int _budgetIndex = 2;
  static const int _settingsIndex = 4;
  final GlobalKey<RedesignMoneyPageState> _moneyPageKey =
      GlobalKey<RedesignMoneyPageState>();
  final GlobalKey<RedesignBudgetPageState> _budgetPageKey =
      GlobalKey<RedesignBudgetPageState>();
  final PageController _pageController =
      PageController(initialPage: _homeIndex);
  DateTime? _lastProfileTabTapAt;
  int _currentIndex = _homeIndex;
  int? _activeProfileId;
  StreamSubscription<WidgetLaunchTarget>? _widgetLaunchIntentSub;
  StreamSubscription<NotificationIntent>? _notificationIntentSub;
  final ProfileRepository _profileRepo = ProfileRepository();
  final SmsService _smsService = SmsService();

  // Auth state
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  bool _hasInitializedSmsPermissions = false;
  bool _hasCheckedNotificationPermissions = false;
  String? _pendingNotificationReference;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(BankDetectionStartupService.runOnAppOpen());
    unawaited(_loadActiveProfileId());

    _widgetLaunchIntentSub = WidgetLaunchIntentService.instance.stream.listen(
      (target) {
        if (target != WidgetLaunchTarget.budget) return;
        _onTabSelected(_budgetIndex);
      },
    );

    _notificationIntentSub = NotificationIntentBus.instance.stream.listen(
      (intent) {
        if (!mounted) return;
        if (intent is CategorizeTransactionIntent) {
          unawaited(_handleNotificationCategorize(intent.reference));
        }
      },
    );

    // Set up callback to refresh UI when a foreground SMS transaction is saved
    _smsService.onTransactionSaved = (tx) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Provider.of<TransactionProvider>(context, listen: false).loadData();
        Provider.of<BudgetProvider>(context, listen: false).loadBudgets();
        final provider =
            Provider.of<TransactionProvider>(context, listen: false);
        final bankLabel = provider.getBankShortName(tx.bankId);
        final sign = tx.type == 'CREDIT'
            ? '+'
            : tx.type == 'DEBIT'
                ? '-'
                : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$bankLabel: $sign ETB ${formatNumberWithComma(tx.amount)}',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      });
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialTarget =
          WidgetLaunchIntentService.instance.consumePendingTarget();
      if (initialTarget != WidgetLaunchTarget.budget) return;
      _onTabSelected(_budgetIndex);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.emitLaunchIntentIfAny();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initSmsPermissions();
      await _checkNotificationPermissions();
      if (mounted) _authenticateIfAvailable();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetLaunchIntentSub?.cancel();
    _notificationIntentSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isAuthenticated) {
      unawaited(
        Provider.of<TransactionProvider>(context, listen: false).loadData(),
      );
    }
  }

  bool _shouldBypassSecurity(PlatformException error) {
    final code = error.code.toLowerCase();
    return code.contains('notavailable') ||
        code.contains('notenrolled') ||
        code.contains('passcodenotset') ||
        code.contains('passcode_not_set') ||
        code.contains('not_enrolled') ||
        code.contains('not_available');
  }

  Future<void> _initSmsPermissions() async {
    if (_hasInitializedSmsPermissions) return;
    _hasInitializedSmsPermissions = true;

    try {
      await _smsService.init();
    } catch (e) {
      if (kDebugMode) {
        print('debug: SMS permission init failed: $e');
      }
    }
  }

  Future<void> _checkNotificationPermissions() async {
    if (kIsWeb) return;
    if (_hasCheckedNotificationPermissions) return;
    _hasCheckedNotificationPermissions = true;

    final permissionsGranted =
        await NotificationService.instance.arePermissionsGranted();
    if (!permissionsGranted && mounted) {
      await NotificationService.instance.requestPermissionsIfNeeded();
    }
  }

  static const String _batteryOptDismissedKey =
      'battery_optimization_prompt_dismissed';

  Future<void> _checkBatteryOptimization() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!mounted) return;

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_batteryOptDismissedKey) == true) return;

      if (!mounted) return;

      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keep transaction alerts active'),
          content: const Text(
            'To make sure you get notified instantly when a transaction '
            'happens, Totals needs to be excluded from battery optimization. '
            'Without this, your phone may stop delivering notifications '
            'in the background.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                prefs.setBool(_batteryOptDismissedKey, true);
                Navigator.pop(ctx, false);
              },
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      if (kDebugMode) {
        print('debug: Battery optimization check failed: $e');
      }
    }
  }

  void _onAuthSuccess() {
    if (!mounted) return;
    setState(() => _isAuthenticated = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final pendingReference = _pendingNotificationReference;
      if (pendingReference != null) {
        _pendingNotificationReference = null;
        await _openTransactionFromNotification(pendingReference);
      }

      if (mounted) {
        unawaited(_checkBatteryOptimization());
      }
    });
  }

  Future<void> _handleNotificationCategorize(String reference) async {
    if (!_isAuthenticated) {
      _pendingNotificationReference = reference;
      await _authenticateIfAvailable();
      return;
    }

    await _openTransactionFromNotification(reference);
  }

  Future<void> _openTransactionFromNotification(String reference) async {
    if (!mounted) return;

    if (_currentIndex != _homeIndex) {
      _onTabSelected(_homeIndex);
    }

    final provider = Provider.of<TransactionProvider>(context, listen: false);
    await provider.loadData();
    if (!mounted) return;

    Transaction? match;
    for (final transaction in provider.allTransactions) {
      if (transaction.reference == reference) {
        match = transaction;
        break;
      }
    }

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction not found'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showTransactionDetailsSheet(
      context: context,
      transaction: match,
      provider: provider,
    );
  }

  Future<void> _authenticateIfAvailable() async {
    if (_isAuthenticated || _isAuthenticating) return;

    if (kIsWeb) {
      _onAuthSuccess();
      return;
    }

    setState(() => _isAuthenticating = true);

    try {
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();

      if (!canCheckBiometrics && !isDeviceSupported) {
        _onAuthSuccess();
        return;
      }

      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Authenticate to access Totals',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (!mounted) return;
      if (didAuthenticate) {
        _onAuthSuccess();
      }
    } on PlatformException catch (e) {
      if (_shouldBypassSecurity(e)) {
        _onAuthSuccess();
      } else {
        if (kDebugMode) print('debug: Auth error: $e');
      }
    } catch (e) {
      if (kDebugMode) print('debug: Auth error: $e');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  void lockApp() {
    setState(() {
      _isAuthenticated = false;
      _currentIndex = _homeIndex;
    });
  }

  void openMoneyAccountsPage() {
    _onTabSelected(_moneyIndex);

    void openAccountsWhenReady([int attempts = 0]) {
      final moneyState = _moneyPageKey.currentState;
      if (moneyState != null && moneyState.mounted) {
        moneyState.openAccountsTab();
        return;
      }

      if (attempts >= 3) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openAccountsWhenReady(attempts + 1);
      });
    }

    openAccountsWhenReady();
  }

  void openSettingsPage() {
    _onTabSelected(_settingsIndex);
  }

  Future<void> _loadActiveProfileId() async {
    final activeProfileId = await _profileRepo.getActiveProfileId();
    if (!mounted) return;
    setState(() {
      _activeProfileId = activeProfileId;
    });
  }

  void _onTabSelected(int index) {
    if (index == _settingsIndex) {
      final now = DateTime.now();
      final isDoubleTap = _lastProfileTabTapAt != null &&
          now.difference(_lastProfileTabTapAt!) <=
              const Duration(milliseconds: 700);
      _lastProfileTabTapAt = now;
      if (isDoubleTap) {
        _lastProfileTabTapAt = null;
        lockApp();
        return;
      }
    } else {
      _lastProfileTabTapAt = null;
    }

    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  String _profileInitials(String name) {
    if (name.isEmpty) return '?';
    final list = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (list.isEmpty) return '?';
    if (list.length >= 2) {
      return (list[0][0] + list[1][0]).toUpperCase();
    }
    return list.first[0].toUpperCase();
  }

  String _cashAccountNumber(TransactionProvider provider) {
    final cashAccounts = provider.accountSummaries
        .where((summary) => summary.bankId == CashConstants.bankId)
        .toList();
    return cashAccounts.isNotEmpty
        ? cashAccounts.first.accountNumber
        : CashConstants.defaultAccountNumber;
  }

  void _showQuickCashSheet() {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    showAddCashTransactionSheet(
      context: context,
      provider: provider,
      accountNumber: _cashAccountNumber(provider),
      initialIsDebit: true,
    );
  }

  Future<void> _onProfileLongPressAt(Rect anchorRect) async {
    final profiles = await _profileRepo.getProfiles();
    final activeProfileId = await _profileRepo.getActiveProfileId();
    if (!mounted || profiles.isEmpty) return;

    final selectedProfileId = await _showProfilePickerMenu(
      anchorRect: anchorRect,
      profiles: profiles,
      activeProfileId: activeProfileId,
    );

    if (selectedProfileId == null || selectedProfileId == activeProfileId) {
      return;
    }

    final selected = profiles.where((p) => p.id == selectedProfileId).toList();
    await _profileRepo.setActiveProfile(selectedProfileId);
    if (!mounted) return;

    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    await txProvider.loadData();
    await budgetProvider.loadBudgets();

    if (!mounted) return;
    setState(() {
      _activeProfileId = selectedProfileId;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selected.isNotEmpty
              ? 'Switched to ${selected.first.name}'
              : 'Profile switched',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<int?> _showProfilePickerMenu({
    required Rect anchorRect,
    required List<Profile> profiles,
    required int? activeProfileId,
  }) async {
    final overlayBox =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return null;

    const rowHeight = 48.0;
    const menuVerticalGap = 8.0;
    final visibleProfiles = profiles.where((p) => p.id != null).toList();
    final anchorTopLeft = overlayBox.globalToLocal(anchorRect.topLeft);
    final anchorBottomRight = overlayBox.globalToLocal(anchorRect.bottomRight);
    final anchorRectInOverlay = Rect.fromPoints(
      anchorTopLeft,
      anchorBottomRight,
    ).inflate(4);
    final estimatedMenuHeight = (visibleProfiles.length * rowHeight) + 16.0;
    final menuTop = (anchorRectInOverlay.top - estimatedMenuHeight - menuVerticalGap)
        .clamp(8.0, overlayBox.size.height - estimatedMenuHeight - 8.0)
        .toDouble();
    final menuAnchorRect = Rect.fromLTWH(
      anchorRectInOverlay.left,
      menuTop,
      anchorRectInOverlay.width,
      0,
    );

    final selected = await showMenu<int>(
      context: context,
      color: AppColors.cardColor(context),
      elevation: 10,
      position: RelativeRect.fromRect(
        menuAnchorRect,
        Offset.zero & overlayBox.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: visibleProfiles.map((profile) {
        final profileId = profile.id!;
        final isActive = profileId == activeProfileId;
        return PopupMenuItem<int>(
          value: profileId,
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? AppColors.primaryLight
                      : AppColors.mutedFill(context),
                ),
                alignment: Alignment.center,
                child: Text(
                  _profileInitials(profile.name),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? Colors.white
                        : AppColors.textSecondary(context),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              if (isActive)
                const Icon(
                  AppIcons.check_rounded,
                  size: 16,
                  color: AppColors.primaryLight,
                ),
            ],
          ),
        );
      }).toList(growable: false),
    );

    return selected;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return RedesignLockScreen(onUnlock: _authenticateIfAvailable);
    }

    return SafeArea(
      bottom: false,
      child: WillPopScope(
        onWillPop: () async {
          if (_currentIndex == _budgetIndex) {
            final handled = _budgetPageKey.currentState?.handleSystemBack() ?? false;
            if (handled) return false;
          }
          return true;
        },
        child: Scaffold(
          extendBody: true,
          body: PageView(
            controller: _pageController,
            physics: const PageScrollPhysics(),
            onPageChanged: (index) {
              if (_currentIndex == index || !mounted) return;
              setState(() {
                _currentIndex = index;
              });
            },
            children: [
              const RedesignHomePage(),
              RedesignMoneyPage(key: _moneyPageKey),
              RedesignBudgetPage(key: _budgetPageKey),
              const RedesignToolsPage(),
              RedesignSettingsPage(
                key: ValueKey('settings-${_activeProfileId ?? 'none'}'),
              ),
            ],
          ),
          bottomNavigationBar: RedesignBottomNav(
            currentIndex: _currentIndex,
            onTap: _onTabSelected,
            onMoneyLongPress: _showQuickCashSheet,
            onProfileLongPressAt: _onProfileLongPressAt,
          ),
        ),
      ),
    );
  }
}
