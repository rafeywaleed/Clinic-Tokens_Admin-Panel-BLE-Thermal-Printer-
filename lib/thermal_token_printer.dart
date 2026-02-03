// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'dart:typed_data';
// import 'dart:ui' as ui;
// import 'package:intl/intl.dart';


// class TokenPrinterScreen extends StatefulWidget {
//   const TokenPrinterScreen({super.key});

//   @override
//   State<TokenPrinterScreen> createState() => _TokenPrinterScreenState();
// }

// class _TokenPrinterScreenState extends State<TokenPrinterScreen> {
//   // Bluetooth variables
//   List<BluetoothDevice> _devices = [];
//   BluetoothDevice? _connectedDevice;
//   bool _isScanning = false;
//   bool _isConnecting = false;
//   bool _isPrinting = false;
//   bool _isConnected = false;
//   BluetoothState _bluetoothState = BluetoothState.unknown;
  
//   // Token variables
//   int _tokenNumber = 1;
//   final DateFormat _dateFormat = DateFormat('dd-MM-yyyy HH:mm:ss');
  
//   // Stream subscription
//   StreamSubscription<DiscoveryState>? _discoverySubscription;
//   StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

//   @override
//   void initState() {
//     super.initState();
//     _initializeBluetooth();
//   }

//   @override
//   void dispose() {
//     _discoverySubscription?.cancel();
//     _connectionSubscription?.cancel();
//     if (_connectedDevice != null) {
//       FlutterBluetoothPrinter.disconnect(_connectedDevice!.address);
//     }
//     super.dispose();
//   }

//   Future<void> _initializeBluetooth() async {
//     // Check and request permissions
//     await _checkPermissions();
    
//     // Check Bluetooth state
//     await _checkBluetoothState();
    
//     // Listen to connection state changes
//     _connectionSubscription = FlutterBluetoothPrinter.connectionStateNotifier
//         .listen((BluetoothConnectionState state) {
//       if (mounted) {
//         setState(() {
//           _isConnected = state.state == BluetoothConnectionState.connected;
//         });
//       }
//     });

//     // Start device discovery
//     _startDiscovery();
//   }

//   Future<void> _checkPermissions() async {
//     // Request necessary permissions
//     final statuses = await [
//       Permission.bluetooth,
//       Permission.bluetoothConnect,
//       Permission.bluetoothScan,
//       Permission.locationWhenInUse,
//     ].request();

//     // Check if all permissions are granted
//     final allGranted = statuses.values.every((status) => status.isGranted);
//     if (!allGranted) {
//       _showError('Some permissions are not granted. App may not work properly.');
//     }
//   }

//   Future<void> _checkBluetoothState() async {
//     try {
//       final state = await FlutterBluetoothPrinter.getState();
//       if (mounted) {
//         setState(() {
//           _bluetoothState = state;
//         });
//       }
//     } catch (e) {
//       _showError('Failed to get Bluetooth state: $e');
//     }
//   }

//   void _startDiscovery() {
//     if (_isScanning) return;

//     setState(() {
//       _isScanning = true;
//       _devices.clear();
//     });

//     _discoverySubscription?.cancel();
//     _discoverySubscription = FlutterBluetoothPrinter.discovery.listen(
//       (DiscoveryState state) {
//         if (state is DiscoveryResult) {
//           if (mounted) {
//             setState(() {
//               _devices = state.devices;
//             });
//           }
//         } else if (state is DiscoveryStarted) {
//           if (mounted) {
//             setState(() {
//               _isScanning = true;
//             });
//           }
//         } else if (state is DiscoveryFinished) {
//           if (mounted) {
//             setState(() {
//               _isScanning = false;
//             });
//           }
//         }
//       },
//       onError: (error) {
//         if (mounted) {
//           setState(() {
//             _isScanning = false;
//           });
//         }
//         _showError('Discovery Error: $error');
//       },
//     );
//   }

//   Future<void> _connectToDevice(BluetoothDevice device) async {
//     if (_isConnecting || _connectedDevice?.address == device.address) return;

