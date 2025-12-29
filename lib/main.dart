// ignore_for_file: prefer_const_constructors, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:background_fetch/background_fetch.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'database_helper.dart';
import 'dart:convert'; // Required for utf8.decoder

// [HEADLESS TASK - Same as before]
@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  String taskId = task.taskId;
  bool isTimeout = task.timeout;
  if (isTimeout) {
    BackgroundFetch.finish(taskId);
    return;
  }
  try {
    var location = await bg.BackgroundGeolocation.getCurrentPosition(
      samples: 1,
      extras: {"event": "background-fetch"}
    );
    await DatabaseHelper.instance.insertLog(
      location.coords.latitude,
      location.coords.longitude,
      "Headless-Fetch"
    );
  } catch(e) {
    print('[Headless] Error: $e');
  }
  BackgroundFetch.finish(taskId);
}

void main() {
  runApp(const MaterialApp(home: GPSLoggerApp()));
  BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
}

class GPSLoggerApp extends StatefulWidget {
  const GPSLoggerApp({super.key});

  @override
  State<GPSLoggerApp> createState() => _GPSLoggerAppState();
}

class _GPSLoggerAppState extends State<GPSLoggerApp> {
  bool _isTracking = false;
  String _status = "Stopped";
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _initPlatformState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final logs = await DatabaseHelper.instance.getLogs();
    if (mounted) {
      setState(() {
        _logs = logs;
      });
    }
  }

  // --- EXPORT FUNCTION ---
  Future<void> _exportCSV() async {
    // 1. Get data from DB
    List<Map<String, dynamic>> data = await DatabaseHelper.instance.getLogs();
    
    // 2. Create CSV Header
    List<List<dynamic>> rows = [];
    rows.add(["latitude", "longitude", "source", "timestamp"]);

    // 3. Add Rows
    for (var row in data) {
      rows.add([
        row['latitude'],
        row['longitude'],
        row['source'],
        row['timestamp']
      ]);
    }

    // 4. Convert to CSV String
    String csvData = const ListToCsvConverter().convert(rows);

    // 5. Write to a temporary file
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/gps_logs.csv";
    final file = File(path);
    await file.writeAsString(csvData);

    // 6. Share the file (User can save to Files, Drive, Email, etc.)
    await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path)], 
      text: 'Here are your GPS Logs'
    )
  );
  }

  // --- IMPORT FUNCTION ---
  Future<void> _importCSV() async {
    // 1. Pick a file
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      File file = File(result.files.single.path!);
      
      // 2. Read file content
      final input = file.openRead();
      final fields = await input
          .transform(utf8.decoder)              // 1. Convert Bytes to String
          .transform(const CsvToListConverter()) // 2. Convert String to List
          .toList();
      // 3. Parse and Insert
      int count = 0;
      // Skip header row (index 0) if it exists, start at 1
      for (int i = 1; i < fields.length; i++) {
        var row = fields[i];
        // Ensure row has at least 4 columns (lat, lon, source, time)
        if (row.length >= 4) {
          double lat = row[0] is double ? row[0] : double.tryParse(row[0].toString()) ?? 0.0;
          double lon = row[1] is double ? row[1] : double.tryParse(row[1].toString()) ?? 0.0;
          String source = row[2].toString();
          String timestamp = row[3].toString();

          await DatabaseHelper.instance.insertLog(lat, lon, source, timestamp: timestamp);
          count++;
        }
      }

      // 4. Refresh UI
      await _loadLogs();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Imported $count logs!")));
    }
  }

  Future<void> _clearDatabase() async {
    await DatabaseHelper.instance.clearLogs();
    _loadLogs();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Database Cleared")));
  }

  Future<void> _initPlatformState() async {
    await _initBackgroundGeolocation();
    await _initBackgroundFetch();
  }

  Future<void> _initBackgroundFetch() async {
    await BackgroundFetch.configure(BackgroundFetchConfig(
        minimumFetchInterval: 15,
        stopOnTerminate: false,
        enableHeadless: true,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresStorageNotLow: false,
        requiresDeviceIdle: false,
        requiredNetworkType: NetworkType.NONE
    ), (String taskId) async {
      bg.Location location = await bg.BackgroundGeolocation.getCurrentPosition(
        samples: 1, extras: {"event": "background-fetch"}
      );
      await DatabaseHelper.instance.insertLog(
        location.coords.latitude, location.coords.longitude, "Background-Fetch"
      );
      await _loadLogs();
      BackgroundFetch.finish(taskId);
    }, (String taskId) async {
      BackgroundFetch.finish(taskId);
    });
  }

  Future<void> _initBackgroundGeolocation() async {
    bg.BackgroundGeolocation.onLocation((bg.Location location) async {
      await DatabaseHelper.instance.insertLog(
        location.coords.latitude, location.coords.longitude, "Motion-Change"
      );
      await _loadLogs();
    });

    await bg.BackgroundGeolocation.ready(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 15.0,
        stopOnTerminate: false,
        startOnBoot: true,
        debug: true,
        logLevel: bg.Config.LOG_LEVEL_VERBOSE,
        enableHeadless: true,
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
      appBar: AppBar(
        title: const Text("SQLite Road Tracker"),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') _exportCSV();
              if (value == 'import') _importCSV();
              if (value == 'clear') _clearDatabase();
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem(value: 'export', child: Text('Export CSV')),
                const PopupMenuItem(value: 'import', child: Text('Import CSV')),
                const PopupMenuItem(value: 'clear', child: Text('Clear Database')),
              ];
            },
          ),
        ],
      ),
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
            Expanded(
              child: _logs.isEmpty 
              ? const Center(child: Text("No logs in database"))
              : ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  final date = DateTime.tryParse(log['timestamp'])?.toLocal() ?? DateTime.now();
                  final timeString = "${date.hour}:${date.minute}:${date.second}";

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      log['source'] == 'Motion-Change' ? Icons.directions_car : Icons.timer,
                      color: log['source'] == 'Motion-Change' ? Colors.blue : Colors.orange,
                    ),
                    title: Text("Lat: ${log['latitude']}, Lon: ${log['longitude']}"),
                    subtitle: Text("${log['source']} @ $timeString"),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}