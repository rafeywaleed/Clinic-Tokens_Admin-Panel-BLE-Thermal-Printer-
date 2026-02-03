// import 'dart:async';
// import 'dart:io';

// import 'package:blue_thermal_printer/blue_thermal_printer.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// class TokenPrinterApp2 extends StatelessWidget {
//   const TokenPrinterApp2({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Token Printer',
//       theme: ThemeData(
//         primarySwatch: Colors.indigo,
//         useMaterial3: false,
//       ),
//       home: const HomeScreen(),
//       debugShowCheckedModeBanner: false,
//     );
//   }
// }

// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});

//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> {
//   final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;
//   List<BluetoothDevice> _devices = [];
//   BluetoothDevice? _selectedDevice;
//   bool _connected = false;
//   int _token = 1;
//   bool _loadingDevices = false;

//   static const String _prefTokenKey = 'token_counter';

//   @override
//   void initState() {
//     super.initState();
//     _initAll();
//   }

//   Future<void> _initAll() async {
//     await _requestPermissions();
//     await _loadTokenFromPrefs();
//     await _initBluetooth();
//   }

//   Future<void> _requestPermissions() async {
//     // Request common permissions necessary for Bluetooth usage on Android.
//     // permission_handler maps to proper runtime permissions per Android version.
//     if (!kIsWeb && Platform.isAndroid) {
//       // Request location (older Android devices require it for Bluetooth scanning)
//       await Permission.location.request();

//       // Android 12+ Bluetooth permissions
//       if (await Permission.bluetoothScan.isDenied) {
//         await Permission.bluetoothScan.request();
//       }
//       if (await Permission.bluetoothConnect.isDenied) {
//         await Permission.bluetoothConnect.request();
//       }

//       // sometimes useful to also request bluetooth (legacy)
//       await Permission.bluetooth.request();
//     }
//   }

//   Future<void> _loadTokenFromPrefs() async {
//     final prefs = await SharedPreferences.getInstance();
//     setState(() {
//       _token = prefs.getInt(_prefTokenKey) ?? 1; // start from 1 by default
//     });
//   }

//   Future<void> _saveTokenToPrefs() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setInt(_prefTokenKey, _token);
//   }

//   Future<void> _initBluetooth() async {
//     setState(() => _loadingDevices = true);

//     // Listen to state changes (connected / disconnected)
//     _bluetooth.onStateChanged().listen((state) {
//       if (!mounted) return;
//       setState(() {
//         switch (state) {
//           case BlueThermalPrinter.CONNECTED:
//             _connected = true;
//             break;
//           case BlueThermalPrinter.DISCONNECTED:
//           case BlueThermalPrinter.DISCONNECT_REQUESTED:
//           case BlueThermalPrinter.ERROR:
//           case BlueThermalPrinter.STATE_OFF:
//           case BlueThermalPrinter.STATE_TURNING_OFF:
//           case BlueThermalPrinter.STATE_TURNING_ON:
//           case BlueThermalPrinter.STATE_ON:
//           default:
//             _connected = false;
//             break;
//         }
//       });
//     });

//     try {
//       final bonded = await _bluetooth.getBondedDevices();
//       final isConnected = await _bluetooth.isConnected;
//       setState(() {
//         _devices = bonded.cast<BluetoothDevice>();
//         _connected = isConnected ?? false;
//       });
//     } catch (e) {
//       debugPrint("Error listing bonded devices: $e");
//     } finally {
//       setState(() => _loadingDevices = false);
//     }
//   }

//   Future<void> _connectOrDisconnect() async {
//     if (_connected) {
//       await _bluetooth.disconnect();
//       setState(() {
//         _connected = false;
//       });
//       _showSnack("Disconnected from printer.");
//       return;
//     }

//     if (_selectedDevice == null) {
//       _showSnack("Please select a printer (paired) first.");
//       return;
//     }

//     try {
//       await _bluetooth.connect(_selectedDevice!);
//       // The onStateChanged listener will flip the `_connected` flag.
//       _showSnack(
//           "Connection request sent. If pairing is required, accept on device.");
//     } catch (e) {
//       _showSnack("Failed to connect: $e");
//       debugPrint("Connect error: $e");
//     }
//   }

//   Future<void> _printToken() async {
//     final isConnected = (await _bluetooth.isConnected) ?? false;
//     if (!isConnected) {
//       _showSnack("Printer not connected. Please connect a printer first.");
//       return;
//     }

//     try {
//       // Example printing layout: heading, token number, timestamp, new lines, paper cut.
//       await _bluetooth.printCustom("TOKEN", 3, 1); // big centered header
//       await _bluetooth.printNewLine();
//       await _bluetooth.printCustom(
//           "No. $_token", 2, 1); // token number centered
//       await _bluetooth.printNewLine();
//       await _bluetooth.printCustom("Thank you", 0, 1);
//       await _bluetooth.printNewLine();
//       await _bluetooth.printNewLine();
//       // Some printers support paperCut
//       try {
//         // Not all printer implementations support paperCut; ignore if fails.
//         await _bluetooth.paperCut();
//       } catch (_) {}
//       // increment and persist
//       setState(() {
//         _token += 1;
//       });
//       await _saveTokenToPrefs();
//       _showSnack("Printed token and increased counter.");
//     } catch (e) {
//       _showSnack("Printing failed: $e");
//       debugPrint("Print error: $e");
//     }
//   }

//   Future<void> _resetToken() async {
//     final confirm = await showDialog<bool>(
//       context: context,
//       builder: (_) => AlertDialog(
//         title: const Text("Reset tokens?"),
//         content: const Text("This will reset the token counter back to 1."),
//         actions: [
//           TextButton(
//               onPressed: () => Navigator.pop(context, false),
//               child: const Text("Cancel")),
//           ElevatedButton(
//               onPressed: () => Navigator.pop(context, true),
//               child: const Text("Reset")),
//         ],
//       ),
//     );

