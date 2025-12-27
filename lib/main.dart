// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

void main() {
  runApp(const MaterialApp(home: GPSLoggerApp()));
}

class GPSLoggerApp extends StatefulWidget {
  const GPSLoggerApp({super.key});

  @override
  State<GPSLoggerApp> createState() => _GPSLoggerAppState();
}

class _GPSLoggerAppState extends State<GPSLoggerApp> {
  bool _isTracking = false;
  String _status = "Stopped";
  List<String> _recentLogs = [];

  @override
  void initState() {
    super.initState();
    _initBackgroundGeolocation();
  }

  void _initBackgroundGeolocation() {
    // 1. Listen to events
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      print('[location] - $location');
      setState(() {
        _recentLogs.insert(0, "Lat: ${location.coords.latitude}, Lon: ${location.coords.longitude}");
      });
    }, (bg.LocationError error) {
      print('[location] ERROR: $error');
    });

    bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
      print('[motionchange] - $location');
    });

    // 2. Configure the plugin
    bg.BackgroundGeolocation.ready(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 15.0, // Only log every 15 meters
        stopOnTerminate: false, // Continue tracking after app is swiped away
        startOnBoot: true,      // Continue tracking after phone reboot
        debug: true,            // Sound effects for testing (remove for production)
        logLevel: bg.Config.LOG_LEVEL_VERBOSE,
        reset: true 
    )).then((bg.State state) {
      setState(() {
        _isTracking = state.enabled;
        _status = state.enabled ? "Running" : "Stopped";
      });
    });
  }

  void _toggleTracking() {
    if (_isTracking) {
      bg.BackgroundGeolocation.stop().then((state) {
        setState(() {
          _isTracking = false;
          _status = "Stopped";
        });
      });
    } else {
      bg.BackgroundGeolocation.start().then((state) {
        setState(() {
          _isTracking = true;
          _status = "Tracking Roads...";
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Background Road Tracker")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                title: Text("Status: $_status"),
                trailing: Switch(
                  value: _isTracking,
                  onChanged: (val) => _toggleTracking(),
                ),
              ),
            ),
            const Divider(),
            const Text("Recent Background Points:", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _recentLogs.length,
                itemBuilder: (context, index) => Text(_recentLogs[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}