import 'package:flutter/material.dart';
import 'package:wavedialer/themes/onyx/startup_screen.dart' as onyx_startup;
import 'package:wavedialer/themes/onyx/home_screen.dart' as onyx_home;
import 'package:wavedialer/themes/onyx/call_screen.dart' as onyx_call;
import 'package:wavedialer/themes/onyx/settings_screen.dart' as onyx_settings;
import 'package:wavedialer/themes/nothing/home_screen.dart' as nothing_home;
import 'package:wavedialer/themes/nothing/settings_screen.dart' as nothing_settings;

class ThemeRouter {
  static Widget getStartupScreen(String theme) {
    switch (theme) {
      case 'nothing':
      case 'onyx':
      default:
        return const onyx_startup.StartupScreen();
    }
  }

  static Widget getHomeScreen(String theme) {
    switch (theme) {
      case 'nothing':
        return const nothing_home.HomeScreen();
      case 'onyx':
      default:
        return const onyx_home.HomeScreen();
    }
  }

  static Widget getSettingsScreen(String theme) {
    switch (theme) {
      case 'nothing':
        return const nothing_settings.SettingsScreen();
      case 'onyx':
      default:
        return const onyx_settings.SettingsScreen();
    }
  }

  static Widget getCallScreen(
    String theme, {
    String? initialNumber,
    int? initialState,
    String? initialName,
    int initialSeconds = 0,
    required bool exitOnEnd,
  }) {
    switch (theme) {
      case 'nothing':
      case 'onyx':
      default:
        return onyx_call.CallScreen(
          initialNumber: initialNumber,
          initialState: initialState,
          initialName: initialName,
          initialSeconds: initialSeconds,
          exitOnEnd: exitOnEnd,
        );
    }
  }
}