//     setState(() {
//       _isConnecting = true;
//     });

//     try {
//       // Disconnect from current device if any
//       if (_connectedDevice != null) {
//         await FlutterBluetoothPrinter.disconnect(_connectedDevice!.address);
//       }

//       // Connect to new device
//       final connected = await FlutterBluetoothPrinter.connect(device.address);

//       if (connected) {
//         setState(() {
//           _connectedDevice = device;
//           _isConnecting = false;
//         });
//         _showSuccess('Connected to ${device.name ?? "Unknown Device"}');
//       } else {
//         setState(() {
//           _connectedDevice = null;
//           _isConnecting = false;
//         });
//         _showError('Failed to connect to device');
//       }
//     } catch (e) {
//       setState(() {
//         _isConnecting = false;
//       });
//       _showError('Connection Error: $e');
//     }
//   }

//   Future<void> _disconnectDevice() async {
//     if (_connectedDevice != null) {
//       try {
//         await FlutterBluetoothPrinter.disconnect(_connectedDevice!.address);
//         setState(() {
//           _connectedDevice = null;
//           _isConnected = false;
//         });
//         _showSuccess('Disconnected from printer');
//       } catch (e) {
//         _showError('Disconnection Error: $e');
//       }
//     }
//   }

//   Future<void> _printToken() async {
//     if (_connectedDevice == null || !_isConnected) {
//       _showError('Please connect to a printer first');
//       return;
//     }

//     if (_isPrinting) return;

//     setState(() {
//       _isPrinting = true;
//     });

//     try {
//       // Create the token receipt as an image
//       final image = await _createTokenImage();
      
//       if (image != null) {
//         // Print the image using the package's printImageSingle method
//         final success = await FlutterBluetoothPrinter.printImageSingle(
//           address: _connectedDevice!.address,
//           imageBytes: image,
//           imageWidth: 384, // Standard width for 58mm printer
//           imageHeight: 600,
//           paperSize: PaperSize.mm58,
//           addFeeds: 3, // Add some feed after printing
//           cutPaper: false, // Don't cut paper for tokens
//           keepConnected: true, // Keep connection for faster subsequent prints
//           onProgress: (progress) {
//             print('Print progress: $progress%');
//           },
//         );

//         if (success) {
//           // Increment token number only after successful print
//           setState(() {
//             _tokenNumber++;
//           });
//           _showSuccess('Token #${_tokenNumber - 1} printed successfully');
//         } else {
//           _showError('Failed to print token');
//         }
//       }
//     } catch (e) {
//       _showError('Print Error: $e');
//     } finally {
//       setState(() {
//         _isPrinting = false;
//       });
//     }
//   }

//   Future<Uint8List?> _createTokenImage() async {
//     try {
//       // Create a picture recorder
//       final recorder = ui.PictureRecorder();
//       final canvas = Canvas(recorder);
      
//       // Define receipt dimensions (58mm thermal printer at 203 DPI)
//       const width = 384.0; // 58mm at 203 DPI (58 * 203 / 25.4 ≈ 384)
//       const height = 600.0;
      
//       // Create paint objects
//       final paint = Paint()
//         ..color = Colors.black
//         ..style = PaintingStyle.fill;
      
//       // Draw receipt background (white)
//       canvas.drawRect(
//         const Rect.fromLTRB(0, 0, width, height), 
//         Paint()..color = Colors.white,
//       );

//       // Define text styles
//       final titleStyle = ui.TextStyle(
//         color: Colors.black,
//         fontSize: 24,
//         fontWeight: FontWeight.bold,
//         fontFamily: 'Roboto',
//       );

//       final tokenStyle = ui.TextStyle(
//         color: Colors.black,
//         fontSize: 42,
//         fontWeight: FontWeight.bold,
//         fontFamily: 'Roboto',
//       );

//       final normalStyle = ui.TextStyle(
//         color: Colors.black,
//         fontSize: 18,
//         fontFamily: 'Roboto',
//       );

//       final smallStyle = ui.TextStyle(
//         color: Colors.black,
//         fontSize: 14,
//         fontFamily: 'Roboto',
//       );

