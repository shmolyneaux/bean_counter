import 'package:flutter/material.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/features/receipts/screens/receipts_screen.dart';
import 'package:bean_budget/features/receipts/receipts_notifier.dart';
import 'package:bean_budget/features/statements/screens/statements_screen.dart';
import 'package:bean_budget/features/statements/statements_notifier.dart';
import 'package:bean_budget/features/categories/screens/categories_screen.dart';
import 'package:bean_budget/features/categories/categories_notifier.dart';
import 'package:bean_budget/features/reports/screens/reports_screen.dart';

class AppShell extends StatefulWidget {
  final CategoriesNotifier categoriesNotifier;
  final ReceiptsNotifier receiptsNotifier;
  final StatementsNotifier statementsNotifier;

  const AppShell({
    super.key,
    required this.categoriesNotifier,
    required this.receiptsNotifier,
    required this.statementsNotifier,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const List<_NavDestination> _destinations = [
    _NavDestination(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Receipts',
    ),
    _NavDestination(
      icon: Icons.description_outlined,
      selectedIcon: Icons.description_rounded,
      label: 'Statements',
    ),
    _NavDestination(
      icon: Icons.category_outlined,
      selectedIcon: Icons.category_rounded,
      label: 'Categories',
    ),
    _NavDestination(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart_rounded,
      label: 'Reports',
    ),
  ];

  List<Widget> get _screens => [
        ReceiptsScreen(
            notifier: widget.receiptsNotifier,
            categoriesNotifier: widget.categoriesNotifier),
        StatementsScreen(
          notifier: widget.statementsNotifier,
          categoriesNotifier: widget.categoriesNotifier,
        ),
        CategoriesScreen(notifier: widget.categoriesNotifier),
        const ReportsScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                right: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() => _selectedIndex = index);
              },
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 20),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.primary, AppColors.primaryDark],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.savings_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Bean\nBudget',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              destinations: _destinations
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_selectedIndex),
                child: _screens[_selectedIndex],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
