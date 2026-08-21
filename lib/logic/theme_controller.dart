import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._internal();
  ThemeController._internal();

  String _currentTheme = 'onyx';
  String get currentTheme => _currentTheme;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentTheme = prefs.getString('selected_layout_theme') ?? 'onyx';
    notifyListeners();
  }

  Future<void> setTheme(String theme) async {
    if (_currentTheme == theme) return;
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_layout_theme', theme);
    notifyListeners();
  }
}
