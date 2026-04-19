import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/database/database.dart';
import 'package:bean_budget/features/statements/statements_notifier.dart';
import 'package:bean_budget/features/categories/categories_notifier.dart';
import 'package:bean_budget/features/statements/screens/receipt_picker_dialog.dart';

final _monthFmt = DateFormat('MMMM yyyy');
final _shortDateFmt = DateFormat('MMM d');
final _currencyFmt = NumberFormat('#,##0.00');

class TransactionsScreen extends StatefulWidget {
  final StatementsNotifier notifier;
  final CategoriesNotifier categoriesNotifier;

  const TransactionsScreen({
    super.key,
    required this.notifier,
    required this.categoriesNotifier,
  });

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChange);
    widget.categoriesNotifier.addListener(_onChange);
    if (widget.notifier.statements.isEmpty && !widget.notifier.isLoading) {
      widget.notifier.load();
    }
    if (widget.categoriesNotifier.isEmpty && !widget.categoriesNotifier.isLoading) {
      widget.categoriesNotifier.load();
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChange);
    widget.categoriesNotifier.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // ── Formatting helpers ───────────────────────────────────────────────────

  String _fmtAmount(int cents) =>
      '\$${_currencyFmt.format(cents.abs() / 100.0)}';

  Color _amountColor(int cents) {
    if (cents > 0) return AppColors.warning;
    if (cents < 0) return AppColors.success;
    return AppColors.textMuted;
  }

  // ── Category helpers ─────────────────────────────────────────────────────

  String _categoryLabel(String? id) {
    if (id == null) return '— Uncategorized —';
    if (id == kMixedCategoryId) return 'Mixed';
    if (id == kIgnoredCategoryId) return 'Ignore';
    return widget.categoriesNotifier.flatList
            .where((c) => c.id == id)
            .firstOrNull
            ?.name ??
        '— Uncategorized —';
  }

  Color _categoryDotColor(String? id) {
    if (id == kMixedCategoryId) return AppColors.accent;
    if (id == kIgnoredCategoryId) return AppColors.textMuted;
    if (id == null) return AppColors.textMuted;
    final cat =
        widget.categoriesNotifier.flatList.where((c) => c.id == id).firstOrNull;
    return cat != null ? Color(cat.color) : AppColors.textMuted;
  }

  // ── Month grouping ───────────────────────────────────────────────────────

  List<_MonthGroup> _buildMonthGroups() {
    final allEntries = <(Statement, StatementLine)>[];
    for (final statement in widget.notifier.statements) {
      final lines = widget.notifier.loadedLines[statement.id] ?? [];
      for (final line in lines) {
        allEntries.add((statement, line));
      }
    }
    allEntries.sort((a, b) => b.$2.date.compareTo(a.$2.date));

    final groupMap = <String, List<(Statement, StatementLine)>>{};
    for (final entry in allEntries) {
      final key = DateFormat('yyyy-MM').format(entry.$2.date);
      (groupMap[key] ??= []).add(entry);
    }

    final monthKeys = groupMap.keys.toList()..sort((a, b) => b.compareTo(a));
    return monthKeys.map((key) {
      final dt = DateTime.parse('$key-01');
      return _MonthGroup(
        label: _monthFmt.format(dt),
        entries: groupMap[key]!,
      );
    }).toList();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          if (widget.notifier.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (widget.notifier.isLoading && widget.notifier.statements.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final groups = _buildMonthGroups();

    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 80, color: AppColors.textMuted.withAlpha(80)),
            const SizedBox(height: 16),
            const Text('No transactions yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('Import statements to see transactions here',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (widget.notifier.error != null)
          _errorBanner(widget.notifier.error!),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: groups.length,
            itemBuilder: (_, i) => _buildMonthSection(groups[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthSection(_MonthGroup group) {
    int totalCharge = 0;
    int categorized = 0;
    int uncategorized = 0;
    for (final (_, line) in group.entries) {
      final effectiveCat = widget.notifier.effectiveCategoryId(line);
      if (line.amount > 0) totalCharge += line.amount;
      if (effectiveCat != null) {
        categorized++;
      } else {
        uncategorized++;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          // ── Month header ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBright,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calendar_month_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('${group.entries.length} transactions',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _fmtAmount(totalCharge),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(width: 10),
                if (uncategorized == 0)
                  _chip('$categorized categorized', AppColors.success)
                else ...[
                  _chip('$categorized categorized', AppColors.success),
                  const SizedBox(width: 6),
                  _chip('$uncategorized uncategorized', AppColors.warning),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Table header ───────────────────────────────────────────────
          _buildTableHeader(),
          const Divider(height: 1),
          // ── Rows ───────────────────────────────────────────────────────
          ...group.entries.map((entry) => _buildRow(entry.$1, entry.$2)),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    const s = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
      letterSpacing: 0.5,
    );
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          SizedBox(width: 92, child: Text('DATE', style: s)),
          SizedBox(
              width: 138,
              child: Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('SOURCE', style: s))),
          Expanded(
              child: Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('DESCRIPTION', style: s))),
          SizedBox(
              width: 100,
              child: Text('AMOUNT', style: s, textAlign: TextAlign.right)),
          SizedBox(width: 12),
          SizedBox(width: 210, child: Text('CATEGORY', style: s)),
          SizedBox(width: 12),
          SizedBox(width: 160, child: Text('RECEIPT', style: s)),
          SizedBox(width: 12),
          Expanded(child: Text('NOTES', style: s)),
        ],
      ),
    );
  }

  Widget _buildRow(Statement statement, StatementLine line) {
    final effectiveCategoryId = widget.notifier.effectiveCategoryId(line);
    return _TxRow(
      key: ValueKey(line.id),
      line: line,
      sourceLabel: statement.source,
      categoryButton:
          _buildCategoryButton(statement, line, effectiveCategoryId),
      effectiveCategoryId: effectiveCategoryId,
      hasExactReceiptMatch: widget.notifier.hasExactReceiptMatch(line),
      amountColor: _amountColor(line.amount),
      formattedAmount: _fmtAmount(line.amount),
      formattedDate: _shortDateFmt.format(line.date),
      onSaveNotes: (notes) =>
          widget.notifier.updateLineNotes(statement.id, line.id, notes),
      onPickReceipt: () => _pickReceipt(statement, line),
    );
  }

  Widget _buildCategoryButton(
      Statement statement, StatementLine line, String? effectiveCategoryId) {
    final cats = widget.categoriesNotifier.flatList;
    return PopupMenuButton<String?>(
      tooltip: '',
      onSelected: (value) =>
          widget.notifier.updateLineCategory(statement.id, line.id, value),
      itemBuilder: (_) => [
        PopupMenuItem<String?>(
          value: null,
          child: Text('— Uncategorized —',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        if (cats.isNotEmpty) const PopupMenuDivider(),
        ...cats.map((c) => PopupMenuItem<String?>(
              value: c.id,
              child: Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: Color(c.color))),
                const SizedBox(width: 10),
                Text(c.name, style: const TextStyle(fontSize: 13)),
              ]),
            )),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _categoryDotColor(effectiveCategoryId))),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_categoryLabel(effectiveCategoryId),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded,
                size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _pickReceipt(Statement statement, StatementLine line) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => ReceiptPickerDialog(
        notifier: widget.notifier,
        amountCents: line.amount,
        date: line.date,
        currentReceiptId: line.receiptId,
        showNoMatch: widget.notifier.hasExactReceiptMatch(line),
      ),
    );
    if (picked == '__no_match__') {
      widget.notifier.suppressExactMatch(line.id);
    } else if (picked != null) {
      await widget.notifier.updateLineReceipt(
          statement.id, line.id, picked.isEmpty ? null : picked);
    }
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _errorBanner(String error) {
    return Container(
      width: double.infinity,
      color: AppColors.error.withAlpha(30),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(error,
                  style: const TextStyle(fontSize: 13, color: AppColors.error))),
        ],
      ),
    );
  }
}

