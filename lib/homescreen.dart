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
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  bool _isOnline = true;
  Timer? _connectivityTimer;

  BluetoothConnectionState _connectionState = BluetoothConnectionState.idle;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

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

    // 2. Initialize connectivity monitoring
    _initConnectivity();

    // 3. Initial Data Fetch
    _refreshData();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _pulseController.dispose();
    _connectivitySubscription?.cancel();
    _connectivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    // Initial connectivity check
    await _checkConnectivity();

    // Listen for connectivity changes
    _connectivitySubscription = Connectivity()
            .onConnectivityChanged
            .listen((ConnectivityResult result) {
              _debounceConnectivityCheck();
            } as void Function(List<ConnectivityResult> event)?)
        as StreamSubscription<ConnectivityResult>?;
  }

  void _debounceConnectivityCheck() {
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer(const Duration(milliseconds: 500), () {
      _checkConnectivity();
    });
  }

  Future<void> _checkConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResult != ConnectivityResult.none;

      if (_isOnline != hasConnection) {
        setState(() => _isOnline = hasConnection);

        if (hasConnection) {
          // Auto-refresh when connection is restored
          _refreshData();
          _showSuccess("Back online");
        } else {
          _showError("No internet connection");
        }
      }
    } catch (e) {
      debugPrint("Connectivity check error: $e");
    }
  }

  Future<void> _refreshData() async {
    if (!_isOnline) {
      _showError("No internet connection. Please check your network.");
      return;
    }

    // Animate refresh button
    _refreshController.forward(from: 0);
    await _refreshController.animateTo(1, curve: AppAnimations.easeInOut);

    setState(() => _isLoading = true);

    try {
      final lastGen = await ApiService.getLastGeneratedToken();
      if (lastGen != null) _lastIssuedToken = lastGen;

      final status = await ApiService.getCurrentStatus();
      if (status != null && status['activeToken'] != null) {
        _servingToken = status['activeToken']['tokenNumber'];
      } else {
        _servingToken = null;
      }
    } catch (e) {
      _showError("Failed to fetch data. Please try again.");
    } finally {
      setState(() => _isLoading = false);
      _refreshController.reverse();
    }
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
    } catch (e) {
      _showError("Failed to select printer: ${e.toString()}");
    }
  }

  // --- LOGIC: Print New Token ---
  Future<void> _printToken() async {
    // Prevent printing if already printing
    if (_isPrinting) {
      _showError("Already printing. Please wait...");
      return;
    }

    // Check if printer is connected
    if (_selectedDevice == null || _receiptController == null) {
      _showError("Please connect a printer first");
      return;
    }

    // Check internet connectivity
    if (!_isOnline) {
      _showError("No internet connection. Cannot generate token.");
      return;
    }

    // Prevent printing if printer is already printing
    if (_connectionState == BluetoothConnectionState.printing) {
      _showError("Printer is currently printing. Please wait...");
      return;
    }

    setState(() => _isPrinting = true);

    try {
      // 1. Call Backend to Generate Token
      final newTokenNum = await ApiService.generateToken();

      if (newTokenNum == null) {
        throw Exception("Failed to generate token. Please try again.");
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
      if (e.toString().contains("timeout")) {
        _showError("Request timeout. Please check your connection.");
      } else if (e.toString().contains("SocketException")) {
        _showError("Network error. Please check your internet connection.");
      } else if (e.toString().contains("Bluetooth")) {
        _showError("Printer connection lost. Please reconnect.");
      } else {
        _showError("Printing failed: ${e.toString()}");
      }
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  Future<void> _testToken() async {
    // Check internet connectivity
    if (!_isOnline) {
      _showError("No internet connection. Please check your network.");
      return;
    }

    // Prevent test if system is already loading
    if (_isLoading) {
      _showError("System is busy. Please wait...");
      return;
    }

    try {
      final newTokenNum = await ApiService.generateToken();
      if (newTokenNum == null) {
        throw Exception("Failed to generate token");
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
    // Check internet connectivity
    if (!_isOnline) {
      _showError("No internet connection. Please check your network.");
      return;
    }

    // Prevent if already loading
    if (_isLoading) {
      _showError("System is busy. Please wait...");
      return;
    }

    // Check if there's a token to complete
    if (_servingToken == null) {
      _showError("No active token to complete");
      return;
    }

    // Check if we're at the last token (serving token equals last issued token)
    if (_servingToken != null && _servingToken! >= _lastIssuedToken) {
      _showError("No more tokens in queue. Please generate a new token first.");
      return;
    }

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
      if (e.toString().contains("No active token")) {
        _showError("No active token to complete");
      } else if (e.toString().contains("No more tokens")) {
        _showError(
            "No more tokens in queue. Please generate a new token first.");
      } else {
        _showError("Failed to update status: ${e.toString()}");
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- LOGIC: Reset System ---
  void _confirmReset() {
    // Check internet connectivity
    if (!_isOnline) {
      _showError("No internet connection. Please check your network.");
      return;
    }

    // Prevent reset if tokens are being generated or processed
    if (_isPrinting || _isLoading) {
      _showError("System is busy. Please wait...");
      return;
    }

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
            _showError("Failed to reset system. Please try again.");
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
    // Calculate if next patient button should be enabled
    final canCompleteToken = _isOnline &&
        !_isLoading &&
        _servingToken != null &&
        (_servingToken! < _lastIssuedToken || _servingToken == null);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Container(
            constraints: BoxConstraints(maxWidth: 600.w),
            margin: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Header
                _AppHeader(
                  onRefresh: _refreshData,
                  onBluetooth: _selectPrinter,
                  refreshController: _refreshController,
                  isOnline: _isOnline,
                  isLoading: _isLoading,
                ),

                SizedBox(height: 24.h),

                // Status Indicators
                Column(
                  children: [
                    if (!_isOnline)
                      _OfflineIndicator(pulseController: _pulseController),
                    _StatusIndicator(
                      isConnected: isConnected,
                      deviceName: _selectedDevice?.name,
                      pulseController: _pulseController,
                    ),
                  ],
                ),

                SizedBox(height: 32.h),

                // Token Stats Cards
                _TokenStats(
                  servingToken: _servingToken,
                  lastIssuedToken: _lastIssuedToken,
                  isLoading: _isLoading,
                  isOnline: _isOnline,
                ),

                SizedBox(height: 32.h),

                // Quick Actions
                _QuickActions(
                  onNextPatient: _nextPatient,
                  onReset: _confirmReset,
                  onTest: _testToken,
                  isLoading: _isLoading,
                  isOnline: _isOnline,
                  canCompleteToken: canCompleteToken,
                  isPrinting: _isPrinting,
                ),

                SizedBox(height: 40.h),

                // Token Preview
                _TokenPreview(
                  tokenNumber: _lastIssuedToken + 1,
                  onInitialized: (c) => _receiptController = c,
                ),

                SizedBox(height: 24.h),

                // Print Button
                _PrintButton(
                  isPrinting: _isPrinting,
                  canPrint: _selectedDevice != null && _isOnline && !_isLoading,
                  onPrint: _printToken,
                ),

                SizedBox(height: 40.h),
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
  final bool isOnline;
  final bool isLoading;

  const _AppHeader({
    required this.onRefresh,
    required this.onBluetooth,
    required this.refreshController,
    required this.isOnline,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16.h),
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
                  "Hope Homoeopathy",
                  style: AppTextStyles.displayMedium.copyWith(
                    color: AppColors.primary,
                    fontSize: 24.sp,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Token Management System",
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 6.w),
                    if (!isOnline)
                      Container(
                        width: 6.w,
                        height: 6.w,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.danger,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(width: 12.w),

          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: (isOnline && !isLoading) ? onRefresh : null,
                style: IconButton.styleFrom(
                  backgroundColor: (isOnline && !isLoading)
                      ? AppColors.surfaceElevated
                      : AppColors.surfaceElevated.withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  padding: EdgeInsets.all(12.w),
                  visualDensity: VisualDensity.compact,
                ),
                icon: RotationTransition(
                  turns: Tween(begin: 0.0, end: 1.0).animate(refreshController),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: (isOnline && !isLoading)
                        ? AppColors.primary
                        : AppColors.textTertiary,
                    size: 24.w,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              IconButton(
                onPressed: (!isLoading) ? onBluetooth : null,
                style: IconButton.styleFrom(
                  backgroundColor: (!isLoading)
                      ? AppColors.surfaceElevated
                      : AppColors.surfaceElevated.withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  padding: EdgeInsets.all(12.w),
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(
                  Icons.bluetooth_rounded,
                  color:
                      (!isLoading) ? AppColors.primary : AppColors.textTertiary,
                  size: 24.w,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfflineIndicator extends StatelessWidget {
  final AnimationController pulseController;

  const _OfflineIndicator({required this.pulseController});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: pulseController,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.danger.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 18.w, color: AppColors.danger),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                "Offline Mode - Limited Functionality",
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 12.sp,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: isConnected
              ? AppColors.accent.withOpacity(0.1)
              : AppColors.warning.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isConnected
                ? AppColors.accent.withOpacity(0.3)
                : AppColors.warning.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 12.w,
              height: 12.w,
              margin: EdgeInsets.only(right: 16.w),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? AppColors.accent : AppColors.warning,
                boxShadow: [
                  BoxShadow(
                    color: isConnected ? AppColors.accent : AppColors.warning,
                    blurRadius: 8.w,
                    spreadRadius: isConnected ? 2.w : 0,
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
                      fontSize: 12.sp,
                      letterSpacing: 1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    isConnected
                        ? deviceName ?? "Bluetooth Printer"
                        : "Tap Bluetooth icon to connect",
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w500,
                      color: isConnected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
  final bool isOnline;

  const _TokenStats({
    required this.servingToken,
    required this.lastIssuedToken,
    required this.isLoading,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: "NOW SERVING",
            value: servingToken?.toString() ?? "--",
            subtitle: isOnline ? "Current Patient" : "Data may be outdated",
            icon: Icons.person_pin_circle_rounded,
            color: AppColors.accent,
            isLoading: isLoading && isOnline,
            isOnline: isOnline,
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: _StatCard(
            title: "LAST ISSUED",
            value: lastIssuedToken.toString(),
            subtitle: isOnline ? "Previous Token" : "Cached Data",
            icon: Icons.receipt_long_rounded,
            color: AppColors.primary,
            isLoading: isLoading && isOnline,
            isOnline: isOnline,
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
  final bool isOnline;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isLoading,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimations.medium,
      curve: AppAnimations.easeInOut,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20.w,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.labelSmall.copyWith(
                    fontSize: 12.sp,
                    color: AppColors.textTertiary,
                    letterSpacing: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon,
                  color: color.withOpacity(isOnline ? 0.8 : 0.4), size: 20.w),
            ],
          ),
          SizedBox(height: 16.h),
          SizedBox(
            height: 48.h,
            child: AnimatedSwitcher(
              duration: AppAnimations.quick,
              child: isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.w,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    )
                  : Text(
                      value,
                      style: AppTextStyles.displayLarge.copyWith(
                        fontSize: 40.sp,
                        color: color.withOpacity(isOnline ? 1.0 : 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            subtitle,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 14.sp,
              color: AppColors.textTertiary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
  final bool isOnline;
  final bool canCompleteToken;
  final bool isPrinting;

  const _QuickActions({
    required this.onNextPatient,
    required this.onReset,
    required this.onTest,
    required this.isLoading,
    required this.isOnline,
    required this.canCompleteToken,
    required this.isPrinting,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: AppColors.border, height: 1.h),
        SizedBox(height: 6.h),
        _ActionButton(
          icon: Icons.navigate_next_rounded,
          label: "Next Patient",
          color: AppColors.accent,
          onPressed: canCompleteToken ? onNextPatient : null,
          isLoading: isLoading,
          isOnline: isOnline,
          tooltip: canCompleteToken
              ? "Move to next patient"
              : "No more tokens in queue. Generate a new token first.",
        ),
        _ActionButton(
          icon: Icons.restart_alt_rounded,
          label: "Reset System",
          color: AppColors.danger,
          onPressed: (isOnline && !isLoading && !isPrinting) ? onReset : null,
          isOnline: isOnline,
          tooltip: (isOnline && !isLoading && !isPrinting)
              ? "Reset all tokens"
              : "System is busy. Please wait...",
        ),
        // _ActionButton(
        //   icon: Icons.bug_report_rounded,
        //   label: "Test Token",
        //   color: AppColors.textTertiary,
        //   onPressed: (isOnline && !isLoading && !isPrinting) ? onTest : null,
        //   isLoading: isLoading,
        //   isOnline: isOnline,
        //   tooltip: (isOnline && !isLoading && !isPrinting)
        //       ? "Generate test token"
        //       : "System is busy. Please wait...",
        // ),
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
  final bool isOnline;
  final String? tooltip;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
    this.isLoading = false,
    this.isOnline = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(12.w),
      child: Tooltip(
        message: tooltip ?? '',
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withOpacity(
              onPressed != null ? 0.1 : 0.05,
            ),
            foregroundColor: color.withOpacity(onPressed != null ? 1.0 : 0.3),
            elevation: 0,
            padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                Container(
                  width: 26.w,
                  height: 26.w,
                  padding: EdgeInsets.all(4.w),
                  child: CircularProgressIndicator(
                    strokeWidth: 3.w,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                )
              else
                Icon(icon,
                    size: 26.w,
                    color: color.withOpacity(onPressed != null ? 1.0 : 0.3)),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.labelLarge.copyWith(
                    fontSize: 16.sp,
                    color: color.withOpacity(onPressed != null ? 1.0 : 0.3),
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
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
        borderRadius: BorderRadius.circular(24.r),
        side: BorderSide(color: AppColors.border, width: 1.w),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
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
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: canPrint
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 20.w,
                  offset: Offset(0, 10.h),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canPrint && !isPrinting ? onPrint : null,
          borderRadius: BorderRadius.circular(16.r),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 24.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isPrinting)
                  SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.w,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                else
                  Icon(Icons.print_rounded,
                      color: canPrint
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                      size: 24.w),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    isPrinting ? "PRINTING..." : "GENERATE & PRINT TOKEN",
                    style: AppTextStyles.labelLarge.copyWith(
                      fontSize: 16.sp,
                      color: canPrint
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
          SizedBox(height: 24.h),
          Text(
            "HOPE HOMOEOPATHY",
            style: TextStyle(
              fontSize: 26.sp,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            "Dr. Syed Saadullah",
            style: TextStyle(
              fontSize: 22.sp,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 6.h),
          Text(
            "Token No.",
            style: TextStyle(
              fontSize: 10.sp,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6.h),
          Text(
            tokenNumber.toString(),
            style: TextStyle(
              fontSize: 48.sp,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 15.h),
          Text(
            DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now()),
            style: TextStyle(
              fontSize: 12.sp,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            "Valid between 10:00 AM to 5:00 PM",
            style: TextStyle(
              fontSize: 12.sp,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            "* Valid for 1 Patient Only *",
            style: TextStyle(
              fontSize: 12.sp,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Divider(thickness: 1.w),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Please wait. Thank you",
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        "To check status, visit:",
                        style: TextStyle(
                          fontSize: 14.sp,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        "https://hopehomeo-tokens.vercel.app/",
                        style: TextStyle(
                          fontSize: 8.sp,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                Container(
                  height: 50.w,
                  width: 50.w,
                  child: Image.asset("assets/qr.png", fit: BoxFit.contain),
                )
              ],
            ),
          ),
          SizedBox(height: 32.h),
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
        constraints: BoxConstraints(maxWidth: 400.w),
        margin: EdgeInsets.symmetric(horizontal: 20.w),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 40.w,
              spreadRadius: -10.w,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(32.w),
              child: Column(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 64.w,
                    color: AppColors.warning.withOpacity(0.8),
                  ),
                  SizedBox(height: 24.h),
                  Text(
                    title,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontSize: 24.sp,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    content,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 16.sp,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24.r),
                  bottomRight: Radius.circular(24.r),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          onSecondaryPressed ?? () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        side: BorderSide(color: AppColors.border, width: 1.w),
                      ),
                      child: Text(
                        secondaryButtonText,
                        style: AppTextStyles.labelLarge.copyWith(
                          fontSize: 16.sp,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onPrimaryPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryButtonColor,
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(
                        primaryButtonText,
                        style: AppTextStyles.labelLarge.copyWith(
                          fontSize: 16.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            width: 24.w,
            height: 24.w,
            margin: EdgeInsets.only(right: 12.w),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 16.w,
              color: AppColors.accent,
            ),
          ),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 14.sp,
                color: Colors.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
      ),
      margin: EdgeInsets.all(20.w),
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
    );
  }

  static SnackBar error({required String message}) {
    return SnackBar(
      content: Row(
        children: [
          Container(
            width: 24.w,
            height: 24.w,
            margin: EdgeInsets.only(right: 12.w),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 16.w,
              color: AppColors.danger,
            ),
          ),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 14.sp,
                color: Colors.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
      ),
      margin: EdgeInsets.all(20.w),
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
    );
  }
}
