import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/insights_provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/screens/home_page.dart';
import 'package:totals/database/migration_helper.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:workmanager/workmanager.dart';
import 'package:totals/background/daily_spending_worker.dart';
import 'package:totals/services/notification_scheduler.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/services/widget_launch_intent_service.dart';
import 'package:totals/services/widget_refresh_scheduler.dart';
import 'package:totals/_redesign/screens/onboarding_page.dart';
import 'package:totals/_redesign/screens/redesign_shell.dart';
import 'package:totals/_redesign/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

SnackBarThemeData _globalSnackBarTheme() {
  return SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xFF334155),
    contentTextStyle: const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    elevation: 0,
  );
}

Widget _buildUiScaledApp({
  required BuildContext context,
  required Widget child,
  required double scale,
}) {
  if ((scale - 1.0).abs() < 0.001) return child;

  // Use sizeOf instead of MediaQuery.of to only depend on size changes,
  // not every MediaQuery field (avoids unnecessary rebuilds during theme changes
  // that can crash overlay elements like bottom sheets).
  final size = MediaQuery.sizeOf(context);
  final scaledWidth = size.width / scale;
  final scaledHeight = size.height / scale;

  return ClipRect(
    child: OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: scaledWidth,
      maxWidth: scaledWidth,
      minHeight: scaledHeight,
      maxHeight: scaledHeight,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: scaledWidth,
          height: scaledHeight,
          child: child,
        ),
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database and migrate if needed
  // await MigrationHelper.migrateIfNeeded();

  // Initialize default profile if none exists
  final profileRepo = ProfileRepository();
  await profileRepo.initializeDefaultProfile();

  // Initialize home widget
  await WidgetService.initialize();
  await WidgetLaunchIntentService.instance.initialize();

  // Read redesign flag from SharedPreferences (persists across restarts)
  final prefs = await SharedPreferences.getInstance();
  final useRedesign = prefs.getBool('use_redesign') ?? true;
  // final hasCompletedOnboarding =
  //     prefs.getBool('has_completed_onboarding') ?? false;
  final hasCompletedOnboarding = true;
  if (!kIsWeb) {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        // isInDebugMode: kDebugMode,
        isInDebugMode: false,
      );
      await NotificationScheduler.syncSpendingSummarySchedule();
      await WidgetRefreshScheduler.syncWidgetRefreshSchedule();
    } catch (e) {
      // Ignore if not supported on the current platform.
      if (kDebugMode) {
        print('debug: Workmanager init failed: $e');
      }
    }
  }

  runApp(MyApp(
    useRedesign: useRedesign,
    showOnboarding: useRedesign && !hasCompletedOnboarding,
  ));
}

class MyApp extends StatelessWidget {
  final bool useRedesign;
  final bool showOnboarding;

  const MyApp({
    super.key,
    required this.useRedesign,
    this.showOnboarding = false,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => BudgetProvider()),

        // we need insights provider to use the existing transacton provider instead of using
        // a new transaction provider instance.
        ChangeNotifierProxyProvider<TransactionProvider, InsightsProvider>(
          create: (context) => InsightsProvider(
              txProvider:
                  Provider.of<TransactionProvider>(context, listen: false)),
          update: (context, txProvider, previous) =>
              previous!..txProvider = txProvider,
        ),
        ChangeNotifierProvider.value(value: AccountSyncStatusService.instance),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Totals',
            theme: useRedesign
                ? RedesignTheme.light()
                : ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.blue,
                      brightness: Brightness.light,
                    ),
                    snackBarTheme: _globalSnackBarTheme(),
                    useMaterial3: true,
                  ),
            darkTheme: useRedesign
                ? RedesignTheme.dark()
                : ThemeData(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFF3F3F46),
                      secondary: Color(0xFF52525B),
                      surface: Color(0xFF1E2230),
                      background: Color(0xFF161A26),
                      surfaceVariant: Color(0xFF161A26),
                      onPrimary: Colors.white,
                      onSecondary: Colors.white,
                      onSurface: Colors.white,
                      onBackground: Colors.white,
                      onSurfaceVariant: Colors.white70,
                      brightness: Brightness.dark,
                    ),
                    scaffoldBackgroundColor: const Color(0xFF161A26),
                    cardColor: const Color(0xFF1E2230),
                    dividerColor: const Color(0xFF34384A),
                    snackBarTheme: _globalSnackBarTheme(),
                    useMaterial3: true,
                  ),
            themeMode: themeProvider.themeMode,
            builder: (context, child) {
              if (child == null) return const SizedBox.shrink();
              return _buildUiScaledApp(
                context: context,
                child: child,
                scale: themeProvider.uiScale,
              );
            },
            home: showOnboarding
                ? const OnboardingPage()
                : useRedesign
                    ? const RedesignShell()
                    : const HomePage(),
          );
        },
      ),
    );
  }
}
