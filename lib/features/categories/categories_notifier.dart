import 'package:flutter/foundation.dart' hide Category;
import 'package:bean_budget/core/database/database.dart';
import 'package:bean_budget/core/repositories/category_repository.dart';

/// Holds the hierarchical category tree for the UI.
class CategoryNode {
  final Category category;
  final List<CategoryNode> children;

  CategoryNode({required this.category, required this.children});
}

class CategoriesNotifier extends ChangeNotifier {
  final CategoryRepository _repo;

  List<CategoryNode> _categoryTree = [];
  bool _isLoading = false;
  String? _error;

  CategoriesNotifier(this._repo);

  List<CategoryNode> get categoryTree => _categoryTree;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isEmpty => _categoryTree.isEmpty;

  /// Load the full category tree from the database.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final topLevel = await _repo.getTopLevelCategories();
      _categoryTree = await Future.wait(
        topLevel.map((cat) => _buildNode(cat)),
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<CategoryNode> _buildNode(Category category) async {
    final subs = await _repo.getSubCategories(category.id);
    final children = await Future.wait(subs.map((s) => _buildNode(s)));
    return CategoryNode(category: category, children: children);
  }

  /// Create a new category and refresh the tree.
  Future<void> createCategory({
    required String name,
    String? parentId,
    String icon = 'category',
    int color = 0xFF9E9E9E,
  }) async {
    await _repo.createCategory(
      name: name,
      parentId: parentId,
      icon: icon,
      color: color,
    );
    await load();
  }

  /// Update a category and refresh the tree.
  Future<void> updateCategory({
    required String id,
    String? name,
    String? icon,
    int? color,
  }) async {
    await _repo.updateCategory(
      id: id,
      name: name,
      icon: icon,
      color: color,
    );
    await load();
  }

  /// Delete a category and refresh the tree.
  Future<void> deleteCategory(String id) async {
    await _repo.deleteCategory(id);
    await load();
  }

  /// Get a flat list of all categories (useful for dropdowns).
  List<Category> get flatList {
    final result = <Category>[];
    void flatten(List<CategoryNode> nodes) {
      for (final node in nodes) {
        result.add(node.category);
        flatten(node.children);
      }
    }
    flatten(_categoryTree);
    return result;
  }
}
