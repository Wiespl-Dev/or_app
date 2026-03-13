import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import 'package:wiespl_contrl_panel/clock/clockui.dart';
import 'package:wiespl_contrl_panel/clock/filp_component.dart';
import 'package:wiespl_contrl_panel/main.dart';
import 'package:wiespl_contrl_panel/or/ormodescreen.dart';
import 'package:wiespl_contrl_panel/provider/espprovider.dart';
import 'package:wiespl_contrl_panel/provider/orsystemprovider.dart';

class MedicalDashboard extends StatelessWidget {
  final VoidCallback onLogout;
  const MedicalDashboard({super.key, required this.onLogout});

  final Color medicalTeal = const Color(0xFF00796B);
  final Color darkText = const Color.fromARGB(255, 228, 234, 236);

  ScreenSize _getScreenSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return ScreenSize.mobile;
    if (width < 1200) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  @override
  Widget build(BuildContext context) {
    var systemPro = context.watch<ORSystemProvider>();

    if (systemPro.viewMode == ORViewMode.orMode) {
      return ORModeScreen();
    }

    final espPro = Provider.of<ESP32Provider>(context);

    return Scaffold(
      body: Stack(
        children: [
          BackgroundAnimation(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildORModeButton(context, systemPro),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        onPressed: () async {
                          final shouldLogout = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Logout'),
                              content: const Text(
                                'Are you sure you want to logout?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context, true);
                                    Navigator.pop(context, true);
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Logout'),
                                ),
                              ],
                            ),
                          );

                          if (shouldLogout == true) {
                            onLogout();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        _buildStaticPanel(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: CustomPaint(
                              painter: ProfessionalClockPainter(systemPro.now),
                              child: Container(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        _buildFlippingTimerPanel(systemPro),
                        const SizedBox(width: 15),
                        _buildRightSidebar(systemPro, espPro),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        _buildControlCard(
                          "LIGHTING",
                          Icons.wb_sunny_outlined,
                          espPro.allLightStates
                              .take(4)
                              .where((l) => l)
                              .length
                              .toString(),
                          onTap: () => _showLightControl(context, espPro),
                        ),
                        _buildTempCard(systemPro, espPro),
                        _buildHumidityCard(systemPro, espPro),
                        _buildPressureCard(espPro),
                        // FIX: MUSIC card now correctly opens the music player
                        // by calling toggleMusicFlip which flips _buildFlippingTimerPanel
                        _buildControlCard(
                          "MUSIC",
                          systemPro.isMusicPlaying
                              ? Icons.music_note
                              : Icons.music_off,
                          systemPro.isMusicPlaying ? "ON" : "OFF",
                          onTap: systemPro.toggleMusicFlip,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildFooter(context, systemPro, espPro),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPressureCard(ESP32Provider esp) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Consumer<ESP32Provider>(
          builder: (context, esp, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.13),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.8),
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "PRESSURE",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: darkText.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    esp.isPressurePositive
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    color: esp.getPressureColor(),
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${esp.getFormattedPressure()} Pa",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: esp.getPressureColor(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildORModeButton(BuildContext context, ORSystemProvider pro) {
    return Align(
      alignment: Alignment.topRight,
      child: GestureDetector(
        onTap: () {
          pro.setViewMode(ORViewMode.orMode);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.medical_services, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                "OR MODE",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightSidebar(ORSystemProvider pro, ESP32Provider esp) {
    return Expanded(
      flex: 1,
      child: MedicalFlipCard(
        isFlipped: pro.showRightPanelFlip || pro.showMGPSFlip,
        front: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Consumer<ESP32Provider>(
              builder: (context, esp, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  child: _buildCircleSetting(
                    Icons.air,
                    "HEPA",
                    true,
                    null,
                    color: esp.sensor10Color,
                  ),
                );
              },
            ),
            const SizedBox(height: 25),
            _buildCircleSetting(
              Icons.settings,
              "CONFIG",
              true,
              pro.toggleRightPanelFlip,
            ),
            const SizedBox(height: 25),
            Consumer<ESP32Provider>(
              builder: (context, esp, child) {
                return _buildCircleSetting(
                  Icons.gas_meter_outlined,
                  "MGPS",
                  true,
                  pro.toggleMGPSFlip,
                  color: esp.mgpsColor,
                );
              },
            ),
          ],
        ),
        back: pro.showMGPSFlip ? _buildMGPSBack(pro) : _buildConfigBack(pro),
      ),
    );
  }

  Widget _buildConfigBack(ORSystemProvider pro) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "SYSTEM CONFIG",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        _buildCircleSetting(
          Icons.language,
          "ENG",
          true,
          null,
          color: Colors.blue,
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: pro.toggleRightPanelFlip,
          child: const Text(
            "BACK",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildMGPSBack(ORSystemProvider pro) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "MGPS STATUS",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 10,
              color: Colors.orange,
            ),
          ),
          const Divider(),
          _gasStatusRow("Oxygen", Colors.green, 0),
          _gasStatusRow("Nitrogen", Colors.blue, 1),
          _gasStatusRow("Vacuum", Colors.yellow[700]!, 2),
          _gasStatusRow("Nitrous Oxide", Colors.blue[900]!, 3),
          const Spacer(),
          TextButton(
            onPressed: pro.toggleMGPSFlip,
            child: const Text(
              "CLOSE",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gasStatusRow(String title, Color healthyColor, int sensorIndex) {
    return Consumer<ESP32Provider>(
      builder: (context, esp, child) {
        final isHealthy = esp.isSensorHealthy(sensorIndex);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: isHealthy ? healthyColor : Colors.red,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  _BlinkingText(
                    text: title,
                    isBlinking: !isHealthy,
                    healthyColor: healthyColor,
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isHealthy ? healthyColor : Colors.red).withOpacity(
                    0.2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isHealthy ? "OK" : "FAULT",
                  style: TextStyle(
                    color: isHealthy ? healthyColor : Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTempCard(ORSystemProvider ui, ESP32Provider esp) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: MedicalFlipCard(
          isFlipped: ui.showTempSettings,
          front: Consumer<ESP32Provider>(
            builder: (context, esp, child) {
              return _buildCardContent(
                "TEMP",
                Icons.thermostat,
                "${esp.currentTemperatureAsDouble.toStringAsFixed(1)}°C",
                ui.toggleTempFlip,
              );
            },
          ),
          back: _buildAdjuster(
            "SET TEMP",
            esp.pendingTemperature,
            (v) => esp.updatePendingTemperature(v),
            () async {
              ui.toggleTempFlip();
              await esp.setTemperature(esp.pendingTemperature);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHumidityCard(ORSystemProvider ui, ESP32Provider esp) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: MedicalFlipCard(
          isFlipped: ui.showHumiditySettings,
          front: Consumer<ESP32Provider>(
            builder: (context, esp, child) {
              return _buildCardContent(
                "HUMIDITY",
                Icons.water_drop_outlined,
                "${double.tryParse(esp.currentHumidity)?.toStringAsFixed(1) ?? "0.0"}%",
                ui.toggleHumidityFlip,
              );
            },
          ),
          back: _buildAdjuster(
            "SET RH %",
            esp.humiditySetpointAsDouble,
            (v) => esp.adjustHumidity(v),
            () async {
              ui.toggleHumidityFlip();
              await esp.setHumiditySetpoint();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    ORSystemProvider pro,
    ESP32Provider esp,
  ) {
    final screenSize = _getScreenSize(context);
    return Row(
      children: [
        // System Power Button
        GestureDetector(
          onTap: () async {
            bool newState = !esp.systemPower;
            if (!newState) {
              bool confirm = await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Confirm"),
                  content: const Text(
                    "Are you sure you want to turn off the system?",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text("Yes"),
                    ),
                  ],
                ),
              );
              if (!confirm) return;
            }
            await esp.toggleSystemPower(newState);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: esp.systemPower
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              border: Border.all(
                color: esp.systemPower ? Colors.green : Colors.red,
                width: 3,
              ),
            ),
            child: Icon(
              Icons.power_settings_new,
              color: esp.systemPower ? Colors.green : Colors.red,
              size: 32,
            ),
          ),
        ),

        const SizedBox(width: 20),

        // HEPA Status
        Consumer<ESP32Provider>(
          builder: (context, esp, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: (esp.sensor10Color == Colors.green)
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: esp.sensor10Color == Colors.green
                      ? Colors.green
                      : Colors.red,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    esp.sensor10Color == Colors.green
                        ? Icons.air
                        : Icons.warning,
                    color: esp.sensor10Color == Colors.green
                        ? Colors.green
                        : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    esp.sensor10Color == Colors.green
                        ? "HEPA Healthy"
                        : "HEPA Fault",
                    style: TextStyle(
                      color: esp.sensor10Color == Colors.green
                          ? Colors.green
                          : Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const Spacer(),

        // Logo
        Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.0),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    height: screenSize == ScreenSize.tablet ? 100 : 120,
                    width: screenSize == ScreenSize.tablet ? 200 : 270,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1.0,
                      ),
                    ),
                    child: const SizedBox(),
                  ),
                ),
              ),
            ),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20.0),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    height: screenSize == ScreenSize.tablet ? 80 : 100,
                    width: screenSize == ScreenSize.tablet ? 180 : 250,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1.0,
                      ),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/app_logo-removebg-preview.png',
                        height: screenSize == ScreenSize.tablet ? 80 : 100,
                        width: screenSize == ScreenSize.tablet ? 240 : 300,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStaticPanel({required Widget child, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(
          color: const Color.fromARGB(3, 18, 10, 45),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _buildCardContent(
    String title,
    IconData icon,
    String value,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: darkText.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Icon(icon, color: medicalTeal, size: 36),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjuster(
    String title,
    double val,
    Function(double) onAdjust,
    VoidCallback close,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                color: Colors.white,
              ),
              onPressed: () => onAdjust(-0.5),
            ),
            Text(
              val.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: medicalTeal,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              onPressed: () => onAdjust(0.5),
            ),
          ],
        ),
        TextButton(
          onPressed: close,
          child: const Text(
            "DONE",
            style: TextStyle(fontSize: 10, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildControlCard(
    String title,
    IconData icon,
    String value, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.13),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.8), width: 2.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: _buildCardContent(title, icon, value, onTap ?? () {}),
      ),
    );
  }

  Widget _buildFlippingTimerPanel(ORSystemProvider pro) {
    return Expanded(
      flex: 2,
      child: MedicalFlipCard(
        isFlipped: pro.showMusic,
        front: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "OR CONTROL PANEL",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: darkText,
              ),
            ),
            Text(
              pro.formattedFullDate,
              style: TextStyle(fontSize: 12, color: darkText.withOpacity(0.6)),
            ),
            const Divider(height: 30, indent: 60, endIndent: 60),
            Text(
              pro.stopwatchDisplay,
              style: TextStyle(
                fontSize: 60,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStopwatchBtn(
                  icon: Icons.refresh,
                  label: "RESET",
                  onTap: pro.resetStopwatch,
                ),
                const SizedBox(width: 30),
                _buildStopwatchBtn(
                  icon: pro.timerRunning ? Icons.pause : Icons.play_arrow,
                  label: pro.timerRunning ? "PAUSE" : "START",
                  onTap: pro.toggleStopwatch,
                  primary: true,
                ),
              ],
            ),
          ],
        ),
        back: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music, color: medicalTeal, size: 30),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                pro.currentTrack,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: darkText,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.skip_previous, color: medicalTeal),
                  onPressed: pro.prevTrack,
                ),
                CircleAvatar(
                  backgroundColor: medicalTeal,
                  child: IconButton(
                    icon: Icon(
                      pro.isMusicPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    // FIX: calls togglePlayPause which now properly plays audio
                    onPressed: pro.togglePlayPause,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.skip_next, color: medicalTeal),
                  onPressed: pro.nextTrack,
                ),
              ],
            ),
            TextButton(
              onPressed: pro.toggleMusicFlip,
              child: const Text(
                "CLOSE PLAYER",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopwatchBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: CircleAvatar(
            radius: 22,
            backgroundColor: primary ? medicalTeal : Colors.teal,
            child: Icon(
              icon,
              color: primary ? Colors.white : medicalTeal,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildCircleSetting(
    IconData icon,
    String label,
    bool isOn,
    VoidCallback? onTap, {
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: isOn ? (color ?? medicalTeal) : Colors.black12,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isOn ? (color ?? medicalTeal) : Colors.black26,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showLightControl(BuildContext context, ESP32Provider pro) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          content: Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color.fromARGB(50, 33, 33, 33).withOpacity(0.5),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "LIGHTING CONTROL",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 24),

                ...List.generate(4, (i) {
                  final isOn = pro.getLightState(i);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb,
                          color: isOn
                              ? const Color.fromARGB(255, 121, 81, 185)
                              : Colors.grey.shade600,
                          size: 32,
                          shadows: isOn
                              ? [
                                  Shadow(
                                    color: const Color.fromARGB(
                                      255,
                                      121,
                                      81,
                                      185,
                                    ).withOpacity(0.6),
                                    blurRadius: 12,
                                  ),
                                ]
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            "ZONE ${i + 1}",
                            style: TextStyle(
                              fontSize: 16,
                              color: isOn ? Colors.white : Colors.grey.shade400,
                              fontWeight: isOn
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Switch.adaptive(
                          value: isOn,
                          activeColor: const Color.fromARGB(255, 121, 81, 185),
                          onChanged: (val) async {
                            try {
                              await pro.toggleLight(i + 1, val);
                              setState(() {});
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "ESP32 Offline: Check your Wi-Fi connection",
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }),

                const Divider(color: Colors.white24, height: 32),

                Row(
                  children: [
                    Builder(
                      builder: (context) {
                        final allOn = pro.allLightStates
                            .take(4)
                            .every((on) => on);
                        return Icon(
                          Icons.lightbulb_outline,
                          color: allOn
                              ? const Color.fromARGB(255, 121, 81, 185)
                              : Colors.grey.shade600,
                          size: 28,
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        "ALL LIGHTS",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: pro.allLightStates.take(4).every((on) => on),
                      activeColor: const Color.fromARGB(255, 121, 81, 185),
                      onChanged: (val) async {
                        await pro.toggleAllLights(val);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white24,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("DONE"),
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

class _BlinkingText extends StatefulWidget {
  final String text;
  final bool isBlinking;
  final Color healthyColor;

  const _BlinkingText({
    required this.text,
    required this.isBlinking,
    required this.healthyColor,
  });

  @override
  State<_BlinkingText> createState() => _BlinkingTextState();
}

class _BlinkingTextState extends State<_BlinkingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.2,
    ).animate(_controller);

    if (widget.isBlinking) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _BlinkingText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.isBlinking) {
      _controller.stop();
      _controller.value = 1.0;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isBlinking) {
      return Text(
        widget.text,
        style: TextStyle(
          color: widget.healthyColor,
          fontWeight: FontWeight.bold,
          fontSize: 23,
        ),
      );
    }

    return FadeTransition(
      opacity: _opacityAnimation,
      child: Text(
        widget.text,
        style: const TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.bold,
          fontSize: 25,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
