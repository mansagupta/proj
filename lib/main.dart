import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beacon Detector',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const BeaconDetectorScreen(),
    );
  }
}

class BeaconDetectorScreen extends StatefulWidget {
  const BeaconDetectorScreen({Key? key}) : super(key: key);

  @override
  _BeaconDetectorScreenState createState() => _BeaconDetectorScreenState();
}

class _BeaconDetectorScreenState extends State<BeaconDetectorScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final List<DiscoveredDevice> _beacons = [];
  String _statusMessage = 'Initializing beacon scanning...';
  String _calculatedPosition = '';
  Timer? _positionStreamTimer;

  @override
  void initState() {
    super.initState();
    _initializeBeaconScanning();
  }

  Future<void> _initializeBeaconScanning() async {
    if (await _checkPermissions()) {
      _startScanning();
    } else {
      setState(() {
        _statusMessage = 'Permissions not granted. Please enable them to scan for beacons.';
      });
    }
  }

  Future<bool> _checkPermissions() async {
    var locationStatus = await Permission.location.request();
    var bluetoothScanStatus = await Permission.bluetoothScan.request();
    var bluetoothConnectStatus = await Permission.bluetoothConnect.request();

    return locationStatus.isGranted &&
        bluetoothScanStatus.isGranted &&
        bluetoothConnectStatus.isGranted;
  }

  void _startScanning() {
    setState(() {
      _statusMessage = 'Scanning for beacons...';
    });

    _ble.scanForDevices(withServices: []).listen(
          (device) {
        if (device.name.contains("ESP32")) {
          setState(() {
            if (!_beacons.any((beacon) => beacon.id == device.id)) {
              _beacons.add(device);
              _statusMessage = 'Found ${_beacons.length} ESP32 beacons!';
              if (_beacons.length >= 3) {
                _calculatePosition();
              }
            }
          });
        }
      },
      onError: (error) {
        setState(() {
          _statusMessage = 'Error: $error';
        });
      },
    );
  }

  void _calculatePosition() {
    // Ensure there are at least 3 beacons
    if (_beacons.length < 3) {
      setState(() {
        _calculatedPosition =
        'Not enough beacons to calculate position. Need at least 3.';
      });
      return;
    }

    // Example fixed positions for beacons (in meters)
    // Replace these with the actual coordinates of your ESP32 beacons
    List<Offset> beaconPositions = [
      const Offset(0, 0),   // Beacon 1
      const Offset(5, 0),   // Beacon 2
      const Offset(0, 5),   // Beacon 3
    ];

    // Convert RSSI to distance (in meters) using the Log-distance path loss model
    // A and n are constants that need to be calibrated based on your environment
    double a = -59; // RSSI value at 1 meter (this value can vary)
    double n = 2.0; // Path-loss exponent (typically 2 for free space)

    List<double> distances = _beacons.map((beacon) {
      return pow(10, ((beacon.rssi - a) / (10 * n))).toDouble();
    }).toList();

    // Trilateration calculation
    double x1 = beaconPositions[0].dx;
    double y1 = beaconPositions[0].dy;
    double x2 = beaconPositions[1].dx;
    double y2 = beaconPositions[1].dy;
    double x3 = beaconPositions[2].dx;
    double y3 = beaconPositions[2].dy;

    double r1 = distances[0];
    double r2 = distances[1];
    double r3 = distances[2];

    // Applying the trilateration formula
    double A = 2 * (x2 - x1);
    double B = 2 * (y2 - y1);
    double C = (pow(r1, 2) - pow(r2, 2) - pow(x1, 2) + pow(x2, 2) - pow(y1, 2) + pow(y2, 2)).toDouble();
    double D = 2 * (x3 - x1);
    double E = 2 * (y3 - y1);
    double F = (pow(r1, 2) - pow(r3, 2) - pow(x1, 2) + pow(x3, 2) - pow(y1, 2) + pow(y3, 2)).toDouble();

    double denominator = (A * E - B * D);
    if (denominator == 0) {
      setState(() {
        _calculatedPosition = 'Error: Unable to calculate position (denominator=0)';
      });
      return;
    }

    double x = (C * E - B * F) / denominator;
    double y = (A * F - C * D) / denominator;

    setState(() {
      _calculatedPosition =
      'Estimated Position: (X: ${x.toStringAsFixed(2)}, Y: ${y.toStringAsFixed(2)})';
    });

    // Start streaming position to the server
    _startPositionStreaming(x, y);
  }

  void _startPositionStreaming(double x, double y) {
    // Cancel any existing timer
    _positionStreamTimer?.cancel();

    // Start a periodic timer to send position every 5 seconds
    _positionStreamTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _sendPositionToServer(x, y);
    });
  }

  Future<void> _sendPositionToServer(double x, double y) async {
    const String serverUrl = 'https://your-server-url.com/api/update_position'; // Replace with your server URL

    try {
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'x': x, 'y': y}),
      );

      if (response.statusCode == 200) {
        print('Position sent successfully!');
      } else {
        print('Failed to send position. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending position: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beacon Detector'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _beacons.isEmpty
            ? Center(child: Text(_statusMessage))
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text(
              _calculatedPosition,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              'Detected Beacons:',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _beacons.length,
                itemBuilder: (context, index) {
                  final beacon = _beacons[index];
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(beacon.name),
                    subtitle: Text('RSSI: ${beacon.rssi}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionStreamTimer?.cancel();
    super.dispose();
  }
}
