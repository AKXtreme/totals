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
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/bank_detection_startup_service.dart';
import 'package:totals/services/widget_launch_intent_service.dart';
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
  final PageController _pageController =
      PageController(initialPage: _homeIndex);
  final GlobalKey<RedesignMoneyPageState> _moneyPageKey =
      GlobalKey<RedesignMoneyPageState>();
  final GlobalKey<RedesignBudgetPageState> _budgetPageKey =
      GlobalKey<RedesignBudgetPageState>();
  DateTime? _lastProfileTabTapAt;
  int _currentIndex = _homeIndex;
  int? _activeProfileId;
  StreamSubscription<WidgetLaunchTarget>? _widgetLaunchIntentSub;
  final ProfileRepository _profileRepo = ProfileRepository();

  // Auth state
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialTarget =
          WidgetLaunchIntentService.instance.consumePendingTarget();
      if (initialTarget != WidgetLaunchTarget.budget) return;
      _onTabSelected(_budgetIndex);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _authenticateIfAvailable();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetLaunchIntentSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't auto-lock on pause — only lock on startup or via manual lockApp().
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

  Future<void> _authenticateIfAvailable() async {
    if (_isAuthenticated || _isAuthenticating) return;

    if (kIsWeb) {
      setState(() => _isAuthenticated = true);
      return;
    }

    setState(() => _isAuthenticating = true);

    try {
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();

      if (!canCheckBiometrics && !isDeviceSupported) {
        if (mounted) setState(() => _isAuthenticated = true);
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
        setState(() => _isAuthenticated = true);
      }
    } on PlatformException catch (e) {
      if (_shouldBypassSecurity(e)) {
        if (mounted) setState(() => _isAuthenticated = true);
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
    _pageController.jumpToPage(index);
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

  Future<void> _onProfileLongPressAt(Offset anchor) async {
    final profiles = await _profileRepo.getProfiles();
    final activeProfileId = await _profileRepo.getActiveProfileId();
    if (!mounted || profiles.isEmpty) return;

    final selectedProfileId = await _showProfilePickerMenu(
      anchor: anchor,
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
    required Offset anchor,
    required List<Profile> profiles,
    required int? activeProfileId,
  }) async {
    final overlayBox =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return null;

    const menuWidth = 220.0;
    const rowHeight = 48.0;
    final visibleProfiles = profiles.where((p) => p.id != null).toList();
    final menuHeight = (visibleProfiles.length * rowHeight) + 16;

    final left = (anchor.dx - menuWidth + 24)
        .clamp(8.0, overlayBox.size.width - menuWidth - 8.0)
        .toDouble();
    final top = (anchor.dy - menuHeight - 10)
        .clamp(8.0, overlayBox.size.height - menuHeight - 8.0)
        .toDouble();

    final selected = await showMenu<int>(
      context: context,
      color: AppColors.cardColor(context),
      elevation: 10,
      position: RelativeRect.fromLTRB(
        left,
        top,
        overlayBox.size.width - left - menuWidth,
        overlayBox.size.height - top - menuHeight,
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

    return WillPopScope(
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
          physics: const NeverScrollableScrollPhysics(),
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
    );
  }
}
