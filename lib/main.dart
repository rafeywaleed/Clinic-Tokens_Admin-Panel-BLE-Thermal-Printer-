import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer_library.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// --- API SERVICE ---
class ApiService {
  static const String baseUrl =
      "https://hospital-token-system-backend.vercel.app/api/tokens";

  // 1. Generate New Token
  static Future<int?> generateToken() async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/generate'));
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['token']['tokenNumber'];
      }
    } catch (e) {
      debugPrint("API Error (Generate): $e");
    }
    return null;
  }

  // 2. Get Current & Upcoming (For Serving Status)
  static Future<Map<String, dynamic>?> getCurrentStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/current'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint("API Error (Current): $e");
    }
    return null;
  }

  // 3. Complete Current Token (Next Patient)
  static Future<Map<String, dynamic>?> completeToken() async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/complete'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['activeToken']; // Returns the NEW active token
      }
    } catch (e) {
      debugPrint("API Error (Complete): $e");
    }
    return null;
  }

  // 4. Get Last Generated Token (For Printer State)
  static Future<int?> getLastGeneratedToken() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/last-generated'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Handle case where no tokens exist yet
        if (data['lastGeneratedToken'] == null) return 0;
        return data['lastGeneratedToken']['tokenNumber'];
      }
    } catch (e) {
      debugPrint("API Error (Last Generated): $e");
    }
    return null;
  }

  // 5. Reset All Tokens
  static Future<bool> resetTokens() async {
    try {
      final response = await http.post(Uri.parse('$baseUrl/reset'));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("API Error (Reset): $e");
      return false;
    }
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clinic Token Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BluetoothDevice? _selectedDevice;
  ReceiptController? _receiptController;

  // State Variables
  int _lastIssuedToken = 0; // Logic for printing
  int? _servingToken; // Logic for doctor's room
  bool _isPrinting = false;
  bool _isLoading = false;

  BluetoothConnectionState _connectionState = BluetoothConnectionState.idle;

  @override
  void initState() {
    super.initState();

    // 1. Bluetooth Listener
    FlutterBluetoothPrinter.connectionStateNotifier.addListener(() {
      setState(() {
        _connectionState =
            FlutterBluetoothPrinter.connectionStateNotifier.value;
      });
    });

    // 2. Initial Data Fetch
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);

    // Fetch Last Generated (For the printer counter)
    final lastGen = await ApiService.getLastGeneratedToken();
    if (lastGen != null) _lastIssuedToken = lastGen;

    // Fetch Current Serving (For the queue display)
    final status = await ApiService.getCurrentStatus();
    if (status != null && status['activeToken'] != null) {
      _servingToken = status['activeToken']['tokenNumber'];
    } else {
      _servingToken = null; // No one is being served
    }

    setState(() => _isLoading = false);
  }

  bool get isConnected =>
      _connectionState == BluetoothConnectionState.printing ||
      _connectionState == BluetoothConnectionState.completed;

  Future<void> _selectPrinter() async {
    try {
      final device = await FlutterBluetoothPrinter.selectDevice(context);
      if (device != null) {
        setState(() => _selectedDevice = device);
      }
    } catch (_) {
      _showError("Failed to select printer");
    }
  }

  // --- LOGIC: Print New Token ---
  Future<void> _printToken() async {
    if (_selectedDevice == null || _receiptController == null) {
      _showError("No printer selected");
      return;
    }

    if (_isPrinting) return;
    setState(() => _isPrinting = true);

    try {
      // 1. Call Backend to Generate Token
      final newTokenNum = await ApiService.generateToken();

      if (newTokenNum == null) {
        throw Exception("Backend failed to generate token");
      }

      // 2. Update Local State (So Receipt widget updates)
      setState(() => _lastIssuedToken = newTokenNum);

      // 3. Print the Receipt
      // Small delay to ensure widget rebuilds with new number before printing
      await Future.delayed(const Duration(milliseconds: 100));

      await _receiptController!.print(
        address: _selectedDevice!.address,
        keepConnected: true,
      );

      _showSuccess("Token #$newTokenNum generated & printed");
      _refreshData(); // Refresh to sync everything
    } catch (e) {
      _showError("Printing failed: $e");
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  Future<void> _testToken() async {
    try {
      // 1. Call Backend to Generate Token
      final newTokenNum = await ApiService.generateToken();

      if (newTokenNum == null) {
        throw Exception("Backend failed to generate token");
      }

      // 2. Update Local State (So Receipt widget updates)
      setState(() => _lastIssuedToken = newTokenNum);

      // 3. Print the Receipt
      // Small delay to ensure widget rebuilds with new number before printing
      await Future.delayed(const Duration(milliseconds: 100));

      _showSuccess("Token #$newTokenNum generated & printed");
      _refreshData(); // Refresh to sync everything
    } catch (e) {
      _showError("Printing failed: $e");
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  // --- LOGIC: Next Patient (Complete Current) ---
  Future<void> _nextPatient() async {
    setState(() => _isLoading = true);
    try {
      final result = await ApiService.completeToken();

      if (result != null) {
        setState(() {
          _servingToken = result['tokenNumber'];
        });
        _showSuccess("Now serving Token #${result['tokenNumber']}");
      } else {
        // If result is null, it might mean queue is empty or just finished
        _refreshData();
        _showSuccess("Current token completed");
      }
    } catch (e) {
      _showError("Failed to update status");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- LOGIC: Reset System ---
  void _confirmReset() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reset All Tokens"),
        content: const Text(
          "WARNING: This will delete all tokens from the database and reset the counter to 0. Are you sure?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              final success = await ApiService.resetTokens();
              if (success) {
                setState(() {
                  _lastIssuedToken = 0;
                  _servingToken = null;
                });
                _showSuccess("System reset successfully");
              } else {
                _showError("Failed to reset system");
              }
            },
            child: const Text("RESET"),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade600),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text("Clinic Admin Panel",
            style: TextStyle(color: Colors.black87)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_searching, color: Colors.blue),
            onPressed: _selectPrinter,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Connection Status
                  _StatusCard(
                    isConnected: isConnected,
                    deviceName: _selectedDevice?.name,
                  ),
                  const SizedBox(height: 20),

                  // 2. Admin Controls (Queue Management)
                  Row(
                    children: [
                      Expanded(
                        child: _InfoCard(
                          title: "NOW SERVING",
                          value: _servingToken?.toString() ?? "--",
                          color: Colors.green,
                          icon: Icons.person,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoCard(
                          title: "LAST ISSUED",
                          value: _lastIssuedToken.toString(),
                          color: Colors.blue,
                          icon: Icons.receipt,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Next Patient Button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _nextPatient,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text("COMPLETE CURRENT / NEXT PATIENT"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.green[700],
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.green.shade200)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _confirmReset,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text("RESET ALL TOKENS"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red[700],
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.red.shade200)),
                    ),
                  ),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _testToken,
                      icon: const Icon(Icons.bug_report),
                      label: const Text("TEST TOKEN"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black26,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.black12)),
                    ),
                  ),

                  const SizedBox(height: 32),
                  // OutlinedButton(
                  //   onPressed: _confirmReset,
                  //   style: OutlinedButton.styleFrom(
                  //     foregroundColor: Colors.red,
                  //     side: const BorderSide(color: Colors.red),
                  //     padding: const EdgeInsets.symmetric(
                  //       vertical: 14,
                  //       horizontal: 18,
                  //     ),
                  //     shape: RoundedRectangleBorder(
                  //       borderRadius: BorderRadius.circular(12),
                  //     ),
                  //   ),
                  //   child: Row(
                  //     children: [
                  //       const Text("Reset Tokens"),
                  //       const Icon(Icons.delete_forever),
                  //     ],
                  //   ),
                  // ),
                  const Divider(),
                  const SizedBox(height: 10),

                  // 3. Printer Controls
                  const Text(
                    "Token Printing",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1),
                  ),
                  const SizedBox(height: 16),

                  // The Card displaying what we are about to print (or last printed)
                  // _TokenCard(token: _lastIssuedToken),

                  TokenReceipt(
                    tokenNumber: _lastIssuedToken + 1,
                    onInitialized: (c) => _receiptController = c,
                  ),

                  const SizedBox(height: 24),

                  _ActionButtons(
                    isPrinting: _isPrinting,
                    canPrint: _selectedDevice != null,
                    onPrint: _printToken,
                    onReset: _confirmReset,
                  ),

                  // Hidden Receipt Widget (Used for generating the print image)
                  Opacity(
                    opacity: 0,
                    child: TokenReceipt(
                      tokenNumber:
                          _lastIssuedToken, // Always prints the latest generated
                      onInitialized: (c) => _receiptController = c,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ===================== UI COMPONENTS ===================== */

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool isConnected;
  final String? deviceName;

  const _StatusCard({
    required this.isConnected,
    required this.deviceName,
  });

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? Colors.green : Colors.orange;

    return Card(
      elevation: 0,
      color: isConnected ? Colors.green.shade50 : Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isConnected
                    ? "Connected to ${deviceName ?? "Printer"}"
                    : "No printer connected",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenCard extends StatelessWidget {
  final int token;

  const _TokenCard({required this.token});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 36,
          horizontal: 24,
        ),
        child: Column(
          children: [
            const Text(
              "LAST GENERATED TOKEN",
              style: TextStyle(
                letterSpacing: 1.2,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              token.toString(),
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final bool isPrinting;
  final bool canPrint;
  final VoidCallback onPrint;
  final VoidCallback onReset;

  const _ActionButtons({
    required this.isPrinting,
    required this.canPrint,
    required this.onPrint,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: (!canPrint || isPrinting) ? null : onPrint,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isPrinting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.print),
                      SizedBox(width: 8),
                      Text("GENERATE & PRINT"),
                    ],
                  ),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

/* ===================== RECEIPT (UNCHANGED) ===================== */

class TokenReceipt extends StatelessWidget {
  final int tokenNumber;
  final Function(ReceiptController) onInitialized;

  const TokenReceipt({
    super.key,
    required this.tokenNumber,
    required this.onInitialized,
  });

  @override
  Widget build(BuildContext context) {
    return Receipt(
      onInitialized: onInitialized,
      builder: (context) => Column(
        children: [
          const SizedBox(height: 24),
          const Text(
            "HOPE HOMOEOPATHY",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const Text(
            "Dr. Syed Saadullah",
            style: TextStyle(fontSize: 22),
          ),
          const SizedBox(height: 6),
          const Text(
            "Token No.",
            style: TextStyle(fontSize: 10),
          ),
          const SizedBox(height: 6),
          Text(
            tokenNumber.toString(),
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now()),
            style: const TextStyle(fontSize: 12),
          ),
          const Text(
            "Valid between 10:00 AM to 5:00 PM",
            style: TextStyle(fontSize: 12),
          ),
          const Text(
            "* Valid for 1 Patient Only *",
            style: TextStyle(fontSize: 12),
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Please wait. Thank you",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "To check status, visit:",
                    style: TextStyle(fontSize: 14),
                  ),
                  Text(
                    "https://hopehomeo-tokens.vercel.app/",
                    style: TextStyle(fontSize: 8),
                  ),
                ],
              ),
              Container(
                height: 50,
                width: 50,
                child: Image.asset("assets/qr.png"),
              )
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
