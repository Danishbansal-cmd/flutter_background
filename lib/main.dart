import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background/data/data_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart'; // ← for POST_NOTIFICATIONS

// ───────────────────────────────────────────────────────────
//  Globals
// ───────────────────────────────────────────────────────────
const fetchBackground = 'fetchBackground';
final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

// ───────────────────────────────────────────────────────────
//  Background‑isolate entry point
// ───────────────────────────────────────────────────────────
@pragma('vm:entry-point') // keep after obfuscation
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized(); // 🔑 registers plugins

  // NEW: notification plugin for this isolate
  final FlutterLocalNotificationsPlugin bgNotifs =
      FlutterLocalNotificationsPlugin();
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  bgNotifs.initialize(init);

  Workmanager().executeTask((task, inputData) async {
    if (task == fetchBackground) {
      try {
        debugPrint('executing task initializing');
        // don’t even try if we lack BACKGROUND permission
        final perm = await Geolocator.checkPermission();
        if (perm != LocationPermission.always) {
          debugPrint(' No background‑location permission');
          return true;
        }
        
        debugPrint('permissions granted');

        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        
        debugPrint('getting location $pos');
        await _appendLocationToPrefs(pos);
        debugPrint('executed _appendLocationToPrefs successfully');

        await _showLocationNotification(bgNotifs, pos);
        debugPrint('executed _showLocationNotification successfully');
      } catch (e, s) {
        debugPrint('BG error: $e\n$s');
      }
    }
    return Future.value(true);
  });
}

// ───────────────────────────────────────────────────────────
//  Store it in Shared Preferences helper
// ───────────────────────────────────────────────────────────
Future<void> _appendLocationToPrefs(Position pos) async {
  final prefs = await DataStorage.getInstace();

  
  debugPrint('get prefs $prefs');

  // We’ll store each element as "epochMillis,lat,lon"
  final now = DateTime.now().millisecondsSinceEpoch;
  final entry = '$now,${pos.latitude},${pos.longitude}';

  final List<String> history = prefs.getStringList('location_history') ?? [];
  history.add(entry);

  await prefs.setStringList('location_history', history);
  
  debugPrint('setted location_history ${prefs.getStringList("location_history")}');
}

// ───────────────────────────────────────────────────────────
//  Notification helper
// ───────────────────────────────────────────────────────────
Future<void> _showLocationNotification(FlutterLocalNotificationsPlugin plugin, Position pos) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'location_bg', // channel ID
    'Location Background', // channel name
    channelDescription: 'Shows location fetched in background',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
  );

  const NotificationDetails details = NotificationDetails(
    android: androidDetails,
  );

  await plugin.show(
    0,
    'Location fetched',
    'Lat: ${pos.latitude}, Lon: ${pos.longitude}',
    details,
  );

  
  debugPrint('executed _showLocationNotification till last');
}

// ───────────────────────────────────────────────────────────
//  App entry point
// ───────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());

  _initializeAfterUiBuild();
}

Future<void> _initializeAfterUiBuild() async {
  // Initialise local‑notifications plugin (works in both isolates)
  const AndroidInitializationSettings initAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(
    android: initAndroid,
  );

  await notifications.initialize(initSettings); 

  // Request runtime permissions (location  notifications on Android 13)
  await _requestPermissions();
  // Send the first pending location (if any) before the UI shows up
  await _sendFirstPendingLocation();
  // Initialise & schedule Workmanager
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  debugPrint('called Workmanager().initialize(callbackDispatcher)');

  // await Workmanager().registerOneOffTask(
  //   'debugOneOff${DateTime.now().millisecondsSinceEpoch}',
  //   fetchBackground,
  //   initialDelay: const Duration(seconds: 10),
  //   constraints: Constraints(networkType: NetworkType.not_required),
  //   existingWorkPolicy: ExistingWorkPolicy.replace,
  // );
  debugPrint('called Workmanager().registerOneOffTask()');

  await Workmanager().registerPeriodicTask(
    'bgLocationTask${DateTime.now().millisecondsSinceEpoch}',
    fetchBackground,
    initialDelay: Duration(seconds: 30),
    frequency: const Duration(minutes: 15), // Android min interval
    constraints: Constraints(networkType: NetworkType.not_required),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
  debugPrint('called Workmanager().registerPeriodicTask()');
}

// ───────────────────────────────────────────────────────────
//  Send first queued location (or “empty” values) to remote API
// ───────────────────────────────────────────────────────────
Future<void> _sendFirstPendingLocation() async {
  final prefs = await SharedPreferences.getInstance();
  final history = prefs.getStringList('location_history') ?? [];

  // Pick the first pending location if any; otherwise “empty”
  final String payloadValue = history.isNotEmpty ? history.first : 'empty';

  final uri = Uri.parse('https://abcdefghi-nine.vercel.app/api/v1/add');

  try {
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: '''
        {
          "abc": "$payloadValue",
          "def": "empty",
          "ghi": "empty"
        }
      ''',
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // If we actually sent a real location, remove it from the list
      if (history.isNotEmpty) {
        history.removeAt(0);
        await prefs.setStringList('location_history', history);
      }
      debugPrint('✅ Posted payload, response: $res');
    } else {
      debugPrint('❌ API replied ${res.statusCode}: ${res.body}');
    }
  } catch (e) {
    debugPrint('❌ Network error: $e');
  }
}

Future<void> _requestPermissions() async {
  // Location
  // step 1 ─ ask for foreground ("While in use") if needed
  var locPermission = await Geolocator.checkPermission();
  if (locPermission == LocationPermission.denied ||
      locPermission == LocationPermission.deniedForever) {
    locPermission = await Geolocator.requestPermission();
  }
  if (locPermission == LocationPermission.deniedForever) return; // user said “Never”

  // step 2 ─ on Android 10+ request BACKGROUND separately
  if (locPermission == LocationPermission.whileInUse) {
    locPermission = await Geolocator.requestPermission(); // will show second dialog
  }

  // Android 13 notifications
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

  if (!await Geolocator.isLocationServiceEnabled()) {
    await Geolocator.openLocationSettings();
  }
}

/// ───────────────────────────────────────────────────────────
///  UI – list all stored locations
/// ───────────────────────────────────────────────────────────
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  /// List we’ll show in the UI
  late Future<List<String>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  Future<List<String>> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();  
    return prefs.getStringList('location_history') ?? <String>[];
  }

  Future<void> _refresh() async {
    setState(() => _historyFuture = _loadHistory());
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Location History'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
            ],
          ),
          body: FutureBuilder<List<String>>(
            future: _historyFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final history = snapshot.data!;
              if (history.isEmpty) {
                return const Center(
                    child: Text('No locations stored yet.'));
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, index) {
                    final entry = history[index];          // "epoch,lat,lon"
                    final parts = entry.split(',');
                    final time = DateTime.fromMillisecondsSinceEpoch(
                        int.parse(parts[0]));
                    final lat = parts[1];
                    final lon = parts[2];

                    return ListTile(
                      leading: Text('#${index + 1}'),
                      title: Text('Lat: $lat  Lon: $lon'),
                      subtitle:
                          Text('${time.toLocal()}'), // formatted timestamp
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
}
