import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

// =============================================================
// COMMON EXPENSE MODEL + PAGE
// =============================================================
class CommonExpense extends HiveObject {
  CommonExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.note,
  });

  String id;
  String title;
  double amount;
  String category;
  String note;
}

class CommonExpenseAdapter extends TypeAdapter<CommonExpense> {
  @override
  final int typeId = 99;
  @override
  CommonExpense read(BinaryReader reader) {
    return CommonExpense(
      id: reader.readString(),
      title: reader.readString(),
      amount: reader.readDouble(),
      category: reader.readString(),
      note: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, CommonExpense obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeDouble(obj.amount);
    writer.writeString(obj.category);
    writer.writeString(obj.note);
  }
}

class CommonExpensePage extends StatefulWidget {
  const CommonExpensePage({super.key});
  @override
  State<CommonExpensePage> createState() => _CommonExpensePageState();
}

class _CommonExpensePageState extends State<CommonExpensePage> {
  final Box<CommonExpense> commonBox = Hive.box<CommonExpense>(
    'common_expenses_box',
  );

  void openAddEdit({CommonExpense? item}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: AddCommonExpenseSheet(
          item: item,
          onSaved: () => setState(() {}),
        ),
      ),
    );
  }

  double get total => commonBox.values.fold(0.0, (s, e) => s + e.amount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Common Expenses')),
      body: ValueListenableBuilder(
        valueListenable: commonBox.listenable(),
        builder: (context, Box<CommonExpense> box, _) {
          final items = box.values.toList();
          if (items.isEmpty) {
            return const Center(child: Text("No common expenses yet"));
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Total: ₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              ...items.map(
                (e) => Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.repeat),
                    title: Text(e.title),
                    subtitle: Text('${e.category} • ${e.note}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('₹${e.amount.toStringAsFixed(2)}'),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await e.delete();
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    onTap: () => openAddEdit(item: e),
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openAddEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// =============================================================
// CONSTANTS & MODELS
// =============================================================
const List<String> defaultCategories = [
  'Food',
  'Travel',
  'Shopping',
  'Bills',
  'Fuel',
  'Rent',
  'Life',
  'Others',
];

const Map<String, IconData> categoryIcons = {
  'Food': Icons.restaurant,
  'Travel': Icons.flight,
  'Shopping': Icons.shopping_cart,
  'Bills': Icons.receipt_long,
  'Fuel': Icons.local_gas_station,
  'Rent': Icons.home,
  'Life': Icons.favorite,
  'Others': Icons.more_horiz,
};

const Map<String, Color> categoryColors = {
  'Food': Colors.orange,
  'Travel': Colors.blue,
  'Shopping': Colors.purple,
  'Bills': Colors.grey,
  'Fuel': Colors.red,
  'Rent': Colors.teal,
  'Life': Colors.pink,
  'Others': Colors.green,
};

class AddCommonExpenseSheet extends StatefulWidget {
  final CommonExpense? item;
  final VoidCallback onSaved;
  const AddCommonExpenseSheet({super.key, this.item, required this.onSaved});

  @override
  State<AddCommonExpenseSheet> createState() => _AddCommonExpenseSheetState();
}

class _AddCommonExpenseSheetState extends State<AddCommonExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  late String title;
  late double amount;
  late String category;
  late String note;

  @override
  void initState() {
    super.initState();
    title = widget.item?.title ?? '';
    amount = widget.item?.amount ?? 0;
    category = widget.item?.category ?? defaultCategories.first;
    note = widget.item?.note ?? '';
  }

  void save() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final box = Hive.box<CommonExpense>('common_expenses_box');
    if (widget.item != null) {
      final e = widget.item!;
      e.title = title;
      e.amount = amount;
      e.category = category;
      e.note = note;
      e.save();
    } else {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      box.add(
        CommonExpense(
          id: id,
          title: title,
          amount: amount,
          category: category,
          note: note,
        ),
      );
    }
    widget.onSaved();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Text(
                "Add / Edit Common Expense",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                onSaved: (v) => title = v ?? '',
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: amount > 0 ? amount.toString() : '',
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) =>
                    v == null || double.tryParse(v) == null ? 'Invalid' : null,
                onSaved: (v) => amount = double.tryParse(v ?? '0') ?? 0,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: category,
                items: defaultCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => category = v!),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: note,
                decoration: const InputDecoration(labelText: 'Note'),
                onSaved: (v) => note = v ?? '',
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}

class SelectCommonExpenseSheet extends StatelessWidget {
  const SelectCommonExpenseSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<CommonExpense>('common_expenses_box');
    final items = box.values.toList();

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "No Common Expenses available. Add some in the Common tab.",
        ),
      );
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              "Select a Common Expense to reuse",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...items.map(
            (e) => ListTile(
              leading: const Icon(Icons.repeat),
              title: Text(e.title),
              subtitle: Text('${e.category} • ₹${e.amount.toStringAsFixed(2)}'),
              onTap: () => Navigator.pop(context, e),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
