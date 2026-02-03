// import 'dart:async';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
// import 'package:flutter_thermal_printer/utils/printer.dart';
// // import 'package:esc_pos_utils/esc_pos_utils.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:intl/intl.dart';

// class TokenPrinterApp3 extends StatelessWidget {
//   const TokenPrinterApp3({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Token Printer Pro',
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
//   final FlutterThermalPrinter _printerPlugin = FlutterThermalPrinter.instance;
//   List<Printer> _printers = [];
//   Printer? _connectedPrinter;
//   bool _isScanning = false;
//   bool _isConnecting = false;
//   bool _isDisconnecting = false;
//   int _tokenNumber = 1;
//   bool _isPrinting = false;
//   StreamSubscription<List<Printer>>? _devicesSubscription;

//   @override
//   void initState() {
//     super.initState();
//     _initBluetooth();
//     _loadTokenNumber();
//   }

//   @override
//   void dispose() {
//     _devicesSubscription?.cancel();
//     // No disconnect method available, just cancel subscription
//     super.dispose();
//   }

//   Future<void> _initBluetooth() async {
//     await _requestPermissions();

//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       startScan();
//     });
//   }

//   Future<void> _requestPermissions() async {
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

//   void startScan() {
//     if (_isScanning) return;

//     setState(() {
//       _isScanning = true;
//       _printers.clear();
//     });

//     _devicesSubscription?.cancel();

//     // Start scanning for BLE printers
//     _printerPlugin.getPrinters(connectionTypes: [ConnectionType.BLE]);

//     _devicesSubscription =
//         _printerPlugin.devicesStream.listen((List<Printer> printers) {
//       setState(() {
//         _printers = printers;
//         _isScanning = false;

//         // Filter for likely printer devices
//         _printers.removeWhere((element) =>
//             element.name == null ||
//             element.name == '' ||
//             element.name!.toLowerCase().contains('print') == false);

//         // Update connection status (we'll track it manually since no isConnected property)
//         // The package doesn't expose isConnected, so we'll track it ourselves
//       });
//     }, onError: (error) {
//       setState(() {
//         _isScanning = false;
//       });
//       _showError('Scan failed: $error');
//     });
//   }

//   void stopScan() {
//     _printerPlugin.stopScan();
//     setState(() {
//       _isScanning = false;
//     });
//   }

//   Future<void> _connectToPrinter(Printer printer) async {
//     if (_isConnecting) return;

//     setState(() {
//       _isConnecting = true;
//     });

//     try {
//       bool connected = await _printerPlugin.connect(printer);
//       if (connected) {
//         setState(() {
//           _connectedPrinter = printer;
//           _isConnecting = false;
//         });
//         _showSuccess('Connected to ${printer.name}');
//       } else {
//         setState(() {
//           _isConnecting = false;
//         });
//         _showError('Failed to connect to ${printer.name}');
//       }
//     } catch (e) {
//       setState(() {
//         _isConnecting = false;
//       });
//       _showError('Connection failed: $e');
//     }
//   }

//   Future<void> _printToken() async {
//     if (_connectedPrinter == null) {
//       _showError('Please connect to a printer first');
//       return;
//     }

//     if (_isPrinting) return;

//     setState(() {
//       _isPrinting = true;
//     });

//     try {
//       // Generate receipt bytes
//       List<int> bytes = await _generateTokenBytes();

//       // Print using the plugin's printData method
//       await _printerPlugin.printData(
//         _connectedPrinter!,
//         bytes,
//         longData: true,
//       );

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

//   // Method using direct ESC/POS commands
//   Future<List<int>> _generateTokenBytes() async {
//     final profile = await CapabilityProfile.load();
//     final generator = Generator(PaperSize.mm80, profile);
//     List<int> bytes = [];

//     bytes += generator.reset();
//     bytes += generator.text(
//       'TOKEN',
//       styles: const PosStyles(
//         align: PosAlign.center,
//         height: PosTextSize.size2,
//         width: PosTextSize.size2,
//         bold: true,
//       ),
//     );

//     bytes += generator.text(
//       'NUMBER',
//       styles: const PosStyles(
//         align: PosAlign.center,
//         height: PosTextSize.size2,
//         width: PosTextSize.size2,
//         bold: true,
//       ),
//     );

//     bytes += generator.hr();

//     bytes += generator.text(
//       '$_tokenNumber',
//       styles: const PosStyles(
//         align: PosAlign.center,
//         height: PosTextSize.size4,
//         width: PosTextSize.size4,
//         bold: true,
//       ),
//     );

//     bytes += generator.hr();

//     bytes += generator.text(
//       DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now()),
//       styles: const PosStyles(
//         align: PosAlign.center,
//       ),
//     );

//     bytes += generator.text(
//       'Thank you for waiting',
//       styles: const PosStyles(
//         align: PosAlign.center,
//       ),
//     );

//     bytes += generator.feed(2);
//     bytes += generator.cut();

//     return bytes;
//   }

//   Future<void> _resetTokens() async {
//     final confirmed = await showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Reset Token Counter'),
//         content: const Text(
//             'Are you sure you want to reset the token counter to 1?'),
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
//         duration: const Duration(seconds: 3),
//       ),
//     );
//   }

//   void _showSuccess(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.green,
//         duration: const Duration(seconds: 2),
//       ),
//     );
//   }

//   void _showInfo(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.blue,
//         duration: const Duration(seconds: 2),
//       ),
//     );
//   }