//       final xsmallStyle = ui.TextStyle(
//         color: Colors.grey,
//         fontSize: 12,
//         fontFamily: 'Roboto',
//       );

//       // Draw title
//       _drawTextCentered(canvas, 'TOKEN RECEIPT', width, 40, titleStyle);

//       // Draw separator line
//       canvas.drawLine(
//         const Offset(20, 80),
//         Offset(width - 20, 80),
//         Paint()
//           ..color = Colors.black
//           ..strokeWidth = 1,
//       );

//       // Draw token number
//       final tokenText = 'TOKEN #${_tokenNumber.toString().padLeft(4, '0')}';
//       _drawTextCentered(canvas, tokenText, width, 140, tokenStyle);

//       // Draw date and time
//       final dateTime = DateTime.now();
//       final dateText = _dateFormat.format(dateTime);
//       _drawTextCentered(canvas, dateText, width, 200, normalStyle);

//       // Draw company name
//       _drawTextCentered(canvas, 'YOUR COMPANY NAME', width, 240, smallStyle);

//       // Draw dashed line
//       _drawDashedLine(canvas, width, 280);

//       // Draw instructions
//       _drawTextCentered(canvas, 'Please wait for your turn', width, 320, normalStyle);
//       _drawTextCentered(canvas, 'and present this token', width, 350, normalStyle);

//       // Draw thank you message
//       _drawTextCentered(canvas, 'Thank you for visiting!', width, 400, normalStyle);

//       // Draw separator line
//       canvas.drawLine(
//         const Offset(20, 450),
//         Offset(width - 20, 450),
//         Paint()
//           ..color = Colors.black
//           ..strokeWidth = 1,
//       );

//       // Draw footer
//       _drawTextCentered(canvas, 'Contact: +1 234 567 8900', width, 480, xsmallStyle);
//       _drawTextCentered(canvas, 'www.yourcompany.com', width, 500, xsmallStyle);
//       _drawTextCentered(canvas, 'Location: Your Business Address', width, 520, xsmallStyle);

//       // Draw QR code placeholder (optional)
//       canvas.drawRect(
//         Rect.fromCenter(
//           center: Offset(width / 2, 580),
//           width: 80,
//           height: 80,
//         ),
//         Paint()
//           ..color = Colors.grey.shade200
//           ..style = PaintingStyle.fill,
//       );

//       _drawTextCentered(canvas, 'SCAN ME', width, 620, xsmallStyle);

//       // End recording
//       final picture = recorder.endRecording();
//       final img = await picture.toImage(width.toInt(), (height + 80).toInt());
//       final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      
//       return byteData?.buffer.asUint8List();
//     } catch (e) {
//       print('Error creating image: $e');
//       return null;
//     }
//   }

//   void _drawTextCentered(Canvas canvas, String text, double width, double y, ui.TextStyle style) {
//     final paragraphBuilder = ui.ParagraphBuilder(
//       ui.ParagraphStyle(
//         textAlign: TextAlign.center,
//         fontSize: style.fontSize,
//         fontWeight: style.fontWeight,
//         fontFamily: style.fontFamily,
//       ),
//     )..pushStyle(style)..addText(text);
    
//     final paragraph = paragraphBuilder.build();
//     paragraph.layout(ui.ParagraphConstraints(width: width));
    
//     canvas.drawParagraph(
//       paragraph,
//       Offset((width - paragraph.width) / 2, y - paragraph.height / 2),
//     );
//   }

//   void _drawDashedLine(Canvas canvas, double width, double y) {
//     const dashWidth = 5.0;
//     const dashSpace = 3.0;
//     double startX = 20;
    
//     final paint = Paint()
//       ..color = Colors.black
//       ..strokeWidth = 1;
    
//     while (startX < width - 20) {
//       canvas.drawLine(
//         Offset(startX, y),
//         Offset(startX + dashWidth, y),
//         paint,
//       );
//       startX += dashWidth + dashSpace;
//     }
//   }

