import 'package:flutter/material.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/database/database.dart';
import 'package:bean_budget/core/repositories/category_repository.dart';
import 'package:bean_budget/core/repositories/receipt_repository.dart';
import 'package:bean_budget/features/categories/categories_notifier.dart';
import 'package:bean_budget/features/receipts/receipts_notifier.dart';
import 'package:bean_budget/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database and repositories
  final db = AppDatabase.instance();
  final categoryRepo = CategoryRepository(db);
  final categoriesNotifier = CategoriesNotifier(categoryRepo);

  final receiptRepo = ReceiptRepository(db);
  final receiptsNotifier = ReceiptsNotifier(receiptRepo);

  runApp(BeanBudgetApp(
    categoriesNotifier: categoriesNotifier,
    receiptsNotifier: receiptsNotifier,
  ));
}

class BeanBudgetApp extends StatelessWidget {
  final CategoriesNotifier categoriesNotifier;
  final ReceiptsNotifier receiptsNotifier;

  const BeanBudgetApp({
    super.key, 
    required this.categoriesNotifier,
    required this.receiptsNotifier,
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
      ),
    );
  }
}
