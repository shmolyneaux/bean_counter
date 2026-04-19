import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bean_budget/core/theme/app_theme.dart';
import 'package:bean_budget/core/repositories/reports_repository.dart';
import 'package:bean_budget/features/reports/reports_notifier.dart';

class ReportsScreen extends StatefulWidget {
  final ReportsNotifier notifier;

  const ReportsScreen({super.key, required this.notifier});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
    widget.notifier.load();
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;

    if (notifier.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!notifier.hasData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 80,
                color: AppColors.textMuted.withAlpha(80),
              ),
              const SizedBox(height: 16),
              const Text(
                'No data yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Import statements to see spending reports',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BarChartSection(notifier: notifier),
          const Divider(height: 1, thickness: 0.5),
          Expanded(child: _CategoryBreakdown(notifier: notifier)),
        ],
      ),
    );
  }
}

// ─── Bar chart ───────────────────────────────────────────────────────────────

class _BarChartSection extends StatelessWidget {
  final ReportsNotifier notifier;

  const _BarChartSection({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final months = notifier.monthlyData;
    final maxCents =
        months.fold<int>(0, (m, e) => e.totalCents > m ? e.totalCents : m);

    const maxBarHeight = 110.0;
    const labelHeight = 20.0;
    const chartHeight = maxBarHeight + labelHeight + 8; // bar + gap + label

    final now = DateTime.now();

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'LAST 12 MONTHS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: months.map((m) {
                final isSelected = notifier.selectedYear == m.year &&
                    notifier.selectedMonth == m.month;
                final isCurrentMonth =
                    m.year == now.year && m.month == now.month;
                final proportion =
                    maxCents > 0 ? m.totalCents / maxCents : 0.0;
                final barHeight =
                    (proportion * maxBarHeight).clamp(m.totalCents > 0 ? 3.0 : 0.0, maxBarHeight);
                final label = DateFormat('MMM').format(DateTime(m.year, m.month));

                return Expanded(
                  child: GestureDetector(
                    onTap: () => notifier.selectMonth(m.year, m.month),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        children: [
                          // Bar area — bar grows from the bottom of this space
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                                width: double.infinity,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : m.totalCents > 0
                                          ? AppColors.primary.withAlpha(90)
                                          : Colors.transparent,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3),
                                  ),
                                  border: isCurrentMonth && !isSelected
                                      ? Border.all(
                                          color: AppColors.primary.withAlpha(120),
                                          width: 1,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Month label
                          SizedBox(
                            height: labelHeight,
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? AppColors.textPrimary
                                      : AppColors.textMuted,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Category breakdown ───────────────────────────────────────────────────────

class _CategoryBreakdown extends StatelessWidget {
  final ReportsNotifier notifier;

  const _CategoryBreakdown({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final year = notifier.selectedYear;
    final month = notifier.selectedMonth;

    if (year == null || month == null) {
      return const Center(
        child: Text(
          'Select a month to see breakdown',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    final monthTitle =
        DateFormat('MMMM yyyy').format(DateTime(year, month));
    final breakdown = notifier.categoryBreakdown;
    final totalCents =
        breakdown.fold<int>(0, (s, c) => s + c.amountCents);
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Text(
                monthTitle,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (notifier.isBreakdownLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  fmt.format(totalCents / 100),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        if (!notifier.isBreakdownLoading && breakdown.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No spending recorded this month',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          )
        else if (!notifier.isBreakdownLoading)
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: breakdown.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _CategoryRow(
                item: breakdown[i],
                totalCents: totalCents,
                fmt: fmt,
              ),
            ),
          )
        else
          const Expanded(child: SizedBox()),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final CategorySpend item;
  final int totalCents;
  final NumberFormat fmt;

  const _CategoryRow({
    required this.item,
    required this.totalCents,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(item.color);
    final proportion = totalCents > 0 ? item.amountCents / totalCents : 0.0;
    final pct = '${(proportion * 100).toStringAsFixed(1)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.categoryName,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              pct,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: Text(
                fmt.format(item.amountCents / 100),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: proportion,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}
