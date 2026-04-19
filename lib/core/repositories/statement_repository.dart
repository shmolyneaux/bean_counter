import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:bean_budget/core/database/database.dart';

class ReceiptMatchData {
  final Receipt receipt;
  final Image? image;
  final Store? store;
  final bool isExactMatch;

  ReceiptMatchData({
    required this.receipt,
    this.image,
    this.store,
    required this.isExactMatch,
  });
}

class StatementRepository {
  final AppDatabase _db;
  static const _uuid = Uuid();

  StatementRepository(this._db);

  Future<List<Statement>> getAllStatements() {
    return (_db.select(_db.statements)
          ..orderBy([(s) => OrderingTerm.desc(s.statementPeriodEnd)]))
        .get();
  }

  Future<int> countLinesForStatement(String statementId) async {
    final count = await (_db.select(_db.statementLines)
          ..where((l) => l.statementId.equals(statementId)))
        .get();
    return count.length;
  }

  Future<Statement> createStatement({
    required String source,
    required String filePath,
    required String accountLastFour,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.statements).insert(
      StatementsCompanion.insert(
        id: id,
        source: source,
        filePath: filePath,
        accountLastFour: accountLastFour,
        statementPeriodStart: periodStart,
        statementPeriodEnd: periodEnd,
      ),
    );
    return (_db.select(_db.statements)..where((s) => s.id.equals(id))).getSingle();
  }

  Future<void> insertStatementLine({
    required String statementId,
    required DateTime date,
    required String payee,
    required int amount,
    String? categoryId,
    String? receiptId,
    int sortOrder = 0,
  }) async {
    await _db.into(_db.statementLines).insert(
      StatementLinesCompanion.insert(
        id: _uuid.v4(),
        statementId: statementId,
        date: date,
        payee: payee,
        amount: amount,
        categoryId: Value(categoryId),
        receiptId: Value(receiptId),
        sortOrder: Value(sortOrder),
      ),
    );
  }

  Future<List<StatementLine>> getLinesForStatement(String statementId) {
    return (_db.select(_db.statementLines)
          ..where((l) => l.statementId.equals(statementId))
          ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
        .get();
  }

  /// Returns the effective categoryId for each receipt:
  /// - the receipt's own categoryId if set, or
  /// - '__mixed__' if the receipt is itemized (has any items), or
  /// - null if truly uncategorized.
  Future<Map<String, String?>> getReceiptCategoryIds(
      List<String> receiptIds) async {
    if (receiptIds.isEmpty) return {};
    final receipts = await (_db.select(_db.receipts)
          ..where((r) => r.id.isIn(receiptIds)))
        .get();
    final result = <String, String?>{};
    for (final r in receipts) {
      if (r.categoryId != null) {
        result[r.id] = r.categoryId;
      } else {
        final items = await (_db.select(_db.receiptItems)
              ..where((i) => i.receiptId.equals(r.id)))
            .get();
        result[r.id] = items.isNotEmpty ? '__mixed__' : null;
      }
    }
    return result;
  }

  /// Returns the set of absolute cent amounts that have at least one exact receipt match.
  Future<Set<int>> getExactMatchAmounts(List<int> amounts) async {
    if (amounts.isEmpty) return {};
    final absAmounts = amounts.map((a) => a.abs()).toSet();
    final receipts = await (_db.select(_db.receipts)
          ..where((r) => r.total.isNotNull()))
        .get();
    return absAmounts.where((a) => receipts.any((r) => r.total == a)).toSet();
  }

  Future<void> updateLineCategory(String lineId, String? categoryId) async {
    await (_db.update(_db.statementLines)
          ..where((l) => l.id.equals(lineId)))
        .write(StatementLinesCompanion(categoryId: Value(categoryId)));
  }

  Future<void> updateLineNotes(String lineId, String? notes) async {
    await (_db.update(_db.statementLines)
          ..where((l) => l.id.equals(lineId)))
        .write(StatementLinesCompanion(notes: Value(notes)));
  }

  Future<void> updateLineReceipt(String lineId, String? receiptId) async {
    await (_db.update(_db.statementLines)
          ..where((l) => l.id.equals(lineId)))
        .write(StatementLinesCompanion(receiptId: Value(receiptId)));
  }

  Future<void> deleteStatement(String statementId) async {
    await (_db.delete(_db.statementLines)
          ..where((l) => l.statementId.equals(statementId)))
        .go();
    await (_db.delete(_db.statements)
          ..where((s) => s.id.equals(statementId)))
        .go();
  }

  /// Finds receipts whose total is within 40% of [amountCents] (uses absolute value).
  /// Exact matches appear first; near matches sorted by amount+date proximity.
  Future<List<ReceiptMatchData>> findMatchingReceipts(
    int amountCents,
    DateTime date,
  ) async {
    final absAmount = amountCents.abs();
    if (absAmount == 0) return [];

    final receipts = await (_db.select(_db.receipts)
          ..where((r) => r.total.isNotNull()))
        .get();

    final tolerance = (absAmount * 0.40).round();
    final candidates = <({double score, Receipt receipt, bool isExact})>[];

    for (final r in receipts) {
      final diff = (r.total! - absAmount).abs();
      if (diff <= tolerance) {
        final isExact = diff == 0;
        double score = diff.toDouble();
        if (r.dateTime_ != null) {
          final dayDiff = r.dateTime_!.difference(date).inDays.abs();
          score += dayDiff * 50.0;
        }
        candidates.add((score: score, receipt: r, isExact: isExact));
      }
    }

    candidates.sort((a, b) => a.score.compareTo(b.score));

    final result = <ReceiptMatchData>[];
    for (final c in candidates.take(10)) {
      final r = c.receipt;
      final img = r.imageId == null
          ? null
          : await (_db.select(_db.images)..where((i) => i.id.equals(r.imageId!)))
              .getSingleOrNull();
      final store = r.storeId == null
          ? null
          : await (_db.select(_db.stores)..where((s) => s.id.equals(r.storeId!)))
              .getSingleOrNull();
      result.add(ReceiptMatchData(
        receipt: r,
        image: img,
        store: store,
        isExactMatch: c.isExact,
      ));
    }
    return result;
  }
}
