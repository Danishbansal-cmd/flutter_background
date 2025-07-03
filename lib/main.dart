import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:developer' as developer;



const task = "getLocation";

@pragma('vm:entry-point') // required for background isolate
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized(); 

  Workmanager().executeTask((taskName, inputData) async{
    switch (taskName) {
      case "getLocation":
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
          developer.log("lat: ${position.latitude}, long: ${position.longitude}");

          FlutterBackgroundService().invoke("updateNotification", {
            "latitude": position.latitude.toString(),
            "longitude": position.longitude.toString(),
          });
        }catch(e, stack){
          developer.log("Error getting location: $e", stackTrace: stack);
        }
        break;
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);

  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'Tracking',
      initialNotificationContent: 'Initializing...',
    ),
    iosConfiguration: IosConfiguration(),
  );

  // await initializeService();
  runApp(const MyApp());
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on("updateNotification").listen((event) {
    final latitude = event?['latitude'] ?? '';
    final longitude = event?['longitude'] ?? '';

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Live Location",
        content: "Lat: $latitude, Long: $longitude",
      );
    }
  });

  service.on("stopService").listen((event) {
    service.stopSelf();
  });
}

// Future<void> initializeService() async {
//   final service = FlutterBackgroundService();

//   await service.configure(
//     androidConfiguration: AndroidConfiguration(
//       onStart: onStart,
//       autoStartOnBoot: true,
//       autoStart: true,
//       isForegroundMode: true,
//     ),
//     iosConfiguration: IosConfiguration(),
//   );

//   await service.startService();
// }

// @pragma('vm:entry-point')
// void onStart(ServiceInstance service) async {
//   bool isTracking = true;
//   SharedPreferences prefs = await DataStorage.getInstace();

//   List<String> locationList = prefs.getStringList('location_history') ?? [];

//   // Required for accessing platform channels in background isolate
//   WidgetsFlutterBinding.ensureInitialized();

//   final timer = Timer.periodic(const Duration(seconds: 60), (timer) async {
//     if (!isTracking) return;

//     if (service is AndroidServiceInstance) {
//       if (await service.isForegroundService()) {
//         // 🔍 Get current location
//         LocationPermission permission = await Geolocator.checkPermission();
//         if (permission == LocationPermission.whileInUse ||
//             permission == LocationPermission.always) {
//           // final position = await Geolocator.getCurrentPosition();
//           try {
//             final position = await Geolocator.getCurrentPosition(
//               desiredAccuracy: LocationAccuracy.low,
//             );

//             final pos = "Lat: ${position.latitude}, Lng: ${position.longitude}";
//             locationList.add(pos);

//             // Save updated list
//             await prefs.setStringList('location_history', locationList);

//             // Display all locations (last 5 for brevity)
//             String content = locationList.reversed.take(5).join('\n');

//             // use position
//             service.setForegroundNotificationInfo(
//               title: "Tracking ${locationList.length} positions",
//               content: content,
//             );

//             // You can also send this data to a server or save it
//             print("Logged: $pos");
//           } catch (e) {
//             print("Error getting position: $e");
//           }
//         } else {
//           print("Location permission not granted.");
//         }
//       }
//     }
//   });

//   if (service is AndroidServiceInstance) {
//     service.on('setAsForeground').listen((even) {
//       service.setAsForegroundService();
//     });

//     service.on('setAsBackground').listen((even) {
//       service.setAsBackgroundService();
//     });

//     service.on('pauseTracking').listen((event) {
//       isTracking = false;
//       print("Tracking paused.");
//     });

//     service.on('resumeTracking').listen((event) {
//       isTracking = true;
//       print("Tracking resumed.");
//     });
//   }

//   service.on('stopService').listen((event) async {
//     timer.cancel(); // Stop the periodic timer
//     await prefs.setStringList('location_history', locationList);
//     service.stopSelf();
//   });
// }



class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String text = "Stop Service";

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _initializeBGTask();
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Service app')),
        body: Column(
          children: [
            ElevatedButton(
              onPressed: () {
                FlutterBackgroundService().invoke("setAsForeground");
              },
              child: const Text("Foreground Mode"),
            ),
            ElevatedButton(
              onPressed: () {
                FlutterBackgroundService().invoke("setAsBackground");
              },
              child: const Text("Background Mode"),
            ),
            ElevatedButton(
              onPressed: () {
                FlutterBackgroundService().invoke("pauseTracking");
              },
              child: const Text("Pause Tracking"),
            ),
            ElevatedButton(
              onPressed: () {
                FlutterBackgroundService().invoke("resumeTracking");
              },
              child: const Text("Resume Tracking"),
            ),
            ElevatedButton(
              child: Text(text),
              onPressed: () async {
                final service = FlutterBackgroundService();
                var isRunning = await service.isRunning();
                if (isRunning) {
                  service.invoke("stopService");
                } else {
                  service.startService();
                }
                if (!isRunning) {
                  text = "Stop Service";
                } else {
                  text = "Start Service";
                }

                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationServiceEnabled) {
      // Optionally prompt user to enable location
      await Geolocator.openLocationSettings();
    }
  }

  Future<void> _initializeBGTask() async {
    var uniqueID = "getLocationIdentifier";
    await Workmanager().registerPeriodicTask(
      uniqueID,
      task,
      frequency: const Duration(minutes: 15), // Android minimum
      initialDelay: Duration(seconds: 10),
      constraints: Constraints(
        networkType: NetworkType.not_required        
      ),
    );
  }
}

