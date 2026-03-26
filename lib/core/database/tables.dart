import 'dart:convert';
import 'package:drift/drift.dart';

/// Represents a single 2D coordinate inside an image (0.0 to 1.0).
class Coordinate {
  final double x;
  final double y;
  Coordinate({required this.x, required this.y});
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory Coordinate.fromJson(Map<String, dynamic> json) => 
      Coordinate(x: (json['x'] as num).toDouble(), y: (json['y'] as num).toDouble());
}

/// Represents the 4 corners of a cropped region inside an image.
class CropPoints {
  final Coordinate topLeft;
  final Coordinate topRight;
  final Coordinate bottomRight;
  final Coordinate bottomLeft;

  CropPoints({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  Map<String, dynamic> toJson() => {
    'tl': topLeft.toJson(),
    'tr': topRight.toJson(),
    'br': bottomRight.toJson(),
    'bl': bottomLeft.toJson(),
  };

  factory CropPoints.fromJson(Map<String, dynamic> json) => CropPoints(
    topLeft: Coordinate.fromJson(json['tl'] as Map<String, dynamic>),
    topRight: Coordinate.fromJson(json['tr'] as Map<String, dynamic>),
    bottomRight: Coordinate.fromJson(json['br'] as Map<String, dynamic>),
    bottomLeft: Coordinate.fromJson(json['bl'] as Map<String, dynamic>),
  );
}

class CropPointsConverter extends TypeConverter<CropPoints, String> {
  const CropPointsConverter();
  @override
  CropPoints fromSql(String fromDb) => CropPoints.fromJson(json.decode(fromDb) as Map<String, dynamic>);
  @override
  String toSql(CropPoints value) => json.encode(value.toJson());
}

/// Stores (e.g., Costco, Walmart) with optional default category.
class Stores extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1)();
  TextColumn get defaultCategoryId => text().nullable().references(Categories, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Expense categories with hierarchical sub-category support.
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1)();
  TextColumn get parentId => text().nullable().references(Categories, #id)();
  TextColumn get icon => text().withDefault(const Constant('category'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF9E9E9E))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Images stored on disk (both uncropped and cropped receipt images).
class Images extends Table {
  TextColumn get id => text()();
  TextColumn get filePath => text()();
  TextColumn get originalFilename => text()();
  TextColumn get mimeType => text().withDefault(const Constant('image/jpeg'))();
  IntColumn get width => integer().withDefault(const Constant(0))();
  IntColumn get height => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Receipts with progressive annotation — most fields nullable until annotated.
class Receipts extends Table {
  TextColumn get id => text()();
  TextColumn get imageId => text().nullable().references(Images, #id)();
  TextColumn get cropPoints => text().map(const CropPointsConverter()).nullable()();
  DateTimeColumn get dateTime_ => dateTime().nullable()();
  TextColumn get lastFourCc => text().nullable().withLength(min: 4, max: 4)();
  IntColumn get subtotal => integer().nullable()();
  IntColumn get total => integer().nullable()();
  IntColumn get amountCad => integer().nullable()();
  TextColumn get storeId => text().nullable().references(Stores, #id)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get statementLineId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('raw'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Individual line items on a receipt.
class ReceiptItems extends Table {
  TextColumn get id => text()();
  TextColumn get receiptId => text().references(Receipts, #id)();
  TextColumn get itemName => text().withLength(min: 1)();
  IntColumn get price => integer()();
  BoolColumn get isTaxable => boolean().withDefault(const Constant(false))();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Bank/credit card statements.
class Statements extends Table {
  TextColumn get id => text()();
  TextColumn get source => text().withLength(min: 1)();
  TextColumn get accountLastFour => text().withLength(min: 4, max: 4)();
  DateTimeColumn get statementPeriodStart => dateTime()();
  DateTimeColumn get statementPeriodEnd => dateTime()();
  TextColumn get filePath => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Individual lines within a statement (one per transaction).
class StatementLines extends Table {
  TextColumn get id => text()();
  TextColumn get statementId => text().references(Statements, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get payee => text()();
  IntColumn get amount => integer()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get receiptId => text().nullable().references(Receipts, #id)();
  TextColumn get notes => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Rules for auto-categorizing statement lines by payee name.
class PayeeRules extends Table {
  TextColumn get id => text()();
  TextColumn get pattern => text().withLength(min: 1)();
  TextColumn get matchType => text().withDefault(const Constant('contains'))();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get storeId => text().nullable().references(Stores, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Saved CSV column mappings per bank, so re-imports auto-map.
class CsvProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1)();
  IntColumn get dateColumn => integer()();
  IntColumn get payeeColumn => integer()();
  IntColumn get amountColumn => integer()();
  TextColumn get delimiter => text().withDefault(const Constant(','))();
  BoolColumn get hasHeaderRow => boolean().withDefault(const Constant(true))();
  TextColumn get dateFormat => text().withDefault(const Constant('MM/dd/yyyy'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
