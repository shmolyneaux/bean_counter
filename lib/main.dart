import 'package:flutter/material.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/database/database.dart';
import 'package:bean_budget/core/repositories/category_repository.dart';
import 'package:bean_budget/core/repositories/receipt_repository.dart';
import 'package:bean_budget/core/repositories/statement_repository.dart';
import 'package:bean_budget/core/repositories/reports_repository.dart';
import 'package:bean_budget/features/categories/categories_notifier.dart';
import 'package:bean_budget/features/receipts/receipts_notifier.dart';
import 'package:bean_budget/features/statements/statements_notifier.dart';
import 'package:bean_budget/features/reports/reports_notifier.dart';
import 'package:bean_budget/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase.instance();
  final categoryRepo = CategoryRepository(db);
  final categoriesNotifier = CategoriesNotifier(categoryRepo);

  final receiptRepo = ReceiptRepository(db);
  final receiptsNotifier = ReceiptsNotifier(receiptRepo);

  final statementRepo = StatementRepository(db);
  final statementsNotifier = StatementsNotifier(statementRepo);

  final reportsRepo = ReportsRepository(db);
  final reportsNotifier = ReportsNotifier(reportsRepo);

  runApp(BeanBudgetApp(
    categoriesNotifier: categoriesNotifier,
    receiptsNotifier: receiptsNotifier,
    statementsNotifier: statementsNotifier,
    reportsNotifier: reportsNotifier,
  ));
}

class BeanBudgetApp extends StatelessWidget {
  final CategoriesNotifier categoriesNotifier;
  final ReceiptsNotifier receiptsNotifier;
  final StatementsNotifier statementsNotifier;
  final ReportsNotifier reportsNotifier;

  const BeanBudgetApp({
    super.key,
    required this.categoriesNotifier,
    required this.receiptsNotifier,
    required this.statementsNotifier,
    required this.reportsNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BeanBudget',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: AppShell(
        categoriesNotifier: categoriesNotifier,
        receiptsNotifier: receiptsNotifier,
        statementsNotifier: statementsNotifier,
        reportsNotifier: reportsNotifier,
      ),
    );
  }
}
