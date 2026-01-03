// lib/main.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'models/earning_expense.dart';
import 'page/overview.dart';
import 'page/monthly_expense.dart';
import 'page/common_expense.dart';
import 'page/settings.dart';

// =============================================================
// MAIN INITIALIZATION
// =============================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(ExpenseAdapter());
  Hive.registerAdapter(EarningAdapter());
  Hive.registerAdapter(CommonExpenseAdapter());

  await Hive.openBox<Expense>('expenses_box');
  await Hive.openBox<Earning>('earnings_box');
  await Hive.openBox<CommonExpense>('common_expenses_box');
  await Hive.openBox('settings');

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
    if (daysSince <= 1) continue;

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
enum MonthlyFilter { all, income, expense }

enum ExpenseStatusFilter { all, paid, unpaid }

enum EarningStatusFilter { all, received, pending }

// ======================= ADD/EDIT SHEET =========================
class AddEditSheet extends StatefulWidget {
  final Expense? expense;
  final Earning? earning;
  final bool isEarning;
  final VoidCallback? onSaved;

  const AddEditSheet({
    super.key,
    this.expense,
    this.earning,
    this.isEarning = false,
    this.onSaved,
  });

  @override
  State<AddEditSheet> createState() => _AddEditSheetState();
}

class _AddEditSheetState extends State<AddEditSheet> {
  final _formKey = GlobalKey<FormState>();

  late String category;
  late bool isPaid;
  late String source;
  late DateTime date;

  late double totalBudget;
  late double dailyReduce;
  late bool autoReduceEnabled;

  late TextEditingController _titleController;
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  late TextEditingController _dateController;

  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();

    if (widget.isEarning) {
      final e = widget.earning;
      _titleController = TextEditingController(text: e?.title ?? 'Salary');
      _amountController = TextEditingController(
        text: e != null ? e.amount.toString() : '',
      );
      _noteController = TextEditingController(text: e?.note ?? '');
      source = e?.source ?? 'Salary';
      category = defaultCategories.first;
      isPaid = false;
      autoReduceEnabled = false;
      totalBudget = 0;
      dailyReduce = 0;
      date = e?.date ?? DateTime.now();
    } else {
      final e = widget.expense;
      _titleController = TextEditingController(text: e?.title ?? '');
      _amountController = TextEditingController(
        text: e != null ? e.amount.toString() : '',
      );
      _noteController = TextEditingController(text: e?.note ?? '');
      category = e?.category ?? defaultCategories.first;
      isPaid = e?.isPaid ?? false;
      autoReduceEnabled = e?.autoReduceEnabled ?? false;
      totalBudget = e?.totalBudget ?? (e?.amount ?? 0);
      dailyReduce = e?.dailyReduce ?? 0;
      source = 'Salary';
      date = e?.date ?? DateTime.now();
    }

    _dateController = TextEditingController(
      text: DateFormat.yMd().format(date),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _dateController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// ✅ APPLY COMMON EXPENSE (FIXED)
  void applyCommonExpense(CommonExpense ce) {
    setState(() {
      category = ce.category;
      _titleController.text = ce.title;
      _amountController.text = ce.amount.toString();
      _noteController.text = ce.note;
    });
  }

  void save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState!.save();

    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;
    final note = _noteController.text.trim();

    if (widget.isEarning) {
      final box = Hive.box<Earning>('earnings_box');
      if (widget.earning != null) {
        final e = widget.earning!;
        e
          ..title = title
          ..amount = amount
          ..source = source
          ..date = date
          ..note = note;
        e.save();
      } else {
        box.add(
          Earning(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: title,
            amount: amount,
            source: source,
            date: date,
            note: note,
          ),
        );
      }
    } else {
      final box = Hive.box<Expense>('expenses_box');

      if (widget.expense != null) {
        final e = widget.expense!;
        e
          ..title = title
          ..amount = amount
          ..category = category
          ..note = note
          ..isPaid = isPaid
          ..date = date
          ..autoReduceEnabled = autoReduceEnabled;
        e.save();
      } else {
        box.add(
          Expense(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: title,
            amount: amount,
            category: category,
            date: date,
            note: note,
            isPaid: isPaid,
            autoReduceEnabled: autoReduceEnabled,
          ),
        );
      }
    }

    widget.onSaved?.call();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isE = widget.isEarning;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isE ? 'Add / Edit Earning' : 'Add / Edit Expense',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              if (!isE)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.library_books),
                    label: const Text("Use Common Expense"),
                    onPressed: () async {
                      final selected =
                          await showModalBottomSheet<CommonExpense>(
                            context: context,
                            builder: (_) => const SelectCommonExpenseSheet(),
                          );
                      if (selected != null) applyCommonExpense(selected);
                    },
                  ),
                ),

              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: isE ? 'Title (optional)' : 'Title',
                ),
                validator: (v) =>
                    (!isE && (v == null || v.isEmpty)) ? 'Required' : null,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) =>
                    v == null || double.tryParse(v) == null ? 'Invalid' : null,
              ),
              const SizedBox(height: 10),

              if (!isE)
                DropdownButtonFormField<String>(
                  value: category,
                  items: defaultCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => category = v!),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),

              const SizedBox(height: 10),

              TextFormField(
                controller: _dateController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      date = picked;
                      _dateController.text = DateFormat.yMd().format(picked);
                    });
                  }
                },
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note'),
              ),

              if (!isE)
                SwitchListTile(
                  value: isPaid,
                  title: const Text('Paid'),
                  onChanged: (v) => setState(() => isPaid = v),
                ),

              const SizedBox(height: 20),
              ElevatedButton(onPressed: save, child: const Text('Save')),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
