import 'package:bean_budget/core/database/database.dart';

class MonthlySpend {
  final int year;
  final int month;
  final int totalCents;

  MonthlySpend({
    required this.year,
    required this.month,
    required this.totalCents,
  });
}

class CategorySpend {
  final String? categoryId;
  final String categoryName;
  final int color;
  final int amountCents;

  CategorySpend({
    required this.categoryId,
    required this.categoryName,
    required this.color,
    required this.amountCents,
  });
}

class ReportsRepository {
  final AppDatabase _db;

  ReportsRepository(this._db);

  /// Returns one [MonthlySpend] per month for the trailing 12 months
  /// (oldest first, current month last). Only positive amounts (charges) count.
  Future<List<MonthlySpend>> getMonthlySpending() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 11, 1);

    final allLines = await (_db.select(_db.statementLines)).get();
    final lines = allLines.where((l) => !l.date.isBefore(start)).toList();

    final monthMap = <String, int>{};
    for (final line in lines) {
      if (line.amount <= 0) continue;
      final key = '${line.date.year}-${line.date.month}';
      monthMap[key] = (monthMap[key] ?? 0) + line.amount;
    }

    return List.generate(12, (i) {
      final d = DateTime(now.year, now.month - 11 + i, 1);
      final key = '${d.year}-${d.month}';
      return MonthlySpend(
        year: d.year,
        month: d.month,
        totalCents: monthMap[key] ?? 0,
      );
    });
  }

  /// Returns spending broken down by category for the given month.
  ///
  /// Category resolution per transaction:
  /// - No receipt linked → use line's categoryId (or "Other")
  /// - Receipt linked, not itemised → use receipt's categoryId (or "Other")
  /// - Receipt linked and itemised → allocate transaction amount proportionally
  ///   by each item's price, using each item's categoryId (or "Other")
  Future<List<CategorySpend>> getCategoryBreakdown(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    final allLines = await (_db.select(_db.statementLines)).get();
    final lines = allLines
        .where((l) => !l.date.isBefore(start) && l.date.isBefore(end))
        .toList();

    // categoryId → accumulated cents (use '__other__' sentinel for unknown)
    final spending = <String, int>{};

    for (final line in lines) {
      if (line.amount <= 0) continue;

      if (line.receiptId == null) {
        _add(spending, line.categoryId ?? '__other__', line.amount);
      } else {
        final receipt = await (_db.select(_db.receipts)
              ..where((r) => r.id.equals(line.receiptId!)))
            .getSingleOrNull();

        if (receipt == null) {
          _add(spending, line.categoryId ?? '__other__', line.amount);
          continue;
        }

        final items = await (_db.select(_db.receiptItems)
              ..where((item) => item.receiptId.equals(receipt.id)))
            .get();

        if (items.isNotEmpty) {
          final totalItemCents =
              items.fold<int>(0, (s, i) => s + i.price);
          if (totalItemCents > 0) {
            for (final item in items) {
              final allocated =
                  (line.amount * item.price / totalItemCents).round();
              _add(spending, item.categoryId ?? '__other__', allocated);
            }
          } else {
            // Items have no price data — fall back to receipt/line category.
            _add(spending,
                receipt.categoryId ?? line.categoryId ?? '__other__',
                line.amount);
          }
        } else {
          // Not itemised — use receipt's category.
          _add(spending,
              receipt.categoryId ?? line.categoryId ?? '__other__',
              line.amount);
        }
      }
    }

    final allCategories = await (_db.select(_db.categories)).get();
    final catById = {for (final c in allCategories) c.id: c};

    final result = <CategorySpend>[];
    for (final entry in spending.entries) {
      if (entry.key == '__other__') {
        result.add(CategorySpend(
          categoryId: null,
          categoryName: 'Other',
          color: 0xFF9E9E9E,
          amountCents: entry.value,
        ));
      } else {
        final cat = catById[entry.key];
        result.add(CategorySpend(
          categoryId: entry.key,
          categoryName: cat?.name ?? 'Unknown',
          color: cat?.color ?? 0xFF9E9E9E,
          amountCents: entry.value,
        ));
      }
    }

    result.sort((a, b) => b.amountCents.compareTo(a.amountCents));
    return result;
  }

  void _add(Map<String, int> map, String key, int amount) {
    map[key] = (map[key] ?? 0) + amount;
  }
}
