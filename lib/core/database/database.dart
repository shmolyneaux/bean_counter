import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:bean_budget/core/database/tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Stores,
  Categories,
  Images,
  Receipts,
  ReceiptItems,
  Statements,
  StatementLines,
  PayeeRules,
  CsvProfiles,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  /// Singleton instance.
  static AppDatabase? _instance;

  /// Get or create the singleton database instance.
  static AppDatabase instance() {
    return _instance ??= AppDatabase._internal(_openConnection());
  }

  /// For testing: create a database with a custom executor.
  factory AppDatabase.forTesting(QueryExecutor executor) {
    return AppDatabase._internal(executor);
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          // Recreate the receipts table to apply the imageId and cropPoints schema change
          await m.deleteTable('receipts');
          await m.createTable(receipts);
        }
        if (from < 3) {
          await m.addColumn(receipts, receipts.categoryId);
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(appDir.path, 'BeanBudget', 'database'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    final file = File(p.join(dbDir.path, 'bean_budget.db'));
    return NativeDatabase.createInBackground(file);
  });
}