//     if (confirm == true) {
//       setState(() {
//         _token = 1;
//       });
//       await _saveTokenToPrefs();
//       _showSnack("Token counter reset.");
//     }
//   }

//   void _showSnack(String message) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context)
//         .showSnackBar(SnackBar(content: Text(message)));
//   }

//   Future<void> _refreshDeviceList() async {
//     setState(() => _loadingDevices = true);
//     try {
//       final bonded = await _bluetooth.getBondedDevices();
//       setState(() {
//         _devices = bonded.cast<BluetoothDevice>();
//       });
//       _showSnack("Device list refreshed.");
//     } catch (e) {
//       _showSnack("Unable to refresh devices: $e");
//     } finally {
//       setState(() => _loadingDevices = false);
//     }
//   }

//   Widget _buildTopStatusCard() {
//     final name = _selectedDevice?.name ?? "No printer selected";
//     final statusColor = _connected ? Colors.green : Colors.red;
//     final statusText = _connected ? "Connected" : "Disconnected";

//     return Card(
//       margin: const EdgeInsets.all(12),
//       elevation: 4,
//       child: Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
//         child: Row(
//           children: [
//             CircleAvatar(radius: 10, backgroundColor: statusColor),
//             const SizedBox(width: 12),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(statusText,
//                       style: const TextStyle(fontWeight: FontWeight.bold)),
//                   const SizedBox(height: 4),
//                   Text(name, style: const TextStyle(color: Colors.black54)),
//                 ],
//               ),
//             ),
//             IconButton(
//               tooltip: "Refresh paired devices",
//               onPressed: _refreshDeviceList,
//               icon: const Icon(Icons.refresh),
//             ),
//             const SizedBox(width: 8),
//             ElevatedButton(
//               onPressed: _connectOrDisconnect,
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: _connected ? Colors.red : Colors.green,
//               ),
//               child: Text(_connected ? "Disconnect" : "Connect"),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildDeviceSelector() {
//     if (_loadingDevices) {
//       return const Center(child: CircularProgressIndicator());
//     }

//     final items = _devices.map((d) {
//       final display = "${d.name ?? 'Unknown'}\n${d.address ?? ''}";
//       return DropdownMenuItem<BluetoothDevice>(
//         value: d,
//         child: Text(display, maxLines: 2, overflow: TextOverflow.ellipsis),
//       );
//     }).toList();

//     if (items.isEmpty) {
//       return const Text(
//           "No paired devices found. Pair your printer in Android settings first.");
//     }

//     return DropdownButtonFormField<BluetoothDevice>(
//       value: _selectedDevice,
//       items: items,
//       onChanged: (v) {
//         setState(() {
//           _selectedDevice = v;
//         });
//       },
//       decoration: const InputDecoration(
//         labelText: "Choose a paired printer",
//         border: OutlineInputBorder(),
//         contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Token Printer"),
//         centerTitle: true,
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             _buildTopStatusCard(),
//             const SizedBox(height: 8),
//             _buildDeviceSelector(),
//             const SizedBox(height: 24),
//             // Token display
//             Card(
//               elevation: 3,
//               margin: const EdgeInsets.symmetric(vertical: 8),
//               child: Padding(
//                 padding: const EdgeInsets.symmetric(vertical: 30),
//                 child: Column(
//                   children: [
//                     const Text("Current Token",
//                         style: TextStyle(fontSize: 18, color: Colors.black54)),
//                     const SizedBox(height: 12),
//                     Text(
//                       "${_token - 1 >= 1 ? _token - 1 : 0}", // shows last printed token number; if none printed, show 0
//                       style: const TextStyle(
//                           fontSize: 64,
//                           fontWeight: FontWeight.bold,
//                           letterSpacing: 2.0),
//                     ),
//                     const SizedBox(height: 8),
//                     Text("Next: $_token",
//                         style: const TextStyle(
//                             fontSize: 16, color: Colors.black45)),
//                   ],
//                 ),
//               ),
//             ),
//             const SizedBox(height: 16),
//             // Buttons row
//             Row(
//               children: [
//                 Expanded(
//                   child: ElevatedButton.icon(
//                     icon: const Icon(Icons.print),
//                     label: const Padding(
//                       padding: EdgeInsets.symmetric(vertical: 14.0),
//                       child:
//                           Text("Print Token", style: TextStyle(fontSize: 16)),
//                     ),
//                     onPressed: _printToken,
//                   ),
//                 ),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   child: OutlinedButton.icon(
//                     icon: const Icon(Icons.refresh),
//                     label: const Padding(
//                       padding: EdgeInsets.symmetric(vertical: 14.0),
//                       child:
//                           Text("Reset Tokens", style: TextStyle(fontSize: 16)),
//                     ),
//                     onPressed: _resetToken,
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 24),
//             // Helpful hints
//             Card(
//               color: Colors.grey.shade50,
//               child: Padding(
//                 padding: const EdgeInsets.all(12.0),
//                 child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: const [
//                       Text("Notes",
//                           style: TextStyle(fontWeight: FontWeight.bold)),
//                       SizedBox(height: 6),
//                       Text(
//                           "• Make sure the printer is paired (Settings → Bluetooth)."),
//                       SizedBox(height: 4),
//                       Text(
//                           "• Select the paired printer in the dropdown then press Connect."),
//                       SizedBox(height: 4),
//                       Text(
//                           "• If printing fails, check the printer model (many use ESC/POS)."),
//                     ]),
//               ),
//             ),
//             const SizedBox(height: 40),
//           ],
//         ),
//       ),
//     );
//   }
// }
