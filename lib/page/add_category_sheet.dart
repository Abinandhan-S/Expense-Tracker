import 'package:flutter/material.dart';
import '../services/category_service.dart';

class AddCategorySheet extends StatefulWidget {
  final Function(String)? onCategoryAdded;

  const AddCategorySheet({super.key, this.onCategoryAdded});

  @override
  State<AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<AddCategorySheet> {
  final _formKey = GlobalKey<FormState>();
  String _newCategoryName = '';
  IconData _selectedIcon = Icons.category;
  Color _selectedColor = Colors.grey;

  final List<IconData> _availableIcons = [
    Icons.category,
    Icons.restaurant,
    Icons.flight,
    Icons.shopping_cart,
    Icons.receipt_long,
    Icons.local_gas_station,
    Icons.home,
    Icons.favorite,
    Icons.more_horiz,
    Icons.school,
    Icons.sports_esports,
    Icons.healing,
    Icons.pets,
    Icons.work,
    Icons.commute,
  ];

  final List<Color> _availableColors = [
    Colors.grey,
    Colors.orange,
    Colors.blue,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.pink,
    Colors.green,
    Colors.indigo,
    Colors.brown,
  ];

  @override
  void initState() {
    super.initState();
    _selectedIcon = _availableIcons.first;
    _selectedColor = _availableColors.first;
  }

  void _addCategory() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    CategoryService.add(_newCategoryName, _selectedIcon, _selectedColor);

    if (widget.onCategoryAdded != null) {
      widget.onCategoryAdded!(_newCategoryName);
    }

    Navigator.pop(context); // Close sheet
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add New Category',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            TextFormField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Category Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              onSaved: (v) => _newCategoryName = v!.trim(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Icon:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _availableIcons.length,
                itemBuilder: (c, i) {
                  final icon = _availableIcons[i];
                  final isSelected = icon == _selectedIcon;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = icon),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue.withOpacity(0.2) : null,
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: Colors.blue)
                            : null,
                      ),
                      child: Icon(icon, color: isSelected ? Colors.blue : null),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Color:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _availableColors.length,
                itemBuilder: (c, i) {
                  final color = _availableColors[i];
                  final isSelected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: isSelected
                            ? [
                                const BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _addCategory,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Add Category',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
