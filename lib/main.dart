import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';     // ← for POST_NOTIFICATIONS

// ───────────────────────────────────────────────────────────
//  Globals
// ───────────────────────────────────────────────────────────
const fetchBackground = 'fetchBackground';
final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

// ───────────────────────────────────────────────────────────
//  Background‑isolate entry point
// ───────────────────────────────────────────────────────────
@pragma('vm:entry-point')                                   // keep after obfuscation
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();                 // 🔑 registers plugins

  Workmanager().executeTask((task, inputData) async {
    if (task == fetchBackground) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        await _showLocationNotification(pos);
      } catch (e, s) {
        debugPrint('BG error: $e\n$s');
      }
    }
    return Future.value(true);
  });
}

// ───────────────────────────────────────────────────────────
//  Notification helper
// ───────────────────────────────────────────────────────────
Future<void> _showLocationNotification(Position pos) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'location_bg',                // channel ID
    'Location Background',        // channel name
    channelDescription: 'Shows location fetched in background',
    importance: Importance.max,
    priority: Priority.high,
    playSound: false,
  );

  const NotificationDetails details = NotificationDetails(android: androidDetails);

  await notifications.show(
    0,
    'Location fetched',
    'Lat: ${pos.latitude}, Lon: ${pos.longitude}',
    details,
  );
}

// ───────────────────────────────────────────────────────────
//  App entry point
// ───────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise local‑notifications plugin (works in both isolates)
  const AndroidInitializationSettings initAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: initAndroid);
  await notifications.initialize(initSettings);

  // Request runtime permissions (location + notifications on Android 13+)
  await _requestPermissions();

  // Initialise & schedule Workmanager
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  await Workmanager().registerPeriodicTask(
    'bgLocationTask',
    fetchBackground,
    frequency: const Duration(minutes: 15), // Android min interval
    constraints: Constraints(networkType: NetworkType.not_required),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );

  runApp(const MyApp());
}

Future<void> _requestPermissions() async {
  // Location
  var locPermission = await Geolocator.checkPermission();
  if (locPermission == LocationPermission.denied ||
      locPermission == LocationPermission.deniedForever) {
    locPermission = await Geolocator.requestPermission();
  }
  if (locPermission == LocationPermission.deniedForever) return;

  // Android 13+ notifications
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

  if (!await Geolocator.isLocationServiceEnabled()) {
    await Geolocator.openLocationSettings();
  }
}

// ───────────────────────────────────────────────────────────
//  UI – just a placeholder
// ───────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Background Location Demo')),
          body: const Center(child: Text('Background task scheduled.')),
        ),
      );
}
