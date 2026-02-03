// import 'dart:async';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter_bluetooth_basic/flutter_bluetooth_basic.dart';
// import 'package:esc_pos_utils/esc_pos_utils.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:intl/intl.dart';

// class TokenPrinterApp1 extends StatelessWidget {
//   const TokenPrinterApp1({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Token Printer',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         primarySwatch: Colors.blue,
//         useMaterial3: true,
//         scaffoldBackgroundColor: Colors.grey[50],
//       ),
//       home: const PrinterScreen(),
//     );
//   }
// }

// class PrinterScreen extends StatefulWidget {
//   const PrinterScreen({super.key});

//   @override
//   _PrinterScreenState createState() => _PrinterScreenState();
// }

// class _PrinterScreenState extends State<PrinterScreen> {
//   final BluetoothManager _bluetoothManager = BluetoothManager.instance;
//   List<BluetoothDevice> _devices = [];
//   BluetoothDevice? _connectedDevice;
//   bool _isScanning = false;
//   bool _isConnecting = false;
//   bool _isDisconnecting = false;
//   int _tokenNumber = 1;
//   bool _isPrinting = false;
//   StreamSubscription<BluetoothState>? _bluetoothStateSubscription;

//   @override
//   void initState() {
//     super.initState();
//     _initBluetooth();
//     _loadTokenNumber();
//     _setupBluetoothListener();
//   }

//   @override
//   void dispose() {
//     _bluetoothStateSubscription?.cancel();
//     _disconnect();
//     super.dispose();
//   }

//   void _setupBluetoothListener() {
//     _bluetoothStateSubscription = _bluetoothManager.onStateChanged().listen((state) {
//       if (state == BluetoothState.STATE_OFF || state == BluetoothState.STATE_TURNING_OFF) {
//         setState(() {
//           _connectedDevice = null;
//         });
//       }
//     });
//   }

//   Future<void> _initBluetooth() async {
//     await _requestPermissions();
    
//     // Initialize bluetooth manager
//     bool isConnected = await _bluetoothManager.isConnected;
//     if (isConnected) {
//       _connectedDevice = await _bluetoothManager.connectedDevice;
//     }
    
//     // Start scan to get initial devices
//     _scanDevices();
//   }

//   Future<void> _requestPermissions() async {
//     // Request necessary permissions for Android
//     await Permission.bluetooth.request();
//     await Permission.bluetoothConnect.request();
//     await Permission.bluetoothScan.request();
//     await Permission.locationWhenInUse.request();
//   }

//   Future<void> _loadTokenNumber() async {
//     final prefs = await SharedPreferences.getInstance();
//     setState(() {
//       _tokenNumber = prefs.getInt('token_number') ?? 1;
//     });
//   }

//   Future<void> _saveTokenNumber() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setInt('token_number', _tokenNumber);
//   }

//   Future<void> _scanDevices() async {
//     if (_isScanning) return;

//     setState(() {
//       _isScanning = true;
//       _devices.clear();
//     });

//     try {
//       await _bluetoothManager.startScan(timeout: const Duration(seconds: 10));
      
//       // Get scanned devices
//       _devices = await _bluetoothManager.scanResults;
      
//       setState(() {
//         _isScanning = false;
//       });
//     } catch (e) {
//       setState(() {
//         _isScanning = false;
//       });
//       _showError('Scan failed: $e');
//     }
//   }

//   Future<void> _connectToDevice(BluetoothDevice device) async {
//     if (_isConnecting) return;

//     setState(() {
//       _isConnecting = true;
//     });

//     try {
//       await _bluetoothManager.connect(device);
//       setState(() {
//         _connectedDevice = device;
//         _isConnecting = false;
//       });
//       _showSuccess('Connected to ${device.name}');
//     } catch (e) {
//       setState(() {
//         _isConnecting = false;
//       });
//       _showError('Connection failed: $e');
//     }
//   }

//   Future<void> _disconnect() async {
//     if (_connectedDevice == null || _isDisconnecting) return;

//     setState(() {
//       _isDisconnecting = true;
//     });

//     try {
//       await _bluetoothManager.disconnect();
//       setState(() {
//         _connectedDevice = null;
//         _isDisconnecting = false;
//       });
//       _showInfo('Disconnected');
//     } catch (e) {
//       setState(() {
//         _isDisconnecting = false;
//       });
//       _showError('Disconnection failed: $e');
//     }
//   }

//   Future<void> _printToken() async {
//     if (_connectedDevice == null) {
//       _showError('Please connect to a printer first');
//       return;
//     }

//     if (_isPrinting) return;

//     setState(() {
//       _isPrinting = true;
//     });

//     try {
//       final profile = await CapabilityProfile.load();
//       final generator = Generator(PaperSize.mm80, profile);
//       List<int> bytes = [];

