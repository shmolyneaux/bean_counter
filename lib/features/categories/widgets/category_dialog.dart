import 'package:flutter/material.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/database/database.dart';
import 'package:bean_budget/features/categories/widgets/category_pickers.dart';

/// Result returned from the category dialog.
class CategoryDialogResult {
  final String name;
  final String? parentId;
  final String icon;
  final int color;

  CategoryDialogResult({
    required this.name,
    required this.parentId,
    required this.icon,
    required this.color,
  });
}

/// Dialog for creating or editing a category.
class CategoryDialog extends StatefulWidget {
  /// If non-null, we're editing this category.
  final Category? existing;

  /// Available parent categories (top-level only).
  final List<Category> parentOptions;

  /// Pre-selected parent ID (when adding a sub-category).
  final String? initialParentId;

  const CategoryDialog({
    super.key,
    this.existing,
    required this.parentOptions,
    this.initialParentId,
  });

  @override
  State<CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<CategoryDialog> {
  late final TextEditingController _nameController;
  late String? _parentId;
  late String _icon;
  late int _color;
  bool _showIconPicker = false;
  bool _showColorPicker = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existing?.name ?? '',
    );
    _parentId = widget.existing?.parentId ?? widget.initialParentId;
    _icon = widget.existing?.icon ?? 'category';
    _color = widget.existing?.color ?? 0xFF3498DB;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isValid => _nameController.text.trim().isNotEmpty;
  bool get _isEditing => widget.existing != null;

  void _submit() {
    if (!_isValid) return;
    Navigator.of(context).pop(
      CategoryDialogResult(
        name: _nameController.text.trim(),
        parentId: _parentId,
        icon: _icon,
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(_color).withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      IconPickerGrid.resolveIcon(_icon),
                      color: Color(_color),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isEditing ? 'Edit Category' : 'New Category',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Name field
              const Text(
                'Name',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'e.g., Groceries',
                ),
              ),
              const SizedBox(height: 16),

              // Parent category dropdown (only for non-editing or if not a top-level)
              if (widget.parentOptions.isNotEmpty && !_isEditing) ...[
                const Text(
                  'Parent Category (optional)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _parentId,
                      isExpanded: true,
                      dropdownColor: AppColors.surfaceElevated,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      hint: const Text(
                        'None (top-level)',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None (top-level)'),
                        ),
                        ...widget.parentOptions.map((cat) {
                          return DropdownMenuItem<String?>(
                            value: cat.id,
                            child: Row(
                              children: [
                                Icon(
                                  IconPickerGrid.resolveIcon(cat.icon),
                                  size: 16,
                                  color: Color(cat.color),
                                ),
                                const SizedBox(width: 8),
                                Text(cat.name),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _parentId = value);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Icon & Color row
              Row(
                children: [
                  // Icon picker toggle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Icon',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showIconPicker = !_showIconPicker;
                              _showColorPicker = false;
                            });
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _showIconPicker
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  IconPickerGrid.resolveIcon(_icon),
                                  size: 20,
                                  color: AppColors.textPrimary,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Change',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Color picker toggle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Color',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showColorPicker = !_showColorPicker;
                              _showIconPicker = false;
                            });
                          },
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _showColorPicker
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Color(_color),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Change',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Icon picker grid (expandable)
              if (_showIconPicker) ...[
                const SizedBox(height: 12),
                IconPickerGrid(
                  selectedIcon: _icon,
                  onIconSelected: (icon) {
                    setState(() {
                      _icon = icon;
                      _showIconPicker = false;
                    });
                  },
                ),
              ],

              // Color picker grid (expandable)
              if (_showColorPicker) ...[
                const SizedBox(height: 12),
                ColorPickerGrid(
                  selectedColor: _color,
                  onColorSelected: (color) {
                    setState(() {
                      _color = color;
                      _showColorPicker = false;
                    });
                  },
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isValid ? _submit : null,
                    child: Text(_isEditing ? 'Save' : 'Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
