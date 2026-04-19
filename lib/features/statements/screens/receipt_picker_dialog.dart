import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/repositories/statement_repository.dart';
import 'package:bean_budget/features/statements/statements_notifier.dart';

final stmtDateFmt = DateFormat('MMM d, yyyy');
final stmtCurrencyFmt = NumberFormat('#,##0.00');

class ReceiptPickerDialog extends StatefulWidget {
  final StatementsNotifier notifier;
  final int amountCents;
  final DateTime date;
  final String? currentReceiptId;
  final bool showNoMatch;

  const ReceiptPickerDialog({
    super.key,
    required this.notifier,
    required this.amountCents,
    required this.date,
    this.currentReceiptId,
    this.showNoMatch = false,
  });

  @override
  State<ReceiptPickerDialog> createState() => _ReceiptPickerDialogState();
}

class _ReceiptPickerDialogState extends State<ReceiptPickerDialog> {
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
    return '\$${stmtCurrencyFmt.format(cents.abs() / 100.0)}';
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
                          'Transaction: ${_fmtAmount(widget.amountCents)}  ·  ${stmtDateFmt.format(widget.date)}',
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
                  if (widget.showNoMatch)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop('__no_match__'),
                      icon: const Icon(Icons.do_not_disturb_rounded, size: 14),
                      label: const Text('No match'),
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
        ? stmtDateFmt.format(match.receipt.dateTime_!)
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