//       // Generate receipt
//       bytes += generator.reset();
//       bytes += generator.text(
//         'TOKEN',
//         styles: const PosStyles(
//           align: PosAlign.center,
//           height: PosTextSize.size2,
//           width: PosTextSize.size2,
//           bold: true,
//         ),
//       );
      
//       bytes += generator.text(
//         'NUMBER',
//         styles: const PosStyles(
//           align: PosAlign.center,
//           height: PosTextSize.size2,
//           width: PosTextSize.size2,
//           bold: true,
//         ),
//       );
      
//       bytes += generator.hr();
      
//       bytes += generator.text(
//         '$_tokenNumber',
//         styles: const PosStyles(
//           align: PosAlign.center,
//           height: PosTextSize.size4,
//           width: PosTextSize.size4,
//           bold: true,
//         ),
//       );
      
//       bytes += generator.hr();
      
//       bytes += generator.text(
//         DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now()),
//         styles: const PosStyles(
//           align: PosAlign.center,
//         ),
//       );
      
//       bytes += generator.text(
//         'Thank you for waiting',
//         styles: const PosStyles(
//           align: PosAlign.center,
//         ),
//       );
      
//       bytes += generator.feed(2);
//       bytes += generator.cut();

//       await _bluetoothManager.writeData(Uint8List.fromList(bytes));

//       // Increment token number
//       setState(() {
//         _tokenNumber++;
//       });
//       await _saveTokenNumber();

//       _showSuccess('Token printed successfully!');
//     } catch (e) {
//       _showError('Print failed: $e');
//     } finally {
//       setState(() {
//         _isPrinting = false;
//       });
//     }
//   }

//   Future<void> _resetTokens() async {
//     final confirmed = await showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Reset Token Counter'),
//         content: const Text('Are you sure you want to reset the token counter to 1?'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context, false),
//             child: const Text('Cancel'),
//           ),
//           TextButton(
//             onPressed: () => Navigator.pop(context, true),
//             child: const Text('Reset', style: TextStyle(color: Colors.red)),
//           ),
//         ],
//       ),
//     );

//     if (confirmed == true) {
//       setState(() {
//         _tokenNumber = 1;
//       });
//       await _saveTokenNumber();
//       _showSuccess('Token counter reset to 1');
//     }
//   }

//   void _showError(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.red,
//       ),
//     );
//   }

//   void _showSuccess(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.green,
//       ),
//     );
//   }

//   void _showInfo(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.blue,
//       ),
//     );
//   }

