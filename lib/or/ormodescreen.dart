import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:provider/provider.dart';
import 'package:wiespl_contrl_panel/dicom/dicomscr.dart';
import 'package:wiespl_contrl_panel/main.dart';
import 'package:wiespl_contrl_panel/or/cleanpro.dart';
import 'package:wiespl_contrl_panel/or/orscreen.dart';
import 'package:wiespl_contrl_panel/pi_api/piscreen.dart';
import 'package:wiespl_contrl_panel/provider/espprovider.dart';
import 'package:wiespl_contrl_panel/provider/orsystemprovider.dart';
import 'package:wiespl_contrl_panel/provider/streamrecorderprovider.dart'; // ← add this import
import 'package:wiespl_contrl_panel/store/storescreen.dart';

// --- OR MODE SCREEN ---
class ORModeScreen extends StatelessWidget {
  ORModeScreen({super.key});

  final Color medicalTeal = const Color(0xFF00796B);

  @override
  Widget build(BuildContext context) {
    var pro = context.watch<ORSystemProvider>();
    var espPro = Provider.of<ESP32Provider>(context, listen: false);

    return Scaffold(
      body: Stack(
        children: [
          BackgroundAnimation(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // Header Row
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          pro.setViewMode(ORViewMode.dashboard);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                "BACK TO DASHBOARD",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: espPro.systemPower
                              ? Colors.green.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: espPro.systemPower
                                ? Colors.green
                                : Colors.red,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.power_settings_new,
                              color: espPro.systemPower
                                  ? Colors.green
                                  : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              espPro.systemPower ? "SYSTEM ON" : "SYSTEM OFF",
                              style: TextStyle(
                                color: espPro.systemPower
                                    ? Colors.green
                                    : Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        "OR MODE",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── All 5 items always visible — no scroll ──
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          // Row 1 — 3 equal items
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildGridItem(
                                    context,
                                    "OR SCREEN",
                                    Icons.desktop_windows,
                                    Colors.blue,
                                    () {
                                      // ✅ FIX: Register controller before navigating
                                      if (!Get.isRegistered<
                                        RecorderController
                                      >()) {
                                        Get.put(RecorderController());
                                      }
                                      openRecorderPage(context);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildGridItem(
                                    context,
                                    "PI",
                                    Icons.perm_identity_outlined,
                                    Colors.green,
                                    () => _navigateToPatientInfo(context),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildGridItem(
                                    context,
                                    "CLEAN",
                                    Icons.cleaning_services,
                                    Colors.purple,
                                    () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CleanControlApp(),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Row 2 — 2 wider items
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildGridItem(
                                    context,
                                    "DICOM",
                                    Icons.medical_services,
                                    Colors.orange,
                                    () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              DicomViewerPage(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildGridItem(
                                    context,
                                    "STORE",
                                    Icons.storefront_rounded,
                                    const Color(0xFF00ACC1),
                                    () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              StoreHomeScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Quick Status Bar
                  _buildQuickStatusBar(espPro),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.2),
                border: Border.all(color: color, width: 3),
              ),
              child: Icon(icon, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              "TAP TO VIEW",
              style: TextStyle(
                fontSize: 9,
                color: Colors.white.withOpacity(0.7),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatusBar(ESP32Provider esp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatusIcon(
            Icons.thermostat,
            "${esp.currentTemperatureAsDouble.toStringAsFixed(1)}°C",
            esp.currentTemperatureAsDouble > 23 ? Colors.orange : Colors.blue,
          ),
          Container(width: 1, height: 20, color: Colors.white.withOpacity(0.3)),
          _buildStatusIcon(
            Icons.water_drop,
            "${double.tryParse(esp.currentHumidity)?.toStringAsFixed(1) ?? "0"}%",
            Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _navigateToPatientInfo(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PatientListScreen()),
    );
  }

  static const platform = MethodChannel('app_launcher_channel');

  Future<void> _launchDroidRenderAndEnterPip(BuildContext context) async {
    const String packageName = 'com.luolai.droidrender';
    try {
      final bool? success = await platform.invokeMethod<bool>(
        'launchAppAndEnterPip',
        {'packageName': packageName},
      );
      if (success == null || !success) {
        _showErrorDialog(context, "Failed to launch DICOM viewer");
      }
    } on PlatformException catch (e) {
      debugPrint("Platform Error: ${e.code} - ${e.message}");
      _showErrorDialog(context, "App not found or permission denied");
    } catch (e) {
      debugPrint("Error launching app: $e");
      _showErrorDialog(context, "Unexpected error occurred");
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}

// BackgroundAnimation class
class BackgroundAnimation extends StatefulWidget {
  const BackgroundAnimation({super.key});

  @override
  State<BackgroundAnimation> createState() => _BackgroundAnimationState();
}

class _BackgroundAnimationState extends State<BackgroundAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromARGB(255, 44, 16, 90),
                Color.fromARGB(255, 68, 49, 127),
              ],
            ),
          ),
        );
      },
    );
  }
}
