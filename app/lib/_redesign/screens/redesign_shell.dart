import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/home_page.dart';
import 'package:totals/_redesign/screens/placeholder_page.dart';
import 'package:totals/_redesign/widgets/redesign_bottom_nav.dart';

class RedesignShell extends StatefulWidget {
  const RedesignShell({super.key});

  @override
  State<RedesignShell> createState() => _RedesignShellState();
}

class _RedesignShellState extends State<RedesignShell> {
  static const int _homeIndex = 0;
  final PageController _pageController = PageController(initialPage: _homeIndex);
  int _currentIndex = _homeIndex;

  @override
  void dispose() {
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
          RedesignPlaceholderPage(title: 'Money'),
          RedesignPlaceholderPage(title: 'Budget'),
          RedesignPlaceholderPage(title: 'Tools'),
          RedesignPlaceholderPage(title: 'You'),
        ],
      ),
      bottomNavigationBar: RedesignBottomNav(
        currentIndex: _currentIndex,
        onTap: _onTabSelected,
      ),
    );
  }
}
