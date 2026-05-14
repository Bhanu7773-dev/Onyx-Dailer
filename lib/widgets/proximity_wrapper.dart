import 'dart:async';
import 'package:flutter/material.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:flutter/services.dart';

class ProximityWrapper extends StatefulWidget {
  final Widget child;
  const ProximityWrapper({super.key, required this.child});

  @override
  State<ProximityWrapper> createState() => _ProximityWrapperState();
}

class _ProximityWrapperState extends State<ProximityWrapper> {
  bool _isNear = false;
  StreamSubscription<int>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _listen() {
    _subscription = ProximitySensor.events.listen((int event) {
      setState(() {
        _isNear = (event > 0);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isNear)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // Swallows touches
              onVerticalDragStart: (_) {},
              onHorizontalDragStart: (_) {},
              child: Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_outlined, color: Colors.white, size: 48),
                      SizedBox(height: 16),
                      Text(
                        'Pocket Mode Active',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Clean the top of the screen\nor move it away to unlock',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
