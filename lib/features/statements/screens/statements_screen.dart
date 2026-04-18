import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/database/database.dart' hide Image;
import 'package:bean_budget/core/repositories/statement_repository.dart';
import 'package:bean_budget/features/statements/statements_notifier.dart';
import 'package:bean_budget/features/categories/categories_notifier.dart';

final _dateFmt = DateFormat('MMM d, yyyy');
final _shortDateFmt = DateFormat('MMM d');
final _currencyFmt = NumberFormat('#,##0.00');

class StatementsScreen extends StatefulWidget {
  final StatementsNotifier notifier;
  final CategoriesNotifier categoriesNotifier;

  const StatementsScreen({
    super.key,
    required this.notifier,
    required this.categoriesNotifier,
  });

  @override
  State<StatementsScreen> createState() => _StatementsScreenState();
}

class _StatementsScreenState extends State<StatementsScreen> {
  final _scrollController = ScrollController();
  final _expandedIds = <String>{};

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
    _scrollController.dispose();
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

  // ── Receipt picker ───────────────────────────────────────────────────────

  Future<void> _pickReceipt(ImportedTransaction tx) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _ReceiptPickerDialog(
        notifier: widget.notifier,
        amountCents: tx.amountCents,
        date: tx.date,
        currentReceiptId: tx.receiptId,
      ),
    );
    // empty string = unlink, non-null = link
    if (picked != null) {
      widget.notifier.setTransactionReceipt(
          tx.tempId, picked.isEmpty ? null : picked);
      if (picked.isNotEmpty && tx.categoryId != kMixedCategoryId) {
        widget.notifier.setTransactionCategory(tx.tempId, kMixedCategoryId);
      }
    }
  }

  // ── Root build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.notifier.hasPending) return _buildEditor();
    return _buildList();
  }

  // ── Statements list ──────────────────────────────────────────────────────

  Widget _buildList() {
    final statements = widget.notifier.statements;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statements'),
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed:
                  widget.notifier.isLoading ? null : widget.notifier.importPdf,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('Import PDF'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.notifier.error != null)
            _errorBanner(widget.notifier.error!),
          Expanded(
            child: statements.isEmpty && !widget.notifier.isLoading
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: statements.length,
                    itemBuilder: (_, i) => _buildStatementCard(statements[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_rounded,
              size: 80, color: AppColors.textMuted.withAlpha(80)),
          const SizedBox(height: 16),
          const Text('No statements yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          const Text('Import a PDF bank statement to get started',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: widget.notifier.importPdf,
            icon: const Icon(Icons.upload_file_rounded, size: 20),
            label: const Text('Import Statement'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementCard(Statement statement) {
    final stats = widget.notifier.statementStats[statement.id];
    final lines = widget.notifier.loadedLines[statement.id] ?? [];
    final period =
        '${_dateFmt.format(statement.statementPeriodStart)} – ${_dateFmt.format(statement.statementPeriodEnd)}';
    final fileName = statement.filePath.split(r'\').last.split('/').last;
    final isCard = statement.source.toLowerCase().contains('visa') ||
        statement.source.toLowerCase().contains('mastercard');
    final isExpanded = _expandedIds.contains(statement.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          // ── Header row ──────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() {
              if (isExpanded) {
                _expandedIds.remove(statement.id);
              } else {
                _expandedIds.add(statement.id);
              }
            }),
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
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
                    child: Icon(
                      isCard
                          ? Icons.credit_card_rounded
                          : Icons.account_balance_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(statement.source,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(period,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text(fileName,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Total charges
                  if (stats != null) ...[
                    Text(
                      _fmtAmount(stats.totalChargeCents),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 10),
                    // Categorized / uncategorized chips
                    if (stats.uncategorized == 0)
                      _chip('${stats.categorized} categorized', AppColors.success)
                    else ...[
                      _chip('${stats.categorized} categorized', AppColors.success),
                      const SizedBox(width: 6),
                      _chip('${stats.uncategorized} uncategorized', AppColors.warning),
                    ],
                    const SizedBox(width: 8),
                  ],
                  // Expand / collapse arrow
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 18, color: AppColors.textMuted),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(statement),
                  ),
                ],
              ),
            ),
          ),
          // ── Expanded transaction rows ────────────────────────────────────
          if (isExpanded) ...[
            const Divider(height: 1),
            _buildSavedLinesTable(statement, lines),
          ],
        ],
      ),
    );
  }

  Widget _buildSavedLinesTable(Statement statement, List<StatementLine> lines) {
    if (lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('No transactions',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ),
      );
    }
    const s = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
      letterSpacing: 0.5,
    );
    return Column(
      children: [
        // Table header
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(
            children: [
              SizedBox(width: 92, child: Text('DATE', style: s)),
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
              Expanded(child: Text('NOTES', style: s)),
            ],
          ),
        ),
        const Divider(height: 1),
        // Rows
        ...lines.map((line) => _buildSavedLineRow(statement, line)),
      ],
    );
  }

  Widget _buildSavedLineRow(Statement statement, StatementLine line) {
    return _SavedLineRow(
      key: ValueKey(line.id),
      line: line,
      statement: statement,
      categoryButton: _buildSavedLineCategoryButton(statement, line),
      amountColor: _amountColor(line.amount),
      formattedAmount: _fmtAmount(line.amount),
      formattedDate: _shortDateFmt.format(line.date),
      onSaveNotes: (notes) =>
          widget.notifier.updateLineNotes(statement.id, line.id, notes),
    );
  }

  Widget _buildSavedLineCategoryButton(Statement statement, StatementLine line) {
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
                    color: _categoryDotColor(line.categoryId))),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_categoryLabel(line.categoryId),
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

  Future<void> _confirmDelete(Statement statement) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete statement?'),
        content: Text(
            'This will permanently delete "${statement.source}" and all its transactions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style:
                  TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await widget.notifier.deleteStatement(statement.id);
    }
  }

  // ── Import editor ────────────────────────────────────────────────────────

  Widget _buildEditor() {
    final pending = widget.notifier.pending;
    final ignoredCount = pending.where((t) => t.isIgnored).length;
    final savedCount = pending.length - ignoredCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.notifier.pendingSource ?? 'Import Statement'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Discard',
          onPressed: () => _confirmDiscard(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                '$savedCount of ${pending.length} transactions',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ),
          if (widget.notifier.isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: widget.notifier.saveStatement,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.notifier.error != null)
            _errorBanner(widget.notifier.error!),
          _buildTableHeader(),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: pending.length,
              itemBuilder: (_, i) => _buildRow(pending[i]),
            ),
          ),
          _buildSummaryBar(pending),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 34),
          const SizedBox(width: 92, child: Text('DATE', style: s)),
          const Expanded(
              child: Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('DESCRIPTION', style: s))),
          const SizedBox(
              width: 100,
              child: Text('AMOUNT', style: s, textAlign: TextAlign.right)),
          const SizedBox(width: 12),
          const SizedBox(width: 210, child: Text('CATEGORY', style: s)),
          const SizedBox(width: 8),
          const SizedBox(width: 160, child: Text('RECEIPT', style: s)),
        ],
      ),
    );
  }

  Widget _buildRow(ImportedTransaction tx) {
    final ignored = tx.isIgnored;
    final textColor = ignored ? AppColors.textMuted : AppColors.textPrimary;
    final textStyle = TextStyle(
      fontSize: 13,
      color: textColor,
      decoration: ignored ? TextDecoration.lineThrough : null,
      decorationColor: AppColors.textMuted,
    );

    return Container(
      color: ignored ? AppColors.surface.withAlpha(100) : Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Visibility toggle
                SizedBox(
                  width: 34,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: Icon(
                      ignored
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_outlined,
                      size: 15,
                      color: ignored
                          ? AppColors.textMuted
                          : AppColors.textMuted.withAlpha(100),
                    ),
                    tooltip: ignored ? 'Un-ignore' : 'Ignore',
                    onPressed: () => widget.notifier.setTransactionCategory(
                      tx.tempId,
                      ignored ? null : kIgnoredCategoryId,
                    ),
                  ),
                ),
                // Date
                SizedBox(
                  width: 92,
                  child: Text(_shortDateFmt.format(tx.date),
                      style: textStyle.copyWith(
                          color: ignored
                              ? AppColors.textMuted
                              : AppColors.textSecondary)),
                ),
                // Description
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(tx.description,
                        style: textStyle,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                // Amount
                SizedBox(
                  width: 100,
                  child: Text(
                    _fmtAmount(tx.amountCents),
                    style: textStyle.copyWith(
                      color: ignored
                          ? AppColors.textMuted
                          : _amountColor(tx.amountCents),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 12),
                // Category
                SizedBox(width: 210, child: _buildCategoryButton(tx)),
                const SizedBox(width: 8),
                // Receipt
                SizedBox(
                  width: 160,
                  child: tx.isMixed ? _buildReceiptButton(tx) : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 12, endIndent: 12),
        ],
      ),
    );
  }

  Widget _buildCategoryButton(ImportedTransaction tx) {
    final cats = widget.categoriesNotifier.flatList;
    return PopupMenuButton<String?>(
      tooltip: '',
      onSelected: (value) =>
          widget.notifier.setTransactionCategory(tx.tempId, value),
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
        const PopupMenuDivider(),
        PopupMenuItem<String?>(
          value: kMixedCategoryId,
          child: Row(children: const [
            Icon(Icons.receipt_long_rounded, size: 15, color: AppColors.accent),
            SizedBox(width: 10),
            Text('Mixed', style: TextStyle(fontSize: 13)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String?>(
          value: kIgnoredCategoryId,
          child: Row(children: const [
            Icon(Icons.visibility_off_rounded,
                size: 15, color: AppColors.textMuted),
            SizedBox(width: 10),
            Text('Ignore',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ]),
        ),
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
                    color: _categoryDotColor(tx.categoryId))),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_categoryLabel(tx.categoryId),
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

  Widget _buildReceiptButton(ImportedTransaction tx) {
    final linked = tx.receiptId != null;
    return InkWell(
      onTap: () => _pickReceipt(tx),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: linked
              ? AppColors.primary.withAlpha(30)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: linked ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              linked ? Icons.receipt_long_rounded : Icons.add_rounded,
              size: 14,
              color: linked ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                linked ? 'Receipt linked' : 'Select receipt',
                style: TextStyle(
                    fontSize: 12,
                    color: linked ? AppColors.primary : AppColors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar(List<ImportedTransaction> pending) {
    final ignored = pending.where((t) => t.isIgnored).length;
    final mixed = pending.where((t) => t.isMixed).length;
    final uncategorized =
        pending.where((t) => t.categoryId == null && !t.isIgnored).length;
    int totalCharges = 0;
    for (final t in pending) {
      if (!t.isIgnored && t.amountCents > 0) totalCharges += t.amountCents;
    }
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _chip('${pending.length} total', AppColors.textSecondary),
          if (ignored > 0) ...[
            const SizedBox(width: 8),
            _chip('$ignored ignored', AppColors.textMuted),
          ],
          if (mixed > 0) ...[
            const SizedBox(width: 8),
            _chip('$mixed mixed', AppColors.accent),
          ],
          if (uncategorized > 0) ...[
            const SizedBox(width: 8),
            _chip('$uncategorized uncategorized', AppColors.warning),
          ],
          const Spacer(),
          Text(
            'Total charges: ${_fmtAmount(totalCharges)}',
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
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
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.error))),
        ],
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard import?'),
        content: const Text('All unsaved changes will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Discard')),
        ],
      ),
    );
    if (ok == true) widget.notifier.discardImport();
  }
}

