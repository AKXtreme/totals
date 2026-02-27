import 'dart:async';

import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/home_page.dart';
import 'package:totals/_redesign/screens/money/money_page.dart';
import 'package:totals/_redesign/screens/placeholder_page.dart';
import 'package:totals/_redesign/widgets/redesign_bottom_nav.dart';
import 'package:totals/services/widget_launch_intent_service.dart';

class RedesignShell extends StatefulWidget {
  const RedesignShell({super.key});

  @override
  State<RedesignShell> createState() => _RedesignShellState();
}

class _RedesignShellState extends State<RedesignShell> {
  static const int _homeIndex = 0;
  static const int _budgetIndex = 2;
  final PageController _pageController =
      PageController(initialPage: _homeIndex);
  int _currentIndex = _homeIndex;
  StreamSubscription<WidgetLaunchTarget>? _widgetLaunchIntentSub;

  @override
  void initState() {
    super.initState();

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
  }

  @override
  void dispose() {
    _widgetLaunchIntentSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          RedesignHomePage(),
          RedesignMoneyPage(),
          RedesignPlaceholderPage(title: 'Budget'),
          RedesignPlaceholderPage(title: 'Tools'),
          RedesignPlaceholderPage(title: 'You', showRedesignToggle: true),
        ],
      ),
      bottomNavigationBar: RedesignBottomNav(
        currentIndex: _currentIndex,
        onTap: _onTabSelected,
      ),
    );
  }
}
