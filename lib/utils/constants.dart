import 'package:flutter/material.dart';

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