// ── Month group data ──────────────────────────────────────────────────────────

class _MonthGroup {
  final String label;
  final List<(Statement, StatementLine)> entries;
  const _MonthGroup({required this.label, required this.entries});
}

// ── Transaction row ───────────────────────────────────────────────────────────

class _TxRow extends StatefulWidget {
  final StatementLine line;
  final String sourceLabel;
  final Widget categoryButton;
  final String? effectiveCategoryId;
  final bool hasExactReceiptMatch;
  final Color amountColor;
  final String formattedAmount;
  final String formattedDate;
  final void Function(String?) onSaveNotes;
  final VoidCallback onPickReceipt;

  const _TxRow({
    super.key,
    required this.line,
    required this.sourceLabel,
    required this.categoryButton,
    required this.effectiveCategoryId,
    required this.hasExactReceiptMatch,
    required this.amountColor,
    required this.formattedAmount,
    required this.formattedDate,
    required this.onSaveNotes,
    required this.onPickReceipt,
  });

  @override
  State<_TxRow> createState() => _TxRowState();
}

class _TxRowState extends State<_TxRow> {
  late final TextEditingController _notesCtrl;
  late final FocusNode _notesFocus;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.line.notes ?? '');
    _notesFocus = FocusNode();
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_TxRow old) {
    super.didUpdateWidget(old);
    if (old.line.notes != widget.line.notes && !_notesFocus.hasFocus) {
      _notesCtrl.text = widget.line.notes ?? '';
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _save() {
    final text = _notesCtrl.text.trim();
    final current = widget.line.notes ?? '';
    if (text != current) widget.onSaveNotes(text.isEmpty ? null : text);
  }

  Widget _buildReceiptButton() {
    final linked = widget.line.receiptId != null;
    final hasMatch = widget.hasExactReceiptMatch;
    final borderColor = linked
        ? AppColors.primary
        : hasMatch
            ? AppColors.success
            : AppColors.border;
    final iconColor = linked
        ? AppColors.primary
        : hasMatch
            ? Colors.white
            : AppColors.textMuted;
    final textColor = linked
        ? AppColors.primary
        : hasMatch
            ? Colors.white
            : AppColors.textMuted;
    final label = linked
        ? 'Receipt linked'
        : hasMatch
            ? 'Exact match found'
            : 'Select receipt';
    final icon = linked || hasMatch
        ? Icons.receipt_long_rounded
        : Icons.add_rounded;

    return InkWell(
      onTap: widget.onPickReceipt,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: linked
              ? AppColors.primary.withAlpha(30)
              : hasMatch
                  ? AppColors.success
                  : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: textColor),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uncategorized = widget.effectiveCategoryId == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: uncategorized ? AppColors.error.withAlpha(20) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Date
                SizedBox(
                  width: 92,
                  child: Text(widget.formattedDate,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ),
                // Source
                SizedBox(
                  width: 138,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(widget.sourceLabel,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                // Description
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(widget.line.payee,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                // Amount
                SizedBox(
                  width: 100,
                  child: Text(
                    widget.formattedAmount,
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.amountColor,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 12),
                // Category
                SizedBox(width: 210, child: widget.categoryButton),
                const SizedBox(width: 12),
                // Receipt
                SizedBox(width: 160, child: _buildReceiptButton()),
                const SizedBox(width: 12),
                // Notes
                Expanded(
                  child: TextField(
                    controller: _notesCtrl,
                    focusNode: _notesFocus,
                    onSubmitted: (_) => _save(),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    decoration: InputDecoration(
                      hintText: 'Add a note…',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, indent: 12, endIndent: 12),
      ],
    );
  }
}
