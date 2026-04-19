import 'package:flutter/foundation.dart';
import 'package:bean_budget/core/repositories/reports_repository.dart';

class ReportsNotifier extends ChangeNotifier {
  final ReportsRepository _repo;

  List<MonthlySpend> _monthlyData = [];
  List<CategorySpend> _categoryBreakdown = [];
  int? _selectedYear;
  int? _selectedMonth;
  bool _isLoading = false;
  bool _isBreakdownLoading = false;
  String? _error;

  ReportsNotifier(this._repo);

  List<MonthlySpend> get monthlyData => _monthlyData;
  List<CategorySpend> get categoryBreakdown => _categoryBreakdown;
  int? get selectedYear => _selectedYear;
  int? get selectedMonth => _selectedMonth;
  bool get isLoading => _isLoading;
  bool get isBreakdownLoading => _isBreakdownLoading;
  String? get error => _error;

  bool get hasData => _monthlyData.any((m) => m.totalCents > 0);

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _monthlyData = await _repo.getMonthlySpending();

      // Auto-select the most recent month that has data, or the current month.
      if (_selectedYear == null) {
        final nonEmpty =
            _monthlyData.where((m) => m.totalCents > 0).toList();
        final target =
            nonEmpty.isNotEmpty ? nonEmpty.last : _monthlyData.last;
        _selectedYear = target.year;
        _selectedMonth = target.month;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    if (_selectedYear != null && _selectedMonth != null) {
      await _loadBreakdown(_selectedYear!, _selectedMonth!);
    }
  }

  Future<void> selectMonth(int year, int month) async {
    if (_selectedYear == year && _selectedMonth == month) return;
    _selectedYear = year;
    _selectedMonth = month;
    notifyListeners();
    await _loadBreakdown(year, month);
  }

  Future<void> _loadBreakdown(int year, int month) async {
    _isBreakdownLoading = true;
    notifyListeners();
    try {
      _categoryBreakdown = await _repo.getCategoryBreakdown(year, month);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isBreakdownLoading = false;
      notifyListeners();
    }
  }
}
