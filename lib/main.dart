// lib/main.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

import 'models/earning_expense.dart';
import 'models/category.dart';
import 'services/category_service.dart';
import 'page/overview.dart';
import 'page/monthly_expense.dart';
import 'page/common_expense.dart';
import 'page/settings.dart';

// =============================================================
// HELPER: INITIALIZE SORT INDEX FOR MIGRATION
// =============================================================
Future<void> initializeSortIndexForExistingExpenses() async {
  final expenseBox = Hive.box<Expense>('expenses_box');

  // Group expenses by month
  final Map<String, List<Expense>> expensesByMonth = {};

  for (final expense in expenseBox.values) {
    final monthKey = '${expense.date.year}_${expense.date.month}';
    expensesByMonth.putIfAbsent(monthKey, () => []).add(expense);
  }

  // Initialize sortIndex for each month's expenses
  for (final entry in expensesByMonth.entries) {
    final expenses = entry.value;

    // Sort by current sortIndex (if any) or by date as fallback
    expenses.sort((a, b) {
      if (a.sortIndex != b.sortIndex) {
        return a.sortIndex.compareTo(b.sortIndex);
      }
      return a.date.compareTo(b.date);
    });

    // Assign proper sortIndex values
    for (int i = 0; i < expenses.length; i++) {
      if (expenses[i].sortIndex != i) {
        expenses[i].sortIndex = i;
        await expenses[i].save();
      }
    }
  }
}

Future<void> initializeSortIndexForExistingEarnings() async {
  final earningBox = Hive.box<Earning>('earnings_box');

  // Group earnings by month
  final Map<String, List<Earning>> earningsByMonth = {};

  for (final earning in earningBox.values) {
    final monthKey = '${earning.date.year}_${earning.date.month}';
    earningsByMonth.putIfAbsent(monthKey, () => []).add(earning);
  }

  // Initialize sortIndex for each month's earnings
  for (final entry in earningsByMonth.entries) {
    final earnings = entry.value;

    // Sort by current sortIndex (if any) or by date as fallback
    earnings.sort((a, b) {
      if (a.sortIndex != b.sortIndex) {
        return a.sortIndex.compareTo(b.sortIndex);
      }
      return a.date.compareTo(b.date);
    });

    // Assign proper sortIndex values
    for (int i = 0; i < earnings.length; i++) {
      if (earnings[i].sortIndex != i) {
        earnings[i].sortIndex = i;
        await earnings[i].save();
      }
    }
  }
}

// =============================================================
// MAIN INITIALIZATION
// =============================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Hive.initFlutter();

  Hive.registerAdapter(ExpenseAdapter());
  Hive.registerAdapter(EarningAdapter());
  Hive.registerAdapter(CommonExpenseAdapter());
  Hive.registerAdapter(CategoryModelAdapter());

  // Try to open boxes, clear corrupted data if typeId error occurs
  try {
    await Hive.openBox<Expense>('expenses_box');
    await Hive.openBox<Earning>('earnings_box');
    await Hive.openBox<CommonExpense>('common_expenses_box');
    await CategoryService.init(); // Opens categories_box and seeds
    await Hive.openBox('settings');
  } catch (e) {
    // If there's any Hive-related error, clear the data and retry
    if (e.toString().contains('typeId') ||
        e.toString().contains('Null') ||
        e.toString().contains('type cast')) {
      print('Hive data corruption detected: ${e.toString()}');
      print('Clearing corrupted data boxes...');

      try {
        await Hive.deleteBoxFromDisk('expenses_box');
      } catch (deleteError) {
        print('Failed to delete expenses_box: ${deleteError.toString()}');
      }

      try {
        await Hive.deleteBoxFromDisk('earnings_box');
      } catch (deleteError) {
        print('Failed to delete earnings_box: ${deleteError.toString()}');
      }

      try {
        await Hive.deleteBoxFromDisk('common_expenses_box');
      } catch (deleteError) {
        print(
          'Failed to delete common_expenses_box: ${deleteError.toString()}',
        );
      }

      try {
        await Hive.deleteBoxFromDisk('settings');
      } catch (deleteError) {
        print('Failed to delete settings box: ${deleteError.toString()}');
      }

      print('Retrying to open boxes after clearing...');
      await Hive.openBox<Expense>('expenses_box');
      await Hive.openBox<Earning>('earnings_box');
      await Hive.openBox<CommonExpense>('common_expenses_box');
      await CategoryService.init(); // Opens categories_box and seeds
      await Hive.openBox('settings');
    } else {
      throw Exception('Hive initialization error: ${e.toString()}');
    }
  }

  // Initialize sortIndex for existing expenses that don't have one
  await initializeSortIndexForExistingExpenses();

  // Initialize sortIndex for existing earnings that don't have one
  await initializeSortIndexForExistingEarnings();

  await ensureRecurringSalaryFilled();
  runApp(const ExpenseTrackerApp());
}

