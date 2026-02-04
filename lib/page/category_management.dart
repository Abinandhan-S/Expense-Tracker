import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/category.dart';
import '../services/category_service.dart';
import 'add_category_sheet.dart';

class CategoryManagementPage extends StatefulWidget {
  const CategoryManagementPage({super.key});

  @override
  State<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends State<CategoryManagementPage> {
  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const AddCategorySheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add),
      ),
      body: ValueListenableBuilder(
        valueListenable: CategoryService.box.listenable(),
        builder: (context, Box<CategoryModel> box, _) {
          final items = box.values.toList();
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (c, i) => const Divider(),
            itemBuilder: (c, i) {
              final cat = items[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(cat.colorValue).withOpacity(0.2),
                  child: Icon(
                    IconData(cat.iconCodePoint, fontFamily: 'MaterialIcons'),
                    color: Color(cat.colorValue),
                  ),
                ),
                title: Text(cat.name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    // Confirm dialog? For now direct delete
                    // Warning: Deleting category in use?
                    // Expenses store String category, so deleting here won't break existing expenses
                    // but they will lose their icon/color mapping if I rely on this list only.
                    CategoryService.delete(cat);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
