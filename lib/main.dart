import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wavedialer/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavedialer/services/telecom_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:wavedialer/logic/theme_controller.dart';
import 'package:wavedialer/logic/theme_router.dart';

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

class _OnyxDialerAppState extends State<OnyxDialerApp> with WidgetsBindingObserver {
  StreamSubscription? _callSub;
  bool _isCallScreenVisible = false;
  bool _isLaunchedForCall = false;
  bool _isLoading = true;
  String? _startMode;
  
  String? _initialIncomingNumber;
  int? _initialIncomingState;
  String? _initialIncomingName;
  int _initialIncomingSeconds = 0;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeController.instance.addListener(_onThemeChange);
    // Explicitly ensure proximity sensor screen off is released when app starts
    ProximitySensor.setProximityScreenOff(false);

    // Use a small delay to ensure the splash/first frame is fully rendered
    // before we start any async work that might compete for CPU.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _initialize();
    });
  }

  void _onThemeChange() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.inactive) {
      if (!_isCallScreenVisible) {
        ProximitySensor.setProximityScreenOff(false);
      }
    }
  }

  Future<void> _initialize() async {
    try {
      await ThemeController.instance.init();
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
            _initialIncomingSeconds = (callData['elapsedSeconds'] as int?) ?? 0;
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
      final elapsedSec = (data['elapsedSeconds'] as int?) ?? 0;
      debugPrint('OnyxMain: Call State Update: $state for $number (name: $name, elapsed: $elapsedSec)');

      // Handle all active states: 1=Dialing, 2=Ringing, 4=Active, 8=Select_Account, 9=Connecting
      if ((state == 1 || state == 2 || state == 4 || state == 8 || state == 9) && !_isCallScreenVisible) {
        _isCallScreenVisible = true;
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ThemeRouter.getCallScreen(
            ThemeController.instance.currentTheme,
            initialNumber: number, 
            initialState: state,
            initialName: name,
            initialSeconds: elapsedSec,
            exitOnEnd: false,
          )),
        ).then((_) {
          _isCallScreenVisible = false;
          ProximitySensor.setProximityScreenOff(false);
        });
      }
      
      if (state == 7) {
        _isCallScreenVisible = false;
        ProximitySensor.setProximityScreenOff(false);
        if (!_isLaunchedForCall) {
          if (mounted) setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ThemeController.instance.removeListener(_onThemeChange);
    _callSub?.cancel();
    ProximitySensor.setProximityScreenOff(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.currentTheme;
    debugPrint('OnyxMain: build - isLoading = $_isLoading, isLaunchedForCall = $_isLaunchedForCall, startMode = $_startMode, theme = $theme');
    
    final isNothing = theme == 'nothing';
    final activeLightTheme = isNothing 
        ? AppTheme.lightTheme.copyWith(
            textTheme: AppTheme.lightTheme.textTheme.apply(fontFamily: 'NothingFont'),
            primaryTextTheme: AppTheme.lightTheme.primaryTextTheme.apply(fontFamily: 'NothingFont'),
          )
        : AppTheme.lightTheme;
    final activeDarkTheme = isNothing 
        ? AppTheme.darkTheme.copyWith(
            textTheme: AppTheme.darkTheme.textTheme.apply(fontFamily: 'NothingFont'),
            primaryTextTheme: AppTheme.darkTheme.primaryTextTheme.apply(fontFamily: 'NothingFont'),
          )
        : AppTheme.darkTheme;

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
        theme: activeLightTheme,
        darkTheme: activeDarkTheme,
        themeMode: ThemeMode.system,
        home: _isLoading 
            ? const Scaffold(backgroundColor: Colors.transparent)
            : (_isLaunchedForCall 
                ? ThemeRouter.getCallScreen(
                    theme,
                    exitOnEnd: true,
                    initialNumber: _initialIncomingNumber,
                    initialState: _initialIncomingState,
                    initialName: _initialIncomingName,
                    initialSeconds: _initialIncomingSeconds,
                  ) 
                : (_startMode == null 
                    ? ThemeRouter.getStartupScreen(theme) 
                    : ThemeRouter.getHomeScreen(theme))),
      ),
    );
  }
}