//   Widget _buildConnectionStatus() {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: _connectedPrinter != null ? Colors.green[50] : Colors.red[50],
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: _connectedPrinter != null ? Colors.green : Colors.red,
//           width: 1,
//         ),
//       ),
//       child: Row(
//         children: [
//           Icon(
//             _connectedPrinter != null
//                 ? Icons.check_circle
//                 : Icons.error_outline,
//             color: _connectedPrinter != null ? Colors.green : Colors.red,
//             size: 24,
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   _connectedPrinter != null ? 'Connected' : 'Not Connected',
//                   style: TextStyle(
//                     fontSize: 16,
//                     fontWeight: FontWeight.bold,
//                     color: _connectedPrinter != null
//                         ? Colors.green[800]
//                         : Colors.red[800],
//                   ),
//                 ),
//                 if (_connectedPrinter != null)
//                   Text(
//                     'Printer: ${_connectedPrinter!.name}',
//                     style: const TextStyle(fontSize: 14),
//                     overflow: TextOverflow.ellipsis,
//                   ),
//               ],
//             ),
//           ),
//           if (_connectedPrinter != null)
//             IconButton(
//               onPressed: () {
//                 // Since there's no disconnect method, we'll just clear the connection
//                 setState(() {
//                   _connectedPrinter = null;
//                 });
//                 _showInfo('Disconnected');
//               },
//               icon: const Icon(Icons.link_off, color: Colors.red),
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildPrinterList() {
//     if (_printers.isEmpty && !_isScanning) {
//       return const Padding(
//         padding: EdgeInsets.all(16.0),
//         child: Text(
//           'No Bluetooth printers found. Tap "Scan for Printers" to search.',
//           textAlign: TextAlign.center,
//           style: TextStyle(color: Colors.grey),
//         ),
//       );
//     }

//     return ListView.builder(
//       shrinkWrap: true,
//       physics: const NeverScrollableScrollPhysics(),
//       itemCount: _printers.length,
//       itemBuilder: (context, index) {
//         final printer = _printers[index];
//         final isConnected = _connectedPrinter?.address == printer.address;

//         return Card(
//           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//           child: ListTile(
//             leading: Icon(
//               Icons.print,
//               color: isConnected ? Colors.green : Colors.blue,
//             ),
//             title: Text(
//               printer.name ?? 'Unknown Printer',
//               style: TextStyle(
//                 fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
//               ),
//             ),
//             subtitle: Text(
//               printer.address ?? 'No address',
//             ),
//             trailing: Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 if (isConnected)
//                   const Icon(Icons.check, color: Colors.green, size: 20),
//                 const SizedBox(width: 8),
//                 ElevatedButton(
//                   onPressed: _isConnecting
//                       ? null
//                       : () => isConnected
//                           ? _disconnectPrinter()
//                           : _connectToPrinter(printer),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor:
//                         isConnected ? Colors.red[50] : Colors.blue[50],
//                     foregroundColor: isConnected ? Colors.red : Colors.blue,
//                     padding:
//                         const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                   ),
//                   child: Text(
//                     isConnected ? 'Disconnect' : 'Connect',
//                     style: const TextStyle(fontSize: 12),
//                   ),
//                 ),
//               ],
//             ),
//             onTap: () {
//               if (!isConnected) {
//                 _connectToPrinter(printer);
//               }
//             },
//           ),
//         );
//       },
//     );
//   }

//   void _disconnectPrinter() {
//     setState(() {
//       _connectedPrinter = null;
//     });
//     _showInfo('Disconnected');
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Token Printer Pro'),
//         centerTitle: true,
//         elevation: 2,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _isScanning ? stopScan : startScan,
//             tooltip: _isScanning ? 'Stop Scan' : 'Scan Printers',
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

//             // Scan Status
//             if (_isScanning) const LinearProgressIndicator(),

//             if (_isScanning)
//               const Padding(
//                 padding: EdgeInsets.symmetric(vertical: 8),
//                 child: Text(
//                   'Scanning for printers...',
//                   textAlign: TextAlign.center,
//                   style: TextStyle(color: Colors.blue),
//                 ),
//               ),

//             const SizedBox(height: 16),

//             // Printer List
//             if (_printers.isNotEmpty || _isScanning)
//               Card(
//                 elevation: 2,
//                 child: Padding(
//                   padding: const EdgeInsets.all(8.0),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Padding(
//                         padding: const EdgeInsets.all(8.0),
//                         child: Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             Text(
//                               'Available Printers',
//                               style: Theme.of(context)
//                                   .textTheme
//                                   .titleMedium
//                                   ?.copyWith(
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                             ),
//                             Text(
//                               'Found: ${_printers.length}',
//                               style: const TextStyle(color: Colors.grey),
//                             ),
//                           ],
//                         ),
//                       ),
//                       _buildPrinterList(),
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
//                     onPressed: _connectedPrinter == null || _isPrinting
//                         ? null
//                         : _printToken,
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
//                       style:
//                           TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
//                     ),
//                     SizedBox(height: 8),
//                     Text(
//                         '1. Make sure your thermal printer is turned on and in pairing mode'),
//                     Text(
//                         '2. Tap "Scan for Printers" to search for available devices'),
//                     Text(
//                         '3. Select your printer from the list and tap "Connect"'),
//                     Text(
//                         '4. Tap "Print Token" to print the current token number'),
//                     Text(
//                         '5. The token number will automatically increment after each print'),
//                     Text(
//                         '6. Use "Reset Counter" to start the token count from 1'),
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
