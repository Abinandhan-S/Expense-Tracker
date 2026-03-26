import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models/earning_expense.dart';

import '../services/category_service.dart';
import 'common_expense.dart';
import 'add_category_sheet.dart';

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
  late bool isReceived;
  late String source;
  late DateTime date;

  late double totalBudget;
  late double dailyReduce;
  late bool autoReduceEnabled;
  late bool isExtra;

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
      isReceived = e?.isReceived ?? false;
      category = CategoryService.getAll().isNotEmpty
          ? CategoryService.getAll().first.name
          : 'Others';
      isPaid = false;
      autoReduceEnabled = false;
      totalBudget = 0;
      dailyReduce = 0;
      isExtra = false;
      source = e?.source ?? 'Salary';
      date = e?.date ?? DateTime.now();
    } else {
      final e = widget.expense;
      _titleController = TextEditingController(text: e?.title ?? '');
      _amountController = TextEditingController(
        text: e != null ? e.amount.toString() : '',
      );
      _noteController = TextEditingController(text: e?.note ?? '');
      category =
          e?.category ??
          (CategoryService.getAll().isNotEmpty
              ? CategoryService.getAll().first.name
              : 'Others');
      isPaid = e?.isPaid ?? false;
      autoReduceEnabled = e?.autoReduceEnabled ?? false;
      totalBudget = e?.totalBudget ?? (e?.amount ?? 0);
      dailyReduce = e?.dailyReduce ?? 0;
      isExtra = e?.isExtra ?? false;
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
          ..note = note
          ..isReceived = isReceived;
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
            isReceived: isReceived,
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
          ..autoReduceEnabled = autoReduceEnabled
          ..isExtra = isExtra;
        e.save();
      } else {
        // Get the next available sortIndex for this month
        final monthExpenses = box.values
            .where(
              (e) => e.date.year == date.year && e.date.month == date.month,
            )
            .toList();
        final maxSortIndex = monthExpenses.isEmpty
            ? 0
            : monthExpenses
                      .map((e) => e.sortIndex)
                      .reduce((a, b) => a > b ? a : b) +
                  1;

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
            sortIndex: maxSortIndex,
            isExtra: isExtra,
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

              if (isE)
                TextFormField(
                  initialValue: source,
                  decoration: const InputDecoration(labelText: 'Source'),
                  onChanged: (v) => source = v.trim(),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
              if (isE) const SizedBox(height: 10),

              if (!isE)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('category_dropdown_$category'),
                        value: category,
                        items: CategoryService.getAll()
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.name,
                                child: Text(c.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => category = v!),
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (ctx) => AddCategorySheet(
                            onCategoryAdded: (newCatName) {
                              setState(() {
                                category = newCatName;
                              });
                            },
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Add New Category',
                    ),
                  ],
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

              if (!isE)
                SwitchListTile(
                  value: isExtra,
                  title: Row(
                    children: [
                      Icon(Icons.star, size: 18, color: Colors.amber),
                      const SizedBox(width: 8),
                      const Text('Extra Expense'),
                    ],
                  ),
                  subtitle: const Text('Mark as non-essential expense'),
                  onChanged: (v) => setState(() => isExtra = v),
                ),

              if (isE)
                SwitchListTile(
                  value: isReceived,
                  title: const Text('Received'),
                  onChanged: (v) => setState(() => isReceived = v),
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
