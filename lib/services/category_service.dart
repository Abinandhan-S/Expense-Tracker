import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/category.dart';
import '../utils/constants.dart';

class CategoryService {
  static const String boxName = 'categories_box';

  static Box<CategoryModel> get box {
    if (!Hive.isBoxOpen(boxName)) {
      throw HiveError(
        'Categories box not initialized. Call CategoryService.init() first.',
      );
    }
    return Hive.box<CategoryModel>(boxName);
  }

  static bool get isInitialized => Hive.isBoxOpen(boxName);

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<CategoryModel>(boxName);
    }
    await _ensureDefaults();
  }

  static Future<void> _ensureDefaults() async {
    final categoryBox = Hive.box<CategoryModel>(boxName);
    if (categoryBox.isNotEmpty) return;

    // Seed from the old hardcoded lists
    // mapped to CategoryModel
    for (final name in defaultCategories) {
      final icon = categoryIcons[name] ?? Icons.category;
      final color = categoryColors[name] ?? Colors.grey;

      final cat = CategoryModel(
        id: DateTime.now().millisecondsSinceEpoch.toString() + name,
        name: name,
        iconCodePoint: icon.codePoint,
        colorValue: color.value,
      );

      await categoryBox.add(cat);
    }
  }

  static List<CategoryModel> getAll() {
    if (!isInitialized) return [];
    return box.values.toList();
  }

  static Future<void> add(String name, IconData icon, Color color) async {
    final cat = CategoryModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      iconCodePoint: icon.codePoint,
      colorValue: color.value,
    );
    await box.add(cat);
  }

  static Future<void> delete(CategoryModel cat) async {
    await cat.delete();
  }

  // Helpers for UI
  static IconData getIcon(String categoryName) {
    if (!isInitialized) {
      return categoryIcons[categoryName] ?? Icons.category;
    }

    try {
      final cat = box.values.firstWhere((e) => e.name == categoryName);
      return IconData(cat.iconCodePoint, fontFamily: 'MaterialIcons');
    } catch (e) {
      // Fallback
      return categoryIcons[categoryName] ?? Icons.category;
    }
  }

  static Color getColor(String categoryName) {
    if (!isInitialized) {
      return categoryColors[categoryName] ?? Colors.grey;
    }

    try {
      final cat = box.values.firstWhere((e) => e.name == categoryName);
      return Color(cat.colorValue);
    } catch (e) {
      return categoryColors[categoryName] ?? Colors.grey;
    }
  }
}