// ── Saved line row ────────────────────────────────────────────────────────

class _SavedLineRow extends StatefulWidget {
  final StatementLine line;
  final Statement statement;
  final Widget categoryButton;
  final Color amountColor;
  final String formattedAmount;
  final String formattedDate;
  final void Function(String?) onSaveNotes;

  const _SavedLineRow({
    super.key,
    required this.line,
    required this.statement,
    required this.categoryButton,
    required this.amountColor,
    required this.formattedAmount,
    required this.formattedDate,
    required this.onSaveNotes,
  });

  @override
  State<_SavedLineRow> createState() => _SavedLineRowState();
}

class _SavedLineRowState extends State<_SavedLineRow> {
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
  void didUpdateWidget(_SavedLineRow old) {
    super.didUpdateWidget(old);
    // Sync if the note was changed externally (e.g. reload), but only when
    // this field isn't currently being edited.
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

  @override
  Widget build(BuildContext context) {
    final uncategorized = widget.line.categoryId == null;
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
              SizedBox(
                width: 92,
                child: Text(
                  widget.formattedDate,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(widget.line.payee,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis),
                ),
              ),
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
              SizedBox(width: 210, child: widget.categoryButton),
              const SizedBox(width: 12),
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
                      borderSide:
                          const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: AppColors.border),
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

// ── Receipt picker dialog ─────────────────────────────────────────────────

class _ReceiptPickerDialog extends StatefulWidget {
  final StatementsNotifier notifier;
  final int amountCents;
  final DateTime date;
  final String? currentReceiptId;

  const _ReceiptPickerDialog({
    required this.notifier,
    required this.amountCents,
    required this.date,
    this.currentReceiptId,
  });

  @override
  State<_ReceiptPickerDialog> createState() => _ReceiptPickerDialogState();
}

class _ReceiptPickerDialogState extends State<_ReceiptPickerDialog> {
  List<ReceiptMatchData>? _matches;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final m = await widget.notifier
        .findMatchingReceipts(widget.amountCents, widget.date);
    if (mounted) setState(() => _matches = m);
  }

  String _fmtAmount(int? cents) {
    if (cents == null) return '—';
    return '\$${_currencyFmt.format(cents.abs() / 100.0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Select Receipt',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          'Transaction: ${_fmtAmount(widget.amountCents)}  ·  ${_dateFmt.format(widget.date)}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            // Body
            if (_matches == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_matches!.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_rounded,
                          size: 40, color: AppColors.textMuted),
                      SizedBox(height: 12),
                      Text('No matching receipts found',
                          style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary)),
                      SizedBox(height: 4),
                      Text(
                        'Verify receipts first, or check the amount.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _matches!.length,
                  itemBuilder: (_, i) => _buildTile(_matches![i]),
                ),
              ),
            const Divider(height: 1),
            // Footer
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (widget.currentReceiptId != null)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(''),
                      icon: const Icon(Icons.link_off_rounded, size: 14),
                      label: const Text('Unlink receipt'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.textMuted),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(ReceiptMatchData match) {
    final isCurrent = match.receipt.id == widget.currentReceiptId;
    final store = match.store?.name ?? 'Unknown Store';
    final total = _fmtAmount(match.receipt.total);
    final dateStr = match.receipt.dateTime_ != null
        ? _dateFmt.format(match.receipt.dateTime_!)
        : 'No date';
    final imagePath = match.image?.filePath;

    return InkWell(
      onTap: () => Navigator.of(context).pop(match.receipt.id),
      child: Container(
        decoration: BoxDecoration(
          color: isCurrent ? AppColors.primary.withAlpha(18) : null,
          border: Border(
            left: BorderSide(
              color: isCurrent ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 52,
                height: 52,
                child: (imagePath != null && File(imagePath).existsSync())
                    ? Image.file(File(imagePath), fit: BoxFit.cover)
                    : Container(
                        color: AppColors.surfaceBright,
                        child: const Icon(Icons.receipt_long_rounded,
                            size: 22, color: AppColors.textMuted),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(store,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      _matchBadge(match.isExactMatch),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 11, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(dateStr,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(width: 12),
                      const Icon(Icons.payments_rounded,
                          size: 11, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(total,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            isCurrent
                ? const Icon(Icons.check_circle_rounded,
                    size: 18, color: AppColors.primary)
                : const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _matchBadge(bool exact) {
    final color = exact ? AppColors.success : AppColors.warning;
    final label = exact ? 'Exact' : 'Near';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