//   void _resetTokenCount() {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Reset Token Count'),
//         content: const Text('Are you sure you want to reset the token count to 1?'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel'),
//           ),
//           TextButton(
//             onPressed: () {
//               setState(() {
//                 _tokenNumber = 1;
//               });
//               Navigator.pop(context);
//               _showSuccess('Token count reset to 1');
//             },
//             child: const Text(
//               'Reset',
//               style: TextStyle(color: Colors.red),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDeviceSelector() {
//     return StreamBuilder<DiscoveryState>(
//       stream: FlutterBluetoothPrinter.discovery,
//       builder: (context, snapshot) {
//         final devices = snapshot.data is DiscoveryResult 
//             ? (snapshot.data as DiscoveryResult).devices 
//             : <BluetoothDevice>[];

//         if (snapshot.connectionState == ConnectionState.waiting && devices.isEmpty) {
//           return const Center(child: CircularProgressIndicator());
//         }

//         if (devices.isEmpty) {
//           return const Center(
//             child: Padding(
//               padding: EdgeInsets.all(16),
//               child: Text(
//                 'No Bluetooth devices found.\nMake sure your printer is turned on and in pairing mode.',
//                 textAlign: TextAlign.center,
//                 style: TextStyle(color: Colors.grey),
//               ),
//             ),
//           );
//         }

//         return ListView.builder(
//           shrinkWrap: true,
//           physics: const NeverScrollableScrollPhysics(),
//           itemCount: devices.length,
//           itemBuilder: (context, index) {
//             final device = devices[index];
//             final isConnected = _connectedDevice?.address == device.address && _isConnected;
            
//             return Card(
//               margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//               child: ListTile(
//                 leading: Icon(
//                   isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
//                   color: isConnected ? Colors.green : Colors.grey,
//                 ),
//                 title: Text(
//                   device.name ?? 'Unknown Device',
//                   style: TextStyle(
//                     fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
//                   ),
//                 ),
//                 subtitle: Text(device.address),
//                 trailing: isConnected
//                     ? const Icon(Icons.check_circle, color: Colors.green)
//                     : _isConnecting && _connectedDevice?.address == device.address
//                         ? const SizedBox(
//                             width: 20,
//                             height: 20,
//                             child: CircularProgressIndicator(strokeWidth: 2),
//                           )
//                         : const Icon(Icons.chevron_right),
//                 onTap: () => _connectToDevice(device),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }

//   void _showError(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.red,
//         behavior: SnackBarBehavior.floating,
//       ),
//     );
//   }