// =============================================================
// HELPER: RECURRING SALARY
// =============================================================
Future<void> ensureRecurringSalaryFilled() async {
  final settings = Hive.box('settings');
  final enabled =
      settings.get('recurring_enabled', defaultValue: false) as bool;
  final amount = (settings.get('recurring_amount', defaultValue: 0.0) as num)
      .toDouble();
  final lastAddedStr =
      settings.get('recurring_last_added', defaultValue: '') as String;

  if (!enabled || amount <= 0) return;

  DateTime now = DateTime.now();
  DateTime lastAdded;
  if (lastAddedStr.isEmpty) {
    lastAdded = DateTime(1970, 1);
  } else {
    final parts = lastAddedStr.split('-');
    lastAdded = DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  DateTime cursor = DateTime(lastAdded.year, lastAdded.month + 1);
  final earningsBox = Hive.box<Earning>('earnings_box');
  while (!isSameMonthOrAfter(cursor, now.add(const Duration(days: 1)))) {
    final exists = earningsBox.values.any(
      (e) =>
          e.source == 'Salary' &&
          e.date.year == cursor.year &&
          e.date.month == cursor.month,
    );
    if (!exists) {
      final id =
          '${DateTime.now().millisecondsSinceEpoch}_${cursor.toIso8601String()}';
      earningsBox.add(
        Earning(
          id: id,
          title: 'Salary',
          amount: amount,
          source: 'Salary',
          date: DateTime(cursor.year, cursor.month, 1),
          note: 'Recurring Salary',
        ),
      );
    }
    settings.put(
      'recurring_last_added',
      '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}',
    );
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
}

bool isSameMonthOrAfter(DateTime a, DateTime b) {
  if (a.year > b.year) return true;
  if (a.year == b.year && a.month >= b.month) return true;
  return false;
}

// =============================================================
// HELPER: AUTO DAILY REDUCTION FOR EXPENSES (UTC-BASED)
// =============================================================
DateTime _stripLocalDate(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

Future<void> applyDailyReductions() async {
  final expenseBox = Hive.box<Expense>('expenses_box');
  final todayLocalDate = _stripLocalDate(DateTime.now());

  for (final e in expenseBox.values) {
    if (!(e.autoReduceEnabled == true &&
        (e.dailyReduce ?? 0) > 0 &&
        e.amount > 0)) {
      continue;
    }

    // Use existing field, but as LOCAL date
    final last = e.lastReducedDateUtc != null
        ? _stripLocalDate(e.lastReducedDateUtc!)
        : _stripLocalDate(e.date);

    final daysSince = todayLocalDate.difference(last).inDays;

    // ✅ Skip today – only reduce for days before today
    if (daysSince == 0) continue;

    final missedDays = daysSince;
    final reduction = e.dailyReduce! * missedDays;

    e.amount = max(0, e.amount - reduction);
    e.lastReducedDateUtc = todayLocalDate; // now storing local date here
    e.reducedDaysCount = (e.reducedDaysCount ?? 0) + missedDays;

    await e.save();
  }
}

// =============================================================
// MAIN APP SHELL
// =============================================================
class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});
  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void toggleTheme(bool dark) {
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.teal.shade50,
          selectedItemColor: Colors.teal.shade700,
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.grey.shade900,
          selectedItemColor: Colors.cyanAccent,
          unselectedItemColor: Colors.grey,
        ),
      ),
      home: MainShell(onToggleTheme: toggleTheme, themeMode: _themeMode),
    );
  }
}

// =============================================================
// MAIN NAVIGATION SHELL
// =============================================================
class MainShell extends StatefulWidget {
  final Function(bool) onToggleTheme;
  final ThemeMode themeMode;
  const MainShell({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  DateTime selectedMonth = DateTime.now();

  void _onItemTapped(int idx) => setState(() => _selectedIndex = idx);

  @override
  Widget build(BuildContext context) {
    final pages = [
      MonthlyPage(
        onToggleTheme: widget.onToggleTheme,
        themeMode: widget.themeMode,
        selectedMonth: selectedMonth,
        onMonthChanged: (dt) => setState(() => selectedMonth = dt),
      ),
      OverviewPage(
        selectedMonth: selectedMonth,
        onMonthSelected: (dt) {
          setState(() {
            selectedMonth = dt;
            _selectedIndex = 0; // switch to Monthly tab
          });
        },
      ),
      const CommonExpensePage(),
      SettingsPage(
        onToggleTheme: widget.onToggleTheme,
        themeMode: widget.themeMode,
      ),
    ];

    return Scaffold(
      body: pages[_selectedIndex],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: 'Monthly',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Common'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ======================= FILTER ENUMS ===========================
enum MonthlyFilter { all, income, expense, extraExpense, necessaryExpense }

enum ExpenseStatusFilter { all, paid, unpaid, extra, necessary }

enum EarningStatusFilter { all, received, pending }

// AddEditSheet moved to lib/page/add_edit_sheet.dart
