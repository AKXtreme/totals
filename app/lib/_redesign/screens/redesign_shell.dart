import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:totals/_redesign/screens/home_page.dart';
import 'package:totals/_redesign/screens/lock_screen.dart';
import 'package:totals/_redesign/screens/money/money_page.dart';
import 'package:totals/_redesign/screens/budget_page.dart';
import 'package:totals/_redesign/screens/settings_page.dart';
import 'package:totals/_redesign/screens/tools_page.dart';
import 'package:totals/_redesign/widgets/redesign_bottom_nav.dart';
import 'package:totals/services/bank_detection_startup_service.dart';
import 'package:totals/services/widget_launch_intent_service.dart';

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
  final PageController _pageController =
      PageController(initialPage: _homeIndex);
  final GlobalKey<RedesignMoneyPageState> _moneyPageKey =
      GlobalKey<RedesignMoneyPageState>();
  int _currentIndex = _homeIndex;
  StreamSubscription<WidgetLaunchTarget>? _widgetLaunchIntentSub;

  // Auth state
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(BankDetectionStartupService.runOnAppOpen());

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

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return RedesignLockScreen(onUnlock: _authenticateIfAvailable);
    }

    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const RedesignHomePage(),
          RedesignMoneyPage(key: _moneyPageKey),
          const RedesignBudgetPage(),
          const RedesignToolsPage(),
          const RedesignSettingsPage(),
        ],
      ),
      bottomNavigationBar: RedesignBottomNav(
        currentIndex: _currentIndex,
        onTap: _onTabSelected,
      ),
    );
  }
}
