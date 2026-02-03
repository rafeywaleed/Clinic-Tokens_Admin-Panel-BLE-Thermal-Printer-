import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer_library.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:token_printer/api_service.dart';
import 'package:token_printer/colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  BluetoothDevice? _selectedDevice;
  ReceiptController? _receiptController;

  // Animation controllers
  late AnimationController _refreshController;
  late AnimationController _pulseController;

  // State Variables
  int _lastIssuedToken = 0;
  int? _servingToken;
  bool _isPrinting = false;
  bool _isLoading = false;

  BluetoothConnectionState _connectionState = BluetoothConnectionState.idle;

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers
    _refreshController = AnimationController(
      vsync: this,
      duration: AppAnimations.medium,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

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

  @override
  void dispose() {
    _refreshController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    // Animate refresh button
    _refreshController.forward(from: 0);
    await _refreshController.animateTo(1, curve: AppAnimations.easeInOut);

    setState(() => _isLoading = true);

    final lastGen = await ApiService.getLastGeneratedToken();
    if (lastGen != null) _lastIssuedToken = lastGen;

    final status = await ApiService.getCurrentStatus();
    if (status != null && status['activeToken'] != null) {
      _servingToken = status['activeToken']['tokenNumber'];
    } else {
      _servingToken = null;
    }

    setState(() => _isLoading = false);
    _refreshController.reverse();
  }

  bool get isConnected =>
      _connectionState == BluetoothConnectionState.printing ||
      _connectionState == BluetoothConnectionState.completed;

  Future<void> _selectPrinter() async {
    try {
      final device = await FlutterBluetoothPrinter.selectDevice(context);
      if (device != null) {
        setState(() => _selectedDevice = device);
        _showSuccess("Printer connected: ${device.name}");
      }
    } catch (_) {
      _showError("Failed to select printer");
    }
  }

  // --- LOGIC: Print New Token ---
  Future<void> _printToken() async {
    if (_selectedDevice == null || _receiptController == null) {
      _showError("Please connect a printer first");
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
      await Future.delayed(const Duration(milliseconds: 100));

      await _receiptController!.print(
        address: _selectedDevice!.address,
        keepConnected: true,
      );

      _showSuccess("Token $newTokenNum generated & printed");
      _refreshData();
    } catch (e) {
      _showError("Printing failed: ${e.toString()}");
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  Future<void> _testToken() async {
    try {
      final newTokenNum = await ApiService.generateToken();
      if (newTokenNum == null) {
        throw Exception("Backend failed to generate token");
      }

      setState(() => _lastIssuedToken = newTokenNum);
      _showSuccess("Test Token $newTokenNum generated");
      _refreshData();
    } catch (e) {
      _showError("Test failed: ${e.toString()}");
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
        _showSuccess("Now serving Token ${result['tokenNumber']}");
      } else {
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
      builder: (_) => CustomDialog(
        title: "Reset All Tokens",
        content:
            "This will permanently delete all tokens and reset the system to initial state. This action cannot be undone.",
        primaryButtonText: "Confirm Reset",
        primaryButtonColor: AppColors.danger,
        onPrimaryPressed: () async {
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
        secondaryButtonText: "Cancel",
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      CustomSnackBar.error(message: message),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      CustomSnackBar.success(message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          // Added ScrollView here
          physics: const BouncingScrollPhysics(),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Header
                _AppHeader(
                  onRefresh: _refreshData,
                  onBluetooth: _selectPrinter,
                  refreshController: _refreshController,
                ),

                const SizedBox(height: 24),

                // Status Indicator
                _StatusIndicator(
                  isConnected: isConnected,
                  deviceName: _selectedDevice?.name,
                  pulseController: _pulseController,
                ),

                const SizedBox(height: 32),

                // Token Stats Cards
                _TokenStats(
                  servingToken: _servingToken,
                  lastIssuedToken: _lastIssuedToken,
                  isLoading: _isLoading,
                ),

                const SizedBox(height: 32),

                // Quick Actions
                _QuickActions(
                  onNextPatient: _nextPatient,
                  onReset: _confirmReset,
                  onTest: _testToken,
                  isLoading: _isLoading,
                ),

                const SizedBox(height: 40),

                // Token Preview
                _TokenPreview(
                  tokenNumber: _lastIssuedToken + 1,
                  onInitialized: (c) => _receiptController = c,
                ),

                const SizedBox(height: 24),

                // Print Button
                _PrintButton(
                  isPrinting: _isPrinting,
                  canPrint: _selectedDevice != null,
                  onPrint: _printToken,
                ),

                const SizedBox(height: 40),

                // // Hidden Receipt Widget
                // Opacity(
                //   opacity: 0,
                //   child: TokenReceipt(
                //     tokenNumber: _lastIssuedToken,
                //     onInitialized: (c) => _receiptController = c,
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ===================== ENHANCED UI COMPONENTS ===================== */

class _AppHeader extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onBluetooth;
  final AnimationController refreshController;

  const _AppHeader({
    required this.onRefresh,
    required this.onBluetooth,
    required this.refreshController,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;
    final isVerySmallScreen = screenWidth < 350;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Clinic Info Column
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Hope Homeopathy",
                  style: AppTextStyles.displayMedium.copyWith(
                    color: AppColors.primary,
                    fontSize: 24,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // const SizedBox(height: 4),
                Text(
                  "Token Management System",
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Action Buttons
          Container(
            constraints: BoxConstraints(
              maxWidth: isVerySmallScreen ? 100 : 120,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onRefresh,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.all(isVerySmallScreen ? 10 : 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: AppColors.primary,
                    size: isVerySmallScreen ? 20 : 24,
                  ),
                ),
                if (!isVerySmallScreen) const SizedBox(width: 8),
                IconButton(
                  onPressed: onBluetooth,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.all(isVerySmallScreen ? 10 : 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    Icons.bluetooth_rounded,
                    color: AppColors.primary,
                    size: isVerySmallScreen ? 20 : 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final bool isConnected;
  final String? deviceName;
  final AnimationController pulseController;

  const _StatusIndicator({
    required this.isConnected,
    required this.deviceName,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: pulseController,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isConnected
              ? AppColors.accent.withOpacity(0.1)
              : AppColors.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isConnected
                ? AppColors.accent.withOpacity(0.3)
                : AppColors.warning.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? AppColors.accent : AppColors.warning,
                boxShadow: [
                  BoxShadow(
                    color: isConnected ? AppColors.accent : AppColors.warning,
                    blurRadius: 8,
                    spreadRadius: isConnected ? 2 : 0,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConnected ? "PRINTER CONNECTED" : "NO PRINTER CONNECTED",
                    style: AppTextStyles.labelSmall.copyWith(
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isConnected
                        ? deviceName ?? "Bluetooth Printer"
                        : "Tap Bluetooth icon to connect",
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isConnected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenStats extends StatelessWidget {
  final int? servingToken;
  final int lastIssuedToken;
  final bool isLoading;

  const _TokenStats({
    required this.servingToken,
    required this.lastIssuedToken,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: "NOW SERVING",
            value: servingToken?.toString() ?? "--",
            subtitle: "Current Patient",
            icon: Icons.person_pin_circle_rounded,
            color: AppColors.accent,
            isLoading: isLoading,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatCard(
            title: "LAST ISSUED",
            value: lastIssuedToken.toString(),
            subtitle: "Previous Token",
            icon: Icons.receipt_long_rounded,
            color: AppColors.primary,
            isLoading: isLoading,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isLoading;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimations.medium,
      curve: AppAnimations.easeInOut,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: color.withOpacity(0.8), size: 20),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: AppAnimations.quick,
            child: isLoading
                ? SizedBox(
                    height: 48,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  )
                : Text(
                    value,
                    style: AppTextStyles.displayLarge.copyWith(
                      fontSize: 40,
                      color: color,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onNextPatient;
  final VoidCallback onReset;
  final VoidCallback onTest;
  final bool isLoading;

  const _QuickActions({
    required this.onNextPatient,
    required this.onReset,
    required this.onTest,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Text(
        //   "Queue Management",
        //   style: AppTextStyles.titleMedium.copyWith(
        //     color: AppColors.textSecondary,
        //   ),
        // ),
        // const SizedBox(height: 16),
        Divider(color: AppColors.border, height: 1),
        SizedBox(height: 6),
        _ActionButton(
          icon: Icons.navigate_next_rounded,
          label: "Next Patient",
          color: AppColors.accent,
          onPressed: isLoading ? null : onNextPatient,
          isLoading: isLoading,
        ),
        _ActionButton(
          icon: Icons.restart_alt_rounded,
          label: "Reset System",
          color: AppColors.danger,
          onPressed: onReset,
        ),
        _ActionButton(
          icon: Icons.bug_report_rounded,
          label: "Test Token",
          color: AppColors.textTertiary,
          onPressed: isLoading ? null : onTest,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(isLoading ? 0.3 : 0.1),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              Container(
                width: 26,
                height: 26,
                padding: const EdgeInsets.all(4),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              )
            else
              Icon(icon, size: 26),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.labelLarge.copyWith(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenPreview extends StatelessWidget {
  final int tokenNumber;
  final Function(ReceiptController) onInitialized;

  const _TokenPreview({
    required this.tokenNumber,
    required this.onInitialized,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.surface, AppColors.surfaceElevated],
            ),
          ),
          child: TokenReceipt(
            tokenNumber: tokenNumber,
            onInitialized: onInitialized,
          ),
        ),
      ),
    );
  }
}

class _PrintButton extends StatelessWidget {
  final bool isPrinting;
  final bool canPrint;
  final VoidCallback onPrint;

  const _PrintButton({
    required this.isPrinting,
    required this.canPrint,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimations.medium,
      curve: AppAnimations.easeInOut,
      decoration: BoxDecoration(
        gradient: canPrint
            ? const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : LinearGradient(
                colors: [AppColors.textTertiary, AppColors.textTertiary],
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: canPrint
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canPrint && !isPrinting ? onPrint : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isPrinting)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                else
                  const Icon(Icons.print_rounded,
                      color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Text(
                  isPrinting ? "PRINTING..." : "GENERATE & PRINT TOKEN",
                  style: AppTextStyles.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ===================== ENHANCED RECEIPT ===================== */

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

/* ===================== CUSTOM DIALOGS ===================== */

class CustomDialog extends StatelessWidget {
  final String title;
  final String content;
  final String primaryButtonText;
  final Color primaryButtonColor;
  final String secondaryButtonText;
  final VoidCallback onPrimaryPressed;
  final VoidCallback? onSecondaryPressed;

  const CustomDialog({
    required this.title,
    required this.content,
    required this.primaryButtonText,
    this.primaryButtonColor = AppColors.primary,
    required this.secondaryButtonText,
    required this.onPrimaryPressed,
    this.onSecondaryPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 40,
              spreadRadius: -10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 64,
                    color: AppColors.warning.withOpacity(0.8),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    content,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          onSecondaryPressed ?? () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: Text(
                        secondaryButtonText,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onPrimaryPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryButtonColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        primaryButtonText,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== CUSTOM SNACKBARS ===================== */

class CustomSnackBar {
  static SnackBar success({required String message}) {
    return SnackBar(
      content: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.accent,
            ),
          ),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }

  static SnackBar error({required String message}) {
    return SnackBar(
      content: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: AppColors.danger,
            ),
          ),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }
}