//   void _showSuccess(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.green,
//         behavior: SnackBarBehavior.floating,
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Thermal Token Printer'),
//         centerTitle: true,
//         elevation: 2,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _startDiscovery,
//             tooltip: 'Scan for devices',
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             // Bluetooth Status Card
//             Card(
//               child: Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(
//                       children: [
//                         _buildBluetoothStatusIcon(),
//                         const SizedBox(width: 12),
//                         Expanded(
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Text(
//                                 _getBluetoothStatusText(),
//                                 style: const TextStyle(
//                                   fontSize: 16,
//                                   fontWeight: FontWeight.bold,
//                                 ),
//                               ),
//                               if (_connectedDevice != null)
//                                 Text(
//                                   _connectedDevice!.name ?? 'Unknown Device',
//                                   style: const TextStyle(
//                                     fontSize: 14,
//                                     color: Colors.grey,
//                                   ),
//                                 ),
//                             ],
//                           ),
//                         ),
//                         if (_connectedDevice != null)
//                           IconButton(
//                             icon: const Icon(Icons.bluetooth_disabled),
//                             onPressed: _disconnectDevice,
//                             tooltip: 'Disconnect',
//                             color: Colors.red,
//                           ),
//                       ],
//                     ),
//                     const SizedBox(height: 8),
//                     LinearProgressIndicator(
//                       value: _isScanning ? null : 0,
//                       backgroundColor: Colors.grey[200],
//                       color: Colors.blue,
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             const SizedBox(height: 16),

//             // Devices List
//             Expanded(
//               flex: 2,
//               child: Card(
//                 child: Padding(
//                   padding: const EdgeInsets.all(16),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       const Text(
//                         'Available Printers',
//                         style: TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                       Expanded(child: _buildDeviceSelector()),
//                     ],
//                   ),
//                 ),
//               ),
//             ),

//             const SizedBox(height: 16),

//             // Token Display
//             Expanded(
//               flex: 3,
//               child: Card(
//                 child: Padding(
//                   padding: const EdgeInsets.all(24),
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       const Text(
//                         'CURRENT TOKEN',
//                         style: TextStyle(
//                           fontSize: 18,
//                           color: Colors.grey,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       const SizedBox(height: 24),
//                       Container(
//                         padding: const EdgeInsets.all(32),
//                         decoration: BoxDecoration(
//                           color: Colors.blue.shade50,
//                           borderRadius: BorderRadius.circular(20),
//                           border: Border.all(color: Colors.blue.shade200, width: 3),
//                           boxShadow: [
//                             BoxShadow(
//                               color: Colors.blue.shade100,
//                               blurRadius: 10,
//                               spreadRadius: 2,
//                             ),
//                           ],
//                         ),
//                         child: Text(
//                           _tokenNumber.toString().padLeft(4, '0'),
//                           style: const TextStyle(
//                             fontSize: 72,
//                             fontWeight: FontWeight.bold,
//                             color: Colors.blue,
//                           ),
//                         ),
//                       ),
//                       const SizedBox(height: 24),
//                       Text(
//                         'Last updated: ${_dateFormat.format(DateTime.now())}',
//                         style: const TextStyle(
//                           fontSize: 14,
//                           color: Colors.grey,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),

//             const SizedBox(height: 16),

//             // Action Buttons
//             Row(
//               children: [
//                 Expanded(
//                   child: ElevatedButton.icon(
//                     onPressed: _isPrinting || !_isConnected
//                         ? null
//                         : _printToken,
//                     icon: _isPrinting
//                         ? const SizedBox(
//                             width: 20,
//                             height: 20,
//                             child: CircularProgressIndicator(
//                               strokeWidth: 2,
//                               color: Colors.white,
//                             ),
//                           )
//                         : const Icon(Icons.print_outlined),
//                     label: Text(_isPrinting ? 'PRINTING...' : 'PRINT TOKEN'),
//                     style: ElevatedButton.styleFrom(
//                       padding: const EdgeInsets.symmetric(vertical: 18),
//                       backgroundColor: Colors.blue,
//                       foregroundColor: Colors.white,
//                       disabledBackgroundColor: Colors.grey,
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 12),
//                 SizedBox(
//                   width: 100,
//                   child: ElevatedButton.icon(
//                     onPressed: _resetTokenCount,
//                     icon: const Icon(Icons.restart_alt),
//                     label: const Text('RESET'),
//                     style: ElevatedButton.styleFrom(
//                       padding: const EdgeInsets.symmetric(vertical: 18),
//                       backgroundColor: Colors.grey.shade200,
//                       foregroundColor: Colors.red,
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildBluetoothStatusIcon() {
//     if (_isConnecting) {
//       return const SizedBox(
//         width: 24,
//         height: 24,
//         child: CircularProgressIndicator(strokeWidth: 2),
//       );
//     } else if (_isConnected) {
//       return const Icon(Icons.bluetooth_connected, color: Colors.green, size: 28);
//     } else if (_bluetoothState == BluetoothState.off) {
//       return const Icon(Icons.bluetooth_disabled, color: Colors.red, size: 28);
//     } else {
//       return const Icon(Icons.bluetooth, color: Colors.blue, size: 28);
//     }
//   }

//   String _getBluetoothStatusText() {
//     if (_isConnecting) {
//       return 'Connecting...';
//     } else if (_isConnected) {
//       return 'Connected to Printer';
//     } else if (_bluetoothState == BluetoothState.off) {
//       return 'Bluetooth is Off';
//     } else if (_isScanning) {
//       return 'Scanning for devices...';
//     } else {
//       return 'Not Connected';
//     }
//   }
// }