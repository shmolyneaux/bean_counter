import 'package:drift/drift.dart';
import 'package:bean_budget/core/database/database.dart';
import 'package:uuid/uuid.dart';

class CategoryRepository {
  final AppDatabase _db;
  static const _uuid = Uuid();

  CategoryRepository(this._db);

  /// Get all top-level categories (no parent) ordered by sortOrder.
  Future<List<Category>> getTopLevelCategories() {
    final query = _db.select(_db.categories)
      ..where((c) => c.parentId.isNull())
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    return query.get();
  }

  /// Get sub-categories for a given parent.
  Future<List<Category>> getSubCategories(String parentId) {
    final query = _db.select(_db.categories)
      ..where((c) => c.parentId.equals(parentId))
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    return query.get();
  }

  /// Get all categories as a flat list.
  Future<List<Category>> getAllCategories() {
    final query = _db.select(_db.categories)
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.name),
      ]);
    return query.get();
  }

  /// Get a single category by ID.
  Future<Category?> getCategoryById(String id) {
    final query = _db.select(_db.categories)
      ..where((c) => c.id.equals(id));
    return query.getSingleOrNull();
  }

  /// Create a new category. Returns the created category.
  Future<Category> createCategory({
    required String name,
    String? parentId,
    String icon = 'category',
    int color = 0xFF9E9E9E,
    int? sortOrder,
  }) async {
    final id = _uuid.v4();

    // If no sortOrder specified, put it at the end.
    if (sortOrder == null) {
      final maxOrder = await _getMaxSortOrder(parentId);
      sortOrder = maxOrder + 1;
    }

    final companion = CategoriesCompanion.insert(
      id: id,
      name: name,
      parentId: Value(parentId),
      icon: Value(icon),
      color: Value(color),
      sortOrder: Value(sortOrder),
    );

    await _db.into(_db.categories).insert(companion);
    return (await getCategoryById(id))!;
  }

  /// Update an existing category.
  Future<void> updateCategory({
    required String id,
    String? name,
    String? icon,
    int? color,
    int? sortOrder,
  }) {
    final companion = CategoriesCompanion(
      name: name != null ? Value(name) : const Value.absent(),
      icon: icon != null ? Value(icon) : const Value.absent(),
      color: color != null ? Value(color) : const Value.absent(),
      sortOrder: sortOrder != null ? Value(sortOrder) : const Value.absent(),
    );

    return (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(companion);
  }

  /// Delete a category and all its sub-categories.
  Future<void> deleteCategory(String id) async {
    // First delete all sub-categories
    final subs = await getSubCategories(id);
    for (final sub in subs) {
      await deleteCategory(sub.id);
    }
    // Then delete the category itself
    await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
  }

  /// Get the maximum sort order for categories at a given level.
  Future<int> _getMaxSortOrder(String? parentId) async {
    final query = _db.select(_db.categories);
    if (parentId == null) {
      query.where((c) => c.parentId.isNull());
    } else {
      query.where((c) => c.parentId.equals(parentId));
    }
    final results = await query.get();
    if (results.isEmpty) return -1;
    return results.fold<int>(0, (max, c) => c.sortOrder > max ? c.sortOrder : max);
  }

  /// Check if a category has any sub-categories.
  Future<bool> hasSubCategories(String id) async {
    final query = _db.select(_db.categories)
      ..where((c) => c.parentId.equals(id));
    final results = await query.get();
    return results.isNotEmpty;
  }
}
