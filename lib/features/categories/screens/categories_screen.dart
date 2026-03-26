import 'package:flutter/material.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/database/database.dart';
import 'package:bean_budget/features/categories/categories_notifier.dart';
import 'package:bean_budget/features/categories/widgets/category_dialog.dart';
import 'package:bean_budget/features/categories/widgets/category_pickers.dart';

class CategoriesScreen extends StatefulWidget {
  final CategoriesNotifier notifier;

  const CategoriesScreen({super.key, required this.notifier});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onNotifierChanged);
    if (widget.notifier.isEmpty && !widget.notifier.isLoading) {
      widget.notifier.load();
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showAddCategoryDialog({String? parentId}) async {
    final List<Category> topLevel = widget.notifier.categoryTree
        .map<Category>((n) => n.category)
        .toList();

    final result = await showDialog<CategoryDialogResult>(
      context: context,
      builder: (context) => CategoryDialog(
        parentOptions: topLevel,
        initialParentId: parentId,
      ),
    );

    if (result != null) {
      await widget.notifier.createCategory(
        name: result.name,
        parentId: result.parentId,
        icon: result.icon,
        color: result.color,
      );
    }
  }

  Future<void> _showEditCategoryDialog(Category category) async {
    final List<Category> topLevel = widget.notifier.categoryTree
        .map<Category>((n) => n.category)
        .toList();

    final result = await showDialog<CategoryDialogResult>(
      context: context,
      builder: (context) => CategoryDialog(
        existing: category,
        parentOptions: topLevel,
      ),
    );

    if (result != null) {
      await widget.notifier.updateCategory(
        id: category.id,
        name: result.name,
        icon: result.icon,
        color: result.color,
      );
    }
  }

  Future<void> _confirmDelete(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Delete Category'),
        content: Text(
          'Delete "${category.name}" and all its sub-categories?\nThis cannot be undone.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.notifier.deleteCategory(category.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
      ),
      body: _buildBody(notifier),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCategoryDialog(),
        tooltip: 'Add Category',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildBody(CategoriesNotifier notifier) {
    if (notifier.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (notifier.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              'Error loading categories',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              notifier.error!,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => notifier.load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (notifier.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category_rounded,
              size: 80,
              color: AppColors.textMuted.withAlpha(80),
            ),
            const SizedBox(height: 16),
            const Text(
              'No categories yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create categories to organize your expenses',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddCategoryDialog(),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add Category'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: notifier.categoryTree.length,
      itemBuilder: (context, index) {
        return _buildCategoryNode(notifier.categoryTree[index], depth: 0);
      },
    );
  }

  Widget _buildCategoryNode(CategoryNode node, {required int depth}) {
    final cat = node.category;
    final hasChildren = node.children.isNotEmpty;

    return Column(
      children: [
        _CategoryTile(
          category: cat,
          depth: depth,
          hasChildren: hasChildren,
          onEdit: () => _showEditCategoryDialog(cat),
          onDelete: () => _confirmDelete(cat),
          onAddChild: () => _showAddCategoryDialog(parentId: cat.id),
        ),
        if (hasChildren)
          ...node.children.map(
            (child) => _buildCategoryNode(child, depth: depth + 1),
          ),
      ],
    );
  }
}

class _CategoryTile extends StatefulWidget {
  final Category category;
  final int depth;
  final bool hasChildren;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddChild;

  const _CategoryTile({
    required this.category,
    required this.depth,
    required this.hasChildren,
    required this.onEdit,
    required this.onDelete,
    required this.onAddChild,
  });

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final leftPadding = 16.0 + (widget.depth * 32.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _isHovered ? AppColors.surfaceElevated.withAlpha(120) : Colors.transparent,
        child: Padding(
          padding: EdgeInsets.only(
            left: leftPadding,
            right: 12,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(cat.color).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  IconPickerGrid.resolveIcon(cat.icon),
                  color: Color(cat.color),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),

              // Name
              Expanded(
                child: Text(
                  cat.name,
                  style: TextStyle(
                    fontSize: widget.depth == 0 ? 15 : 14,
                    fontWeight: widget.depth == 0 ? FontWeight.w600 : FontWeight.w400,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),

              // Action buttons (visible on hover)
              AnimatedOpacity(
                opacity: _isHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 100),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Add sub-category (only for top-level)
                    if (widget.depth == 0)
                      _ActionButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Add sub-category',
                        onPressed: widget.onAddChild,
                      ),
                    _ActionButton(
                      icon: Icons.edit_rounded,
                      tooltip: 'Edit',
                      onPressed: widget.onEdit,
                    ),
                    _ActionButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete',
                      onPressed: widget.onDelete,
                      color: AppColors.error,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: color ?? AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
