import 'dart:io';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:expense_tracker/page/common_expense.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui';

import '../main.dart';
import '../models/earning_expense.dart';

// ======================= MONTHLY PAGE ===========================
class MonthlyPage extends StatefulWidget {
  final Function(bool) onToggleTheme;
  final ThemeMode themeMode;
  final DateTime selectedMonth;
  final ValueChanged<DateTime> onMonthChanged;

  const MonthlyPage({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
    required this.selectedMonth,
    required this.onMonthChanged,
  });

  @override
  State<MonthlyPage> createState() => _MonthlyPageState();
}

class _MonthlyPageState extends State<MonthlyPage> {
  final Box<Expense> expenseBox = Hive.box<Expense>('expenses_box');
  final Box<Earning> earningBox = Hive.box<Earning>('earnings_box');
  String? _expandedExpenseId;

  late DateTime selectedMonth;
  MonthlyFilter _filter = MonthlyFilter.all;
  ExpenseStatusFilter _expenseStatusFilter = ExpenseStatusFilter.all;
  EarningStatusFilter _earningStatusFilter = EarningStatusFilter.all;

  @override
  void initState() {
    super.initState();
    selectedMonth = widget.selectedMonth;
  }

  @override
  void didUpdateWidget(covariant MonthlyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedMonth != widget.selectedMonth) {
      setState(() => selectedMonth = widget.selectedMonth);
    }
  }

  double get totalExpensesForMonth {
    return expenseBox.values
        .where(
          (e) =>
              e.date.year == selectedMonth.year &&
              e.date.month == selectedMonth.month,
        )
        .fold(0.0, (s, e) => s + e.amount);
  }

  double get totalEarningsBeforeReduce {
    return earningBox.values
        .where(
          (e) =>
              e.date.year == selectedMonth.year &&
              e.date.month == selectedMonth.month &&
              e.isReceived,
        )
        .fold(0.0, (s, e) => s + e.amount);
  }

  double get totalEarningsAfterReduce {
    final adjusted = totalEarningsBeforeReduce - totalAutoReducedAmount;
    return adjusted.clamp(0, double.infinity);
  }

  double get remainingBalance =>
      totalEarningsAfterReduce - totalExpensesForMonth;

  double displayedExpensesTotal(List<Expense> expenses) {
    return expenses.fold(0.0, (s, e) => s + e.amount);
  }

  double displayedEarningsTotal(List<Earning> earnings) {
    return earnings
        .where((e) => e.isReceived) // ✅ Only received ones
        .fold(0.0, (s, e) => s + e.amount);
  }

  double get totalAutoReducedAmount {
    double reduced = 0.0;

    for (final e in expenseBox.values) {
      if (e.autoReduceEnabled == true &&
          e.date.year == selectedMonth.year &&
          e.date.month == selectedMonth.month &&
          (e.dailyReduce ?? 0) > 0 &&
          (e.totalBudget ?? 0) > 0) {
        final totalDays = (e.totalBudget! / e.dailyReduce!).floor();

        // normalize to midnight
        final now = DateTime.now();
        final start = DateTime(e.date.year, e.date.month, e.date.day);

        // ✅ count all completed full days since start
        final diffDays = now.difference(start).inDays;
        final daysDeducted = min(max(diffDays, 0), totalDays);

        reduced += daysDeducted * e.dailyReduce!;
      }
    }

    return reduced;
  }

  void previousMonth() {
    final m = DateTime(selectedMonth.year, selectedMonth.month - 1);
    setState(() => selectedMonth = m);
    widget.onMonthChanged(selectedMonth);
  }

  void nextMonth() {
    final m = DateTime(selectedMonth.year, selectedMonth.month + 1);
    setState(() => selectedMonth = m);
    widget.onMonthChanged(selectedMonth);
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        selectedMonth = DateTime(picked.year, picked.month);
      });
      widget.onMonthChanged(selectedMonth);
    }
  }

  Future<void> exportCSV() async {
    final rows = <List<dynamic>>[];
    rows.add([
      'Type',
      'ID',
      'Title',
      'Amount',
      'Category/Source',
      'Date',
      'Note',
    ]);
    for (final e in expenseBox.values) {
      rows.add([
        'Expense',
        e.id,
        e.title,
        e.amount.toStringAsFixed(2),
        e.category,
        DateFormat.yMd().format(e.date),
        e.note,
      ]);
    }
    for (final e in earningBox.values) {
      rows.add([
        'Earning',
        e.id,
        e.title,
        e.amount.toStringAsFixed(2),
        e.source,
        DateFormat.yMd().format(e.date),
        e.note,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/transactions_export_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csv);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exported CSV to: ${file.path}')));
    }
  }

  void openAddEditSheet({
    Expense? expense,
    Earning? earning,
    bool isEarning = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AddEditSheet(
            expense: expense,
            earning: earning,
            isEarning: isEarning,
            onSaved: () {
              setState(() {});
            },
          ),
        ),
      ),
    );
  }

  void showAddChoiceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add, color: Colors.teal),
              title: const Text('Add Expense'),
              onTap: () {
                Navigator.pop(ctx);
                openAddEditSheet(isEarning: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments, color: Colors.green),
              title: const Text('Add Earning'),
              onTap: () {
                Navigator.pop(ctx);
                openAddEditSheet(isEarning: true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<Expense> _applyExpenseFilter(List<Expense> expenses) {
    switch (_filter) {
      case MonthlyFilter.all:
        return expenses;
      case MonthlyFilter.income:
        return [];
      case MonthlyFilter.expense:
        switch (_expenseStatusFilter) {
          case ExpenseStatusFilter.all:
            return expenses;
          case ExpenseStatusFilter.paid:
            // Expense + Paid: show both extra paid AND necessary paid
            return expenses.where((e) => e.isPaid).toList();
          case ExpenseStatusFilter.unpaid:
            // Expense + Unpaid: show both extra unpaid AND necessary unpaid
            return expenses.where((e) => !e.isPaid).toList();
          case ExpenseStatusFilter.extra:
            // Expense + Extra: show all extra expenses (both paid and unpaid)
            return expenses.where((e) => e.isExtra ?? false).toList();
          case ExpenseStatusFilter.necessary:
            // Expense + Necessary: show all necessary expenses (both paid and unpaid)
            return expenses.where((e) => !(e.isExtra ?? false)).toList();
        }
      case MonthlyFilter.extraExpense:
        switch (_expenseStatusFilter) {
          case ExpenseStatusFilter.all:
            // Extra + All: show all extra expenses
            return expenses.where((e) => e.isExtra ?? false).toList();
          case ExpenseStatusFilter.paid:
            // Extra + Paid: show ONLY extra paid
            return expenses.where((e) => (e.isExtra ?? false) && e.isPaid).toList();
          case ExpenseStatusFilter.unpaid:
            // Extra + Unpaid: show ONLY extra unpaid
            return expenses.where((e) => (e.isExtra ?? false) && !e.isPaid).toList();
          case ExpenseStatusFilter.extra:
            // Extra + Extra: same as All
            return expenses.where((e) => e.isExtra ?? false).toList();
          case ExpenseStatusFilter.necessary:
            // Extra + Necessary: no results
            return [];
        }
      case MonthlyFilter.necessaryExpense:
        switch (_expenseStatusFilter) {
          case ExpenseStatusFilter.all:
            // Necessary + All: show all necessary expenses
            return expenses.where((e) => !(e.isExtra ?? false)).toList();
          case ExpenseStatusFilter.paid:
            // Necessary + Paid: show ONLY necessary paid
            return expenses.where((e) => !(e.isExtra ?? false) && e.isPaid).toList();
          case ExpenseStatusFilter.unpaid:
            // Necessary + Unpaid: show ONLY necessary unpaid
            return expenses.where((e) => !(e.isExtra ?? false) && !e.isPaid).toList();
          case ExpenseStatusFilter.extra:
            // Necessary + Extra: no results
            return [];
          case ExpenseStatusFilter.necessary:
            // Necessary + Necessary: same as All
            return expenses.where((e) => !(e.isExtra ?? false)).toList();
        }
    }
  }

  List<Earning> _applyEarningFilter(List<Earning> earnings) {
    switch (_filter) {
      case MonthlyFilter.all:
        return earnings;
      case MonthlyFilter.income:
        switch (_earningStatusFilter) {
          case EarningStatusFilter.all:
            return earnings;
          case EarningStatusFilter.received:
            return earnings.where((e) => e.isReceived).toList();
          case EarningStatusFilter.pending:
            return earnings.where((e) => !e.isReceived).toList();
        }
      case MonthlyFilter.expense:
      case MonthlyFilter.extraExpense:
      case MonthlyFilter.necessaryExpense:
        return [];
    }
  }

  /// Use Common Expense (multi-select) from Monthly tab
  Future<void> _showCommonApplySheet() async {
    final box = Hive.box<CommonExpense>('common_expenses_box');
    final items = box.values.toList();

    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No Common Expenses found')));
      return;
    }

    final Set<CommonExpense> selected = {};

    final result = await showModalBottomSheet<List<CommonExpense>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final height = min(450.0, MediaQuery.of(ctx).size.height * 0.7);
        return SafeArea(
          child: SizedBox(
            height: height,
            child: StatefulBuilder(
              builder: (ctx2, setSt) {
                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Select Common Expenses to apply',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (c, i) {
                          final ce = items[i];
                          final isSel = selected.contains(ce);
                          return CheckboxListTile(
                            value: isSel,
                            title: Text(ce.title),
                            subtitle: Text(
                              '${ce.category} • ₹${ce.amount.toStringAsFixed(2)}',
                            ),
                            onChanged: (v) {
                              setSt(() {
                                if (v == true) {
                                  selected.add(ce);
                                } else {
                                  selected.remove(ce);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx2),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx2, selected.toList());
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (result == null || result.isEmpty) return;

    final expensesBox = Hive.box<Expense>('expenses_box');
    int added = 0;

    for (final ce in result) {
      final alreadyExists = expensesBox.values.any(
        (e) =>
            e.date.year == selectedMonth.year &&
            e.date.month == selectedMonth.month &&
            e.title == ce.title &&
            e.category == ce.category &&
            (e.amount - ce.amount).abs() < 0.01,
      );
      if (alreadyExists) continue;

      final id = '${DateTime.now().millisecondsSinceEpoch}_${ce.id}';
      final dateToUse = DateTime(selectedMonth.year, selectedMonth.month, 1);

      expensesBox.add(
        Expense(
          id: id,
          title: ce.title,
          amount: ce.amount,
          category: ce.category,
          date: dateToUse,
          note: ce.note,
          isPaid: false,
        ),
      );
      added++;
    }

    if (!mounted) return;

    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Applied $added common expense(s) for ${DateFormat.yMMMM().format(selectedMonth)}',
          ),
        ),
      );
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No new expenses added (already exist in this month)'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeMode == ThemeMode.dark;
    final theme = Theme.of(context);

    Widget buildFilterButton(MonthlyFilter f, IconData icon, String label) {
      final selected = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _filter = f;
              if (f == MonthlyFilter.expense || 
                  f == MonthlyFilter.extraExpense || 
                  f == MonthlyFilter.necessaryExpense) {
                _expenseStatusFilter = ExpenseStatusFilter.all;
              } else if (f == MonthlyFilter.income) {
                _earningStatusFilter = EarningStatusFilter.all;
              }
            });
          },
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(0, 36),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withOpacity(0.6),
            ),
            backgroundColor: selected
                ? theme.colorScheme.primary
                : Colors.transparent,
            foregroundColor: selected ? theme.colorScheme.onPrimary : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      );
    }

    Widget buildExpenseStatusButton(
      ExpenseStatusFilter status,
      IconData icon,
      String label,
    ) {
      final selected = _expenseStatusFilter == status;
      final colorBase = isDark ? Colors.cyanAccent : theme.colorScheme.primary;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _expenseStatusFilter = status;
            });
          },
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(0, 34),
            side: BorderSide(
              color: selected ? colorBase : colorBase.withOpacity(0.4),
            ),
            backgroundColor: selected
                ? colorBase.withOpacity(0.18)
                : Colors.transparent,
            foregroundColor: selected ? colorBase : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      );
    }

    Widget buildEarningStatusButton(
      EarningStatusFilter status,
      IconData icon,
      String label,
    ) {
      final selected = _earningStatusFilter == status;
      final isDark = widget.themeMode == ThemeMode.dark;
      final theme = Theme.of(context);
      final colorBase = isDark ? Colors.tealAccent : theme.colorScheme.primary;

      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              // Update the current filter
              _earningStatusFilter = status;
            });
          },
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(0, 34),
            side: BorderSide(
              color: selected ? colorBase : colorBase.withOpacity(0.4),
            ),
            backgroundColor: selected
                ? colorBase.withOpacity(0.18)
                : Colors.transparent,
            foregroundColor: selected ? colorBase : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: [
          Row(
            children: [
              Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              Switch(value: isDark, onChanged: (v) => widget.onToggleTheme(v)),
            ],
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _showCommonApplySheet,
            icon: const Icon(Icons.repeat, size: 18),
            label: const Text("Use Common"),
            style: TextButton.styleFrom(
              foregroundColor: isDark
                  ? Colors.cyanAccent
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: expenseBox.listenable(),
        builder: (context, Box<Expense> b, _) {
          final allExpenses =
              b.values
                  .where(
                    (e) =>
                        e.date.year == selectedMonth.year &&
                        e.date.month == selectedMonth.month,
                  )
                  .toList()
                ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

          return ValueListenableBuilder(
            valueListenable: earningBox.listenable(),
            builder: (context, Box<Earning> eb, __) {
              final allEarnings =
                  eb.values
                      .where(
                        (e) =>
                            e.date.year == selectedMonth.year &&
                            e.date.month == selectedMonth.month,
                      )
                      .toList()
                    ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

              final visibleExpenses = _applyExpenseFilter(allExpenses);
              final visibleEarnings = _applyEarningFilter(allEarnings);

              final displayedExpenses = displayedExpensesTotal(visibleExpenses);
              final displayedEarnings = displayedEarningsTotal(visibleEarnings);

              final paidCount = allExpenses.where((e) => e.isPaid).length;
              final progress = allExpenses.isEmpty
                  ? 0.0
                  : (paidCount / allExpenses.length);

              return SingleChildScrollView(
                child: Column(
                  children: [
                    // Month selector
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: previousMonth,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: _pickMonth,
                              child: Text(
                                DateFormat.yMMMM().format(selectedMonth),
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: nextMonth,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),

                    // Main filter buttons row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            buildFilterButton(
                              MonthlyFilter.all,
                              Icons.all_inclusive,
                              'All',
                            ),
                            buildFilterButton(
                              MonthlyFilter.income,
                              Icons.trending_up,
                              'Income',
                            ),
                            buildFilterButton(
                              MonthlyFilter.expense,
                              Icons.shopping_bag,
                              'Expense',
                            ),
                            buildFilterButton(
                              MonthlyFilter.extraExpense,
                              Icons.star,
                              'Extra',
                            ),
                            buildFilterButton(
                              MonthlyFilter.necessaryExpense,
                              Icons.check_circle,
                              'Necessary',
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) {
                        return SizeTransition(
                          sizeFactor: animation,
                          axisAlignment: -1.0,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: _filter == MonthlyFilter.income
                          ? Padding(
                              key: const ValueKey('earningSubFilterRow'),
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                              child: Center(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      buildEarningStatusButton(
                                        EarningStatusFilter.received,
                                        Icons.check_circle,
                                        'Received',
                                      ),
                                      buildEarningStatusButton(
                                        EarningStatusFilter.pending,
                                        Icons.pending_actions,
                                        'Pending',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('earningSubFilterEmpty'),
                              height: 0,
                            ),
                    ),

                    // Animated Paid/Unpaid row (only when Expense selected)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) {
                        return SizeTransition(
                          sizeFactor: animation,
                          axisAlignment: -1.0,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: _filter == MonthlyFilter.expense || 
                          _filter == MonthlyFilter.extraExpense || 
                          _filter == MonthlyFilter.necessaryExpense
                          ? Padding(
                              key: const ValueKey('subFilterRow'),
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                              child: Center(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Show different options based on main filter
                                      if (_filter == MonthlyFilter.expense) ...[
                                        buildExpenseStatusButton(
                                          ExpenseStatusFilter.paid,
                                          Icons.check_circle,
                                          'Paid',
                                        ),
                                        buildExpenseStatusButton(
                                          ExpenseStatusFilter.unpaid,
                                          Icons.pending_actions,
                                          'Unpaid',
                                        ),
                                      ] else if (_filter == MonthlyFilter.extraExpense) ...[
                                        buildExpenseStatusButton(
                                          ExpenseStatusFilter.all,
                                          Icons.all_inclusive,
                                          'All Extra',
                                        ),
                                        buildExpenseStatusButton(
                                          ExpenseStatusFilter.paid,
                                          Icons.check_circle,
                                          'Paid',
                                        ),
                                        buildExpenseStatusButton(
                                          ExpenseStatusFilter.unpaid,
                                          Icons.pending_actions,
                                          'Unpaid',
                                        ),
                                      ] else if (_filter == MonthlyFilter.necessaryExpense) ...[
                                        buildExpenseStatusButton(
                                          ExpenseStatusFilter.all,
                                          Icons.all_inclusive,
                                          'All Necessary',
                                        ),
                                        buildExpenseStatusButton(
                                          ExpenseStatusFilter.paid,
                                          Icons.check_circle,
                                          'Paid',
                                        ),
                                        buildExpenseStatusButton(
                                          ExpenseStatusFilter.unpaid,
                                          Icons.pending_actions,
                                          'Unpaid',
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('subFilterEmpty'),
                              height: 0,
                            ),
                    ),

                    // Remaining Balance Card
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Remaining Balance',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '₹${remainingBalance.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: remainingBalance >= 0
                                        ? Colors.green
                                        : Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: showAddChoiceSheet,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add'),
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Earnings Card
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Earnings',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '₹${displayedEarnings.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text('Total Month Earning'),
                              ],
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                openAddEditSheet(isEarning: true);
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Earn'),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 🔹 Show auto reduction info (below earnings card)
                    if (totalAutoReducedAmount > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Icon(
                              Icons.trending_down,
                              color: Colors.orangeAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Auto Reduced: ₹${totalAutoReducedAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Expenses Card
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text('Expenses'),
                                Text(
                                  '₹${displayedExpenses.toStringAsFixed(2)}',
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                const Text('Pending'),
                                Text(
                                  '₹${pendingTotalForVisible(allExpenses).toStringAsFixed(2)}',
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                Text('${allExpenses.length} items'),
                                SizedBox(
                                  width: 100,
                                  child: LinearProgressIndicator(
                                    value: progress,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Category Summary
                    if (allExpenses.isNotEmpty)
                      Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Category Summary',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              ...defaultCategories.map((cat) {
                                final catItems = allExpenses
                                    .where((e) => e.category == cat)
                                    .toList();
                                if (catItems.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final total = catItems.fold(
                                  0.0,
                                  (s, e) => s + e.amount,
                                );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        color:
                                            categoryColors[cat] ?? Colors.black,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(cat)),
                                      Text('₹${total.toStringAsFixed(2)}'),
                                      const SizedBox(width: 8),
                                      Text('(${catItems.length} items)'),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Expenses',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Expenses List (filtered & draggable)
                    if (visibleExpenses.isNotEmpty)
                      // ✅ Use shrinkWrap + NeverScrollableScrollPhysics so it works inside a scroll view
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles:
                            false, // ✅ removes the default drag icon
                        itemCount: visibleExpenses.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = visibleExpenses.removeAt(oldIndex);
                            visibleExpenses.insert(newIndex, item);
                          });

                          // Optional: Save the new order (Hive)
                          for (int i = 0; i < visibleExpenses.length; i++) {
                            final e = visibleExpenses[i];
                            e.sortIndex = i;
                            e.save();
                          }
                        },
                        itemBuilder: (ctx, i) {
                          final e = visibleExpenses[i];

                          // 🔢 Calculate daily reduction details
                          final bool hasAutoReduce =
                              (e.autoReduceEnabled ?? false) &&
                              (e.dailyReduce ?? 0) > 0 &&
                              (e.totalBudget ?? 0) > 0;
                          final int totalDays = hasAutoReduce
                              ? (e.totalBudget! / e.dailyReduce!).floor()
                              : 0;
                          final int diffDays = hasAutoReduce
                              ? DateTime.now()
                                    .difference(
                                      DateTime(
                                        e.date.year,
                                        e.date.month,
                                        e.date.day,
                                      ),
                                    )
                                    .inDays
                              : 0;

                          final int daysDeducted = hasAutoReduce
                              ? min(max(diffDays, 0), totalDays)
                              : 0;

                          final int remainingDays = hasAutoReduce
                              ? max(totalDays - daysDeducted, 0)
                              : 0;
                          final double percent = hasAutoReduce
                              ? (daysDeducted / totalDays * 100)
                                    .clamp(0, 100)
                                    .toDouble()
                              : 0.0;

                          return Column(
                            key: Key(
                              'expense_${e.id}_${e.date.millisecondsSinceEpoch}',
                            ),
                            children: [
                              // 🔹 TEMPORARY INFO CARD (appears above when tapping ℹ️)
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child:
                                    _expandedExpenseId == e.id && hasAutoReduce
                                    ? Padding(
                                        key: ValueKey('info_${e.id}'),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        child: _TemporaryInfoCard(
                                          title: "Auto Reduction Details",
                                          percent: percent,
                                          daysDeducted: daysDeducted,
                                          remainingDays: remainingDays,
                                          totalDays: totalDays,
                                          dailyReduce: e.dailyReduce!,
                                          onClose: () {
                                            setState(
                                              () => _expandedExpenseId = null,
                                            );
                                          },
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              // 🔹 MAIN CARD WITH CHECKBOX + DELETE
                              ReorderableDelayedDragStartListener(
                                key: Key('expense_${e.id}_${e.date.millisecondsSinceEpoch}'),
                                index: i,
                                child: Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: ListTile(
                                  onTap: () => openAddEditSheet(
                                    expense: e,
                                    isEarning: false,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        categoryColors[e.category] ??
                                        Colors.blueGrey,
                                    child: Icon(
                                      categoryIcons[e.category] ??
                                          Icons.money,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(
                                    e.title.isNotEmpty
                                        ? e.title
                                        : e.category,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat.yMMMd().format(e.date),
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '₹${e.amount.toStringAsFixed(2)}',
                                          ),
                                          const SizedBox(width: 8),
                                          // Pin/Extra expense toggle
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                e.isExtra = !(e.isExtra ?? false);
                                                e.save();
                                              });
                                            },
                                            child: Icon(
                                              (e.isExtra ?? false) ? Icons.star : Icons.star_border,
                                              color: (e.isExtra ?? false) ? Colors.amber : Colors.grey,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          if (hasAutoReduce) ...[
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  // Toggle info card visibility
                                                  _expandedExpenseId =
                                                      _expandedExpenseId == e.id
                                                      ? null
                                                      : e.id;
                                                });
                                              },
                                              child: const Icon(
                                                Icons.info_outline,
                                                color: Colors.blueAccent,
                                                size: 18,
                                              ),
                                            ),
                                          ],

                                          Checkbox(
                                            value: e.isPaid,
                                            onChanged: (val) {
                                              setState(() {
                                                e.isPaid = val ?? false;
                                                e.save();
                                              });
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.redAccent,
                                            ),
                                            onPressed: () async {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      title: const Text(
                                                        "Delete Expense?",
                                                      ),
                                                      content: const Text(
                                                        "This action cannot be undone.",
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                ctx,
                                                                false,
                                                              ),
                                                          child: const Text(
                                                            "Cancel",
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                ctx,
                                                                true,
                                                              ),
                                                          child: const Text(
                                                            "Delete",
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                              if (confirmed ?? false) {
                                                final deletedCopy = e
                                                    .copyWith();
                                                await e.delete();
                                                if (mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).hideCurrentSnackBar();
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: const Text(
                                                        'Expense deleted',
                                                      ),
                                                      action: SnackBarAction(
                                                        label: 'UNDO',
                                                        onPressed: () async {
                                                          final box =
                                                              Hive.box<Expense>(
                                                                'expenses_box',
                                                              );
                                                          await box.add(
                                                            deletedCopy,
                                                          );
                                                          setState(() {});
                                                        },
                                                      ),
                                                      duration: const Duration(
                                                        seconds: 4,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                ),
                              ),
                            ),
                            ],
                          );
                        },
                      ),

                    const SizedBox(height: 12),

                    // Earnings Section
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Earnings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (visibleEarnings.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'No earnings for this month',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),

                    if (visibleEarnings.isNotEmpty)
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: visibleEarnings.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = visibleEarnings.removeAt(oldIndex);
                            visibleEarnings.insert(newIndex, item);
                          });

                          // Save the new order (Hive)
                          for (int i = 0; i < visibleEarnings.length; i++) {
                            final e = visibleEarnings[i];
                            e.sortIndex = i;
                            e.save();
                          }
                        },
                        itemBuilder: (ctx, i) {
                          final ent = visibleEarnings[i];

                          return ReorderableDelayedDragStartListener(
                            key: Key('earning_${ent.id}_${ent.date.millisecondsSinceEpoch}'),
                            index: i,
                            child: Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                                onTap: () => openAddEditSheet(
                                  earning: ent,
                                  isEarning: true,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green,
                                  child: const Icon(
                                    Icons.payments,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  ent.title.isNotEmpty ? ent.title : ent.source,
                                ),
                                subtitle: Text(
                                  DateFormat.yMMMd().format(ent.date),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // ✅ Amount
                                    Text(
                                      '₹${ent.amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: ent.isReceived
                                            ? Colors.green
                                            : Colors.orangeAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // ✅ Received Toggle
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          ent.isReceived = !ent.isReceived;
                                          ent.save();
                                        });
                                      },
                                      icon: Icon(
                                        ent.isReceived
                                            ? Icons.check_circle
                                            : Icons.pending_actions,
                                        color: ent.isReceived
                                            ? Colors.green
                                            : Colors.orangeAccent,
                                        size: 26,
                                      ),
                                      tooltip: ent.isReceived
                                          ? 'Received'
                                          : 'Pending',
                                    ),

                                    const SizedBox(width: 8),

                                    // ✅ Delete Button
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () async {
                                        final confirmed = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                              "Delete Earning?",
                                            ),
                                            content: const Text(
                                              "This action cannot be undone.",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text("Cancel"),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text("Delete"),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed ?? false) {
                                          final deletedCopy = ent.copyWith();
                                          await ent.delete();
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: const Text(
                                                  'Earning deleted',
                                                ),
                                                action: SnackBarAction(
                                                  label: 'UNDO',
                                                  onPressed: () async {
                                                    final box =
                                                        Hive.box<Earning>(
                                                          'earnings_box',
                                                        );
                                                    await box.add(deletedCopy);
                                                    setState(() {});
                                                  },
                                                ),
                                                duration: const Duration(
                                                  seconds: 4,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                            ),
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showAddChoiceSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  double pendingTotalForVisible(List<Expense> allExpenses) {
    final unpaid = allExpenses
        .where((e) => !e.isPaid)
        .fold(0.0, (s, e) => s + e.amount);
    return unpaid;
  }
}

class MonthlyExpensesPage extends StatefulWidget {
  const MonthlyExpensesPage({super.key});

  @override
  State<MonthlyExpensesPage> createState() => _MonthlyExpensesPageState();
}

class _MonthlyExpensesPageState extends State<MonthlyExpensesPage> {
  late Box<Expense> _expenseBox;
  List<Expense> _expenses = [];

  @override
  void initState() {
    super.initState();
    _expenseBox = Hive.box<Expense>('expenses_box');
    _loadExpenses();
  }

  void _loadExpenses() {
    _expenses = _expenseBox.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // latest first
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Expenses')),
      body: _expenses.isEmpty
          ? const Center(child: Text('No expenses yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _expenses.length,
              itemBuilder: (context, index) {
                final e = _expenses[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          categoryColors[e.category] ?? Colors.blueGrey,
                      child: Icon(
                        categoryIcons[e.category] ?? Icons.money,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      e.title.isNotEmpty ? e.title : e.category,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${DateFormat.yMMMd().format(e.date)} • ₹${e.amount.toStringAsFixed(2)}'
                      '${e.isPaid ? " • Paid" : " • Unpaid"}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Expense?'),
                            content: const Text(
                              'Do you want to delete this expense?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm ?? false) {
                          await e.delete();
                          _loadExpenses();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Expense deleted')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _AutoReduceInfoCard extends StatefulWidget {
  final double dailyReduce;
  final int totalDays;
  final int daysDeducted;
  final int remainingDays;
  final double percent;

  const _AutoReduceInfoCard({
    required this.dailyReduce,
    required this.totalDays,
    required this.daysDeducted,
    required this.remainingDays,
    required this.percent,
  });

  @override
  State<_AutoReduceInfoCard> createState() => _AutoReduceInfoCardState();
}

class _AutoReduceInfoCardState extends State<_AutoReduceInfoCard> {
  final bool _showInfo = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '₹${widget.dailyReduce.toStringAsFixed(0)}/day',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${widget.percent.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTapDown: (details) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final pos = box.localToGlobal(Offset.zero);
                  final size = box.size;
                  final rect = Rect.fromLTWH(
                    pos.dx,
                    pos.dy,
                    size.width,
                    size.height,
                  );

                  // ✅ Use widget.<field> here
                  FloatingInfoOverlay.show(
                    context: context,
                    targetRect: rect,
                    title: "Auto Reduction Details",
                    percent: widget.percent,
                    daysDeducted: widget.daysDeducted,
                    remainingDays: widget.remainingDays,
                    totalDays: widget.totalDays,
                  );
                }
              },
              child: const Icon(
                Icons.info_outline,
                color: Colors.blueAccent,
                size: 18,
              ),
            ),
          ],
        ),

        // Optional inline AnimatedSwitcher (if you want inline info)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: _showInfo
              ? Padding(
                  key: const ValueKey("infoGlassCard"),
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Auto Reduction Details",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: widget.daysDeducted / widget.totalDays,
                                minHeight: 6,
                                backgroundColor: Colors.grey.withOpacity(0.3),
                                color: Colors.cyanAccent,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Deducted: ${widget.daysDeducted} days',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.greenAccent,
                                        fontSize: 12,
                                      ),
                                ),
                                Text(
                                  'Remaining: ${widget.remainingDays} days',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class FloatingInfoOverlay {
  static OverlayEntry? _currentEntry;

  static void show({
    required BuildContext context,
    required Rect targetRect,
    required String title,
    required double percent,
    required int daysDeducted,
    required int remainingDays,
    required int totalDays,
  }) {
    hide();

    final overlay = Overlay.of(context);

    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    const double popupHeight = 160;
    const double margin = 12;

    // Space above/below
    final spaceAbove = targetRect.top - padding.top - margin;
    final spaceBelow =
        size.height - targetRect.bottom - padding.bottom - margin;
    final bool showAbove = spaceAbove > popupHeight || spaceAbove > spaceBelow;

    // Calculate vertical placement
    double top = showAbove
        ? targetRect.top - popupHeight - margin
        : targetRect.bottom + margin;

    // Base popup width
    double popupWidth = targetRect.width;

    // Auto-shrink if popup is too wide
    if (popupWidth > size.width - (margin * 2)) {
      popupWidth = size.width - (margin * 2);
    }

    // Center horizontally by default
    double left = targetRect.left + (targetRect.width / 2) - (popupWidth / 2);

    // Auto-adjust if overflowing
    if (left < margin) {
      left = margin;
    } else if (left + popupWidth > size.width - margin) {
      // shift left if overflow right
      final overflow = (left + popupWidth) - (size.width - margin);
      left = (left - overflow).clamp(margin, size.width - popupWidth - margin);
    }

    // Clamp vertical position safely
    top = top.clamp(
      padding.top + margin,
      size.height - popupHeight - padding.bottom - margin,
    );

    _currentEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // Tap outside to close
          Positioned.fill(
            child: GestureDetector(
              onTap: hide,
              behavior: HitTestBehavior.opaque,
            ),
          ),
          // The popup itself
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            left: left,
            top: top,
            width: popupWidth,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: 1,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: daysDeducted / totalDays,
                              minHeight: 6,
                              backgroundColor: Colors.grey.withOpacity(0.3),
                              color: Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Deducted: $daysDeducted days',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'Remaining: $remainingDays days',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: hide,
                              child: const Text(
                                'Close',
                                style: TextStyle(color: Colors.cyanAccent),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_currentEntry!);
  }

  static void hide() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _TemporaryInfoCard extends StatelessWidget {
  final String title;
  final double percent;
  final int daysDeducted;
  final int remainingDays;
  final int totalDays;
  final double dailyReduce;
  final VoidCallback onClose;

  const _TemporaryInfoCard({
    required this.title,
    required this.percent,
    required this.daysDeducted,
    required this.remainingDays,
    required this.totalDays,
    required this.dailyReduce,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Title + Close Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onClose,
              ),
            ],
          ),

          const SizedBox(height: 6),

          // 🔹 Daily rate & percentage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₹${dailyReduce.toStringAsFixed(0)}/day',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${percent.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 🔹 Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: daysDeducted / totalDays,
              minHeight: 6,
              backgroundColor: Colors.grey.withOpacity(0.3),
              color: Colors.cyanAccent,
            ),
          ),

          const SizedBox(height: 8),

          // 🔹 Deducted / Remaining Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Deducted: $daysDeducted days',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
              Text(
                'Remaining: $remainingDays days',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
