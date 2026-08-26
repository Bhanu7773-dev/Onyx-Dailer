import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._internal();
  ThemeController._internal();

  String _currentTheme = 'onyx';
  String get currentTheme => _currentTheme;

  // 'dot' = NothingFont (dot-matrix), 'serif' = NotoSerifFont
  String _nothingFont = 'dot';
  String get nothingFont => _nothingFont;

  /// The active font family name for the Nothing theme.
  String get nothingFontFamily =>
      _nothingFont == 'serif' ? 'NotoSerifFont' : 'NothingFont';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentTheme = prefs.getString('selected_layout_theme') ?? 'onyx';
    _nothingFont  = prefs.getString('nothing_font') ?? 'dot';
    notifyListeners();
  }

  Future<void> setTheme(String theme) async {
    if (_currentTheme == theme) return;
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_layout_theme', theme);
    notifyListeners();
  }

  Future<void> setNothingFont(String font) async {
    if (_nothingFont == font) return;
    _nothingFont = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nothing_font', font);
    notifyListeners();
  }
}
