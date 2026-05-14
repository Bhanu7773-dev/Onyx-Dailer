import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wavedialer/theme/app_theme.dart';
import 'package:wavedialer/screens/home_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/screens/startup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const OnyxDialerApp());
}

class OnyxDialerApp extends StatefulWidget {
  const OnyxDialerApp({Key? key}) : super(key: key);

  @override
  State<OnyxDialerApp> createState() => _OnyxDialerAppState();
}

class _OnyxDialerAppState extends State<OnyxDialerApp> {
  String? _startMode;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStartMode();
  }

  Future<void> _checkStartMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _startMode = prefs.getString('start_mode');
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: Colors.black),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
      ),
      child: MaterialApp(
        title: 'Onyx Dialer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: _startMode == null ? const StartupScreen() : const HomeScreen(),
      ),
    );
  }
}
