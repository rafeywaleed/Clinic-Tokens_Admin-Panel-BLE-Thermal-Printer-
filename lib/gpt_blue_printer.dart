import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BluetoothDevice? _selectedDevice;
  ReceiptController? _receiptController;

  int _tokenNumber = 1;
  bool _isPrinting = false;

  BluetoothConnectionState _connectionState = BluetoothConnectionState.idle;

  @override
  void initState() {
    super.initState();
    FlutterBluetoothPrinter.connectionStateNotifier.addListener(() {
      setState(() {
        _connectionState =
            FlutterBluetoothPrinter.connectionStateNotifier.value;
      });
    });
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

  Future<void> _printToken() async {
    if (_selectedDevice == null || _receiptController == null) {
      _showError("No printer selected");
      return;
    }

    if (_isPrinting) return;

    setState(() => _isPrinting = true);

    try {
      await _receiptController!.print(
        address: _selectedDevice!.address,
        keepConnected: true,
      );
      setState(() => _tokenNumber++);
    } catch (_) {
      _showError("Printing failed");
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reset Token"),
        content: const Text("Are you sure you want to reset the token number?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _tokenNumber = 1);
              Navigator.pop(context);
            },
            child: const Text("Reset"),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        elevation: 0,
        title: const Text("Token Printer"),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_searching),
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
                children: [
                  _StatusCard(
                    isConnected: isConnected,
                    deviceName: _selectedDevice?.name,
                  ),
                  const SizedBox(height: 24),
                  _TokenCard(token: _tokenNumber),
                  const SizedBox(height: 32),
                  _ActionButtons(
                    isPrinting: _isPrinting,
                    canPrint: _selectedDevice != null,
                    onPrint: _printToken,
                    onReset: _confirmReset,
                  ),
                  SizedBox(
                    height: 40,
                  ),
                  // const Spacer(),
                  TokenReceipt(
                    tokenNumber: _tokenNumber,
                    onInitialized: (c) => _receiptController = c,
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
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
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
              "CURRENT TOKEN",
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
                : const Text("PRINT TOKEN"),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: onReset,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 18,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Icon(Icons.restart_alt),
        ),
      ],
    );
  }
}

/* ===================== RECEIPT ===================== */

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
            "HOPE HOMEPATHY",
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
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Please wait. Thank you",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "To check status, visit:",
                    style: TextStyle(fontSize: 14),
                  ),
                  const Text(
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