//   Widget _buildConnectionStatus() {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: _connectedDevice != null ? Colors.green[50] : Colors.red[50],
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: _connectedDevice != null ? Colors.green : Colors.red,
//           width: 1,
//         ),
//       ),
//       child: Row(
//         children: [
//           Icon(
//             _connectedDevice != null ? Icons.check_circle : Icons.error_outline,
//             color: _connectedDevice != null ? Colors.green : Colors.red,
//             size: 24,
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   _connectedDevice != null ? 'Connected' : 'Not Connected',
//                   style: TextStyle(
//                     fontSize: 16,
//                     fontWeight: FontWeight.bold,
//                     color: _connectedDevice != null ? Colors.green[800] : Colors.red[800],
//                   ),
//                 ),
//                 if (_connectedDevice != null)
//                   Text(
//                     'Printer: ${_connectedDevice!.name}',
//                     style: const TextStyle(fontSize: 14),
//                     overflow: TextOverflow.ellipsis,
//                   ),
//               ],
//             ),
//           ),
//           if (_connectedDevice != null)
//             IconButton(
//               onPressed: _disconnect,
//               icon: _isDisconnecting
//                   ? const SizedBox(
//                       width: 24,
//                       height: 24,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                   : const Icon(Icons.link_off, color: Colors.red),
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDeviceList() {
//     if (_devices.isEmpty && !_isScanning) {
//       return const Padding(
//         padding: EdgeInsets.all(16.0),
//         child: Text(
//           'No Bluetooth devices found. Tap "Scan for Printers" to search.',
//           textAlign: TextAlign.center,
//           style: TextStyle(color: Colors.grey),
//         ),
//       );
//     }

//     return ListView.builder(
//       shrinkWrap: true,
//       physics: const NeverScrollableScrollPhysics(),
//       itemCount: _devices.length,
//       itemBuilder: (context, index) {
//         final device = _devices[index];
//         return ListTile(
//           leading: const Icon(Icons.print, color: Colors.blue),
//           title: Text(device.name ?? 'Unknown Device'),
//           subtitle: Text(device.address ?? ''),
//           trailing: _connectedDevice?.address == device.address
//               ? const Icon(Icons.check, color: Colors.green)
//               : _isConnecting
//                   ? const SizedBox(
//                       width: 24,
//                       height: 24,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                   : ElevatedButton(
//                       onPressed: () => _connectToDevice(device),
//                       child: const Text('Connect'),
//                     ),
//         );
//       },
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Token Printer'),
//         centerTitle: true,
//         elevation: 2,
//         actions: [
//           IconButton(
//             icon: _isScanning
//                 ? const SizedBox(
//                     width: 20,
//                     height: 20,
//                     child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
//                   )
//                 : const Icon(Icons.refresh),
//             onPressed: _isScanning ? null : _scanDevices,
//             tooltip: 'Refresh Devices',
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // Connection Status
//             _buildConnectionStatus(),
//             const SizedBox(height: 20),

//             // Scan Button
//             ElevatedButton.icon(
//               onPressed: _isScanning ? null : _scanDevices,
//               icon: _isScanning
//                   ? const SizedBox(
//                       width: 20,
//                       height: 20,
//                       child: CircularProgressIndicator(strokeWidth: 2),
//                     )
//                   : const Icon(Icons.search),
//               label: Text(_isScanning ? 'Scanning...' : 'Scan for Printers'),
//               style: ElevatedButton.styleFrom(
//                 padding: const EdgeInsets.symmetric(vertical: 16),
//               ),
//             ),
//             const SizedBox(height: 16),

//             // Device List
//             if (_devices.isNotEmpty || _isScanning)
//               Card(
//                 elevation: 2,
//                 child: Padding(
//                   padding: const EdgeInsets.all(8.0),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Padding(
//                         padding: const EdgeInsets.all(8.0),
//                         child: Text(
//                           'Available Printers',
//                           style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                                 fontWeight: FontWeight.bold,
//                               ),
//                         ),
//                       ),
//                       _buildDeviceList(),
//                     ],
//                   ),
//                 ),
//               ),
//             const SizedBox(height: 32),

//             // Token Display
//             Card(
//               elevation: 4,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(16),
//               ),
//               child: Padding(
//                 padding: const EdgeInsets.all(32),
//                 child: Column(
//                   children: [
//                     const Text(
//                       'CURRENT TOKEN',
//                       style: TextStyle(
//                         fontSize: 16,
//                         fontWeight: FontWeight.bold,
//                         color: Colors.grey,
//                       ),
//                     ),
//                     const SizedBox(height: 16),
//                     Text(
//                       '$_tokenNumber',
//                       style: const TextStyle(
//                         fontSize: 72,
//                         fontWeight: FontWeight.bold,
//                         color: Colors.blue,
//                       ),
//                     ),
//                     const SizedBox(height: 8),
//                     Text(
//                       'Next: ${_tokenNumber + 1}',
//                       style: const TextStyle(
//                         fontSize: 14,
//                         color: Colors.grey,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             const SizedBox(height: 32),

//             // Action Buttons
//             Row(
//               children: [
//                 Expanded(
//                   child: ElevatedButton.icon(
//                     onPressed: _connectedDevice == null || _isPrinting ? null : _printToken,
//                     icon: _isPrinting
//                         ? const SizedBox(
//                             width: 20,
//                             height: 20,
//                             child: CircularProgressIndicator(strokeWidth: 2),
//                           )
//                         : const Icon(Icons.print),
//                     label: Text(_isPrinting ? 'Printing...' : 'Print Token'),
//                     style: ElevatedButton.styleFrom(
//                       padding: const EdgeInsets.symmetric(vertical: 16),
//                       backgroundColor: Colors.blue,
//                       foregroundColor: Colors.white,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 16),
//                 Expanded(
//                   child: OutlinedButton.icon(
//                     onPressed: _resetTokens,
//                     icon: const Icon(Icons.restart_alt),
//                     label: const Text('Reset Counter'),
//                     style: OutlinedButton.styleFrom(
//                       padding: const EdgeInsets.symmetric(vertical: 16),
//                       side: const BorderSide(color: Colors.red),
//                     ),
//                   ),
//                 ),
//               ],
//             ),

//             // Instructions
//             const SizedBox(height: 40),
//             const Card(
//               child: Padding(
//                 padding: EdgeInsets.all(16),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Instructions:',
//                       style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
//                     ),
//                     SizedBox(height: 8),
//                     Text('1. Make sure your thermal printer is turned on and in pairing mode'),
//                     Text('2. Tap "Scan for Printers" to search for available devices'),
//                     Text('3. Select your printer from the list and tap "Connect"'),
//                     Text('4. Tap "Print Token" to print the current token number'),
//                     Text('5. The token number will automatically increment after each print'),
//                     Text('6. Use "Reset Counter" to start the token count from 1'),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }