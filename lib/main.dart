import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wavedialer/theme/app_theme.dart';
import 'package:wavedialer/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/screens/startup_screen.dart';
import 'package:wavedialer/screens/call_screen.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

void main() {
  // 1. Minimum initialization to show the first frame
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Set UI mode without waiting
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const OnyxDialerApp());
}

class OnyxDialerApp extends StatefulWidget {
  const OnyxDialerApp({Key? key}) : super(key: key);

  @override
  State<OnyxDialerApp> createState() => _OnyxDialerAppState();
}

class _OnyxDialerAppState extends State<OnyxDialerApp> {
  StreamSubscription? _callSub;
  bool _isCallScreenVisible = false;
  bool _isLaunchedForCall = false;
  bool _isLoading = true;
  String? _startMode;
  
  String? _initialIncomingNumber;
  int? _initialIncomingState;
  String? _initialIncomingName;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Use a small delay to ensure the splash/first frame is fully rendered
    // before we start any async work that might compete for CPU.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _initialize();
    });
  }

  Future<void> _initialize() async {
    try {
      const channel = MethodChannel('dark.onyx.com/telecom_commands');
      
      // Parallelize only the most critical startup info
      final results = await Future.wait([
        channel.invokeMethod('isIncomingCallLaunch').catchError((_) => null),
        SharedPreferences.getInstance(),
      ]);

      final callDataRaw = results[0];
      final prefs = results[1] as SharedPreferences;
      
      final callData = callDataRaw != null ? Map<String, dynamic>.from(callDataRaw as Map) : null;
      final isIncoming = callData != null && callData['isIncoming'] == true;

      if (mounted) {
        setState(() {
          _isLaunchedForCall = isIncoming;
          _isCallScreenVisible = isIncoming; 
          _startMode = prefs.getString('start_mode');
          _isLoading = false;
          
          if (isIncoming) {
            _initialIncomingNumber = callData['number'] as String?;
            _initialIncomingState = callData['state'] as int?;
            _initialIncomingName = callData['name'] as String?;
          }
        });
        
        // Defer listener initialization slightly more
        Future.microtask(() => _initCallListener());
      }
    } catch (e) {
      debugPrint('Startup Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initCallListener() {
    _callSub = TelecomService.callStateStream.listen((data) {
      final state = data['state'] as int;
      final number = data['number'] as String;
      final name = data['name'] as String?;
      debugPrint('OnyxMain: Call State Update: $state for $number (name: $name)');

      // Handle all active states: 1=Dialing, 2=Ringing, 4=Active, 8=Select_Account, 9=Connecting
      if ((state == 1 || state == 2 || state == 4 || state == 8 || state == 9) && !_isCallScreenVisible) {
        _isCallScreenVisible = true;
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => CallScreen(
            initialNumber: number, 
            initialState: state,
            initialName: name,
            exitOnEnd: false,
          )),
        ).then((_) {
          _isCallScreenVisible = false;
        });
      }
      
      if (state == 7) {
        _isCallScreenVisible = false;
      }
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
      ),
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Onyx Dialer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: _isLoading 
            ? const Scaffold(backgroundColor: Colors.transparent)
            : (_isLaunchedForCall 
                ? CallScreen(
                    exitOnEnd: true,
                    initialNumber: _initialIncomingNumber,
                    initialState: _initialIncomingState,
                    initialName: _initialIncomingName,
                  ) 
                : (_startMode == null ? const StartupScreen() : const HomeScreen())),
      ),
    );
  }
}
