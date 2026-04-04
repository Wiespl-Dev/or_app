import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import 'package:wiespl_contrl_panel/clock/clockui.dart';
import 'package:wiespl_contrl_panel/clock/filp_component.dart';
import 'package:wiespl_contrl_panel/main.dart';
import 'package:wiespl_contrl_panel/or/ormodescreen.dart';
import 'package:wiespl_contrl_panel/provider/espprovider.dart';
import 'package:wiespl_contrl_panel/provider/orsystemprovider.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

class _C {
  static const teal = Color(0xFF00796B);
  static const darkText = Color.fromARGB(255, 228, 234, 236);
  static const lightPurple = Color.fromARGB(255, 121, 81, 185);

  // Glass card shared decoration
  static BoxDecoration glassCard({
    Color? borderColor,
    double borderWidth = 2.0,
  }) => BoxDecoration(
    color: Colors.white.withOpacity(0.13),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: borderColor ?? Colors.white.withOpacity(0.8),
      width: borderWidth,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 15,
        offset: const Offset(0, 5),
      ),
    ],
  );
}

// ─── Dashboard ────────────────────────────────────────────────────────────────

class MedicalDashboard extends StatelessWidget {
  final VoidCallback onLogout;
  const MedicalDashboard({super.key, required this.onLogout});

  ScreenSize _screenSize(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 600) return ScreenSize.mobile;
    if (w < 1200) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  @override
  Widget build(BuildContext context) {
    final systemPro = context.watch<ORSystemProvider>();

    if (systemPro.viewMode == ORViewMode.orMode) return ORModeScreen();

    final espPro = context.read<ESP32Provider>();

    return Scaffold(
      body: Stack(
        children: [
          BackgroundAnimation(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _TopBar(systemPro: systemPro, onLogout: onLogout),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        _buildStaticPanel(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: CustomPaint(
                              painter: ProfessionalClockPainter(systemPro.now),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        _FlippingTimerPanel(pro: systemPro),
                        const SizedBox(width: 15),
                        _RightSidebar(pro: systemPro, esp: espPro),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        _LightingCard(espPro: espPro),
                        _TempCard(ui: systemPro, esp: espPro),
                        _HumidityCard(ui: systemPro, esp: espPro),
                        _PressureCard(),
                        _MusicCard(pro: systemPro),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  _Footer(screenSize: _screenSize(context), onLogout: onLogout),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaticPanel({required Widget child, int flex = 1}) => Expanded(
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

// ─── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final ORSystemProvider systemPro;
  final VoidCallback onLogout;
  const _TopBar({required this.systemPro, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _ORModeButton(pro: systemPro),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: () => _confirmLogout(context),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true) onLogout();
  }
}

// ─── OR Mode button ────────────────────────────────────────────────────────────

class _ORModeButton extends StatelessWidget {
  final ORSystemProvider pro;
  const _ORModeButton({required this.pro});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => pro.setViewMode(ORViewMode.orMode),
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medical_services, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              'OR MODE',
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
    );
  }
}

// ─── Right sidebar ────────────────────────────────────────────────────────────

class _RightSidebar extends StatelessWidget {
  final ORSystemProvider pro;
  final ESP32Provider esp;
  const _RightSidebar({required this.pro, required this.esp});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 1,
      child: MedicalFlipCard(
        isFlipped: pro.showRightPanelFlip || pro.showMGPSFlip,
        front: _SidebarFront(pro: pro),
        back: pro.showMGPSFlip ? _MGPSBack(pro: pro) : _ConfigBack(pro: pro),
      ),
    );
  }
}

class _SidebarFront extends StatelessWidget {
  final ORSystemProvider pro;
  const _SidebarFront({required this.pro});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Consumer<ESP32Provider>(
          builder: (_, esp, __) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            child: _CircleSetting(
              icon: Icons.air,
              label: 'HEPA',
              isOn: true,
              color: esp.sensor10Color,
            ),
          ),
        ),
        const SizedBox(height: 25),
        _CircleSetting(
          icon: Icons.settings,
          label: 'CONFIG',
          isOn: true,
          onTap: pro.toggleRightPanelFlip,
        ),
        const SizedBox(height: 25),
        Consumer<ESP32Provider>(
          builder: (_, esp, __) => _CircleSetting(
            icon: Icons.gas_meter_outlined,
            label: 'MGPS',
            isOn: true,
            onTap: pro.toggleMGPSFlip,
            color: esp.mgpsColor,
          ),
        ),
      ],
    );
  }
}

class _ConfigBack extends StatelessWidget {
  final ORSystemProvider pro;
  const _ConfigBack({required this.pro});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'SYSTEM CONFIG',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const _CircleSetting(
          icon: Icons.language,
          label: 'ENG',
          isOn: true,
          color: Colors.blue,
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: pro.toggleRightPanelFlip,
          child: const Text(
            'BACK',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _MGPSBack extends StatelessWidget {
  final ORSystemProvider pro;
  const _MGPSBack({required this.pro});

  static const _gases = [
    ('Oxygen', Colors.green, 0),
    ('Nitrogen', Colors.blue, 1),
    ('Vacuum', Color(0xFFF9A825), 2), // Colors.yellow[700]
    ('Nitrous Oxide', Color(0xFF1A237E), 3), // Colors.blue[900]
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'MGPS STATUS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 10,
              color: Colors.orange,
            ),
          ),
          const Divider(),
          ..._gases.map(
            (g) => _GasStatusRow(
              title: g.$1,
              healthyColor: g.$2,
              sensorIndex: g.$3,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: pro.toggleMGPSFlip,
            child: const Text(
              'CLOSE',
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
}

class _GasStatusRow extends StatelessWidget {
  final String title;
  final Color healthyColor;
  final int sensorIndex;
  const _GasStatusRow({
    required this.title,
    required this.healthyColor,
    required this.sensorIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ESP32Provider>(
      builder: (_, esp, __) {
        final ok = esp.isSensorHealthy(sensorIndex);
        final color = ok ? healthyColor : Colors.red;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.circle, color: color, size: 14),
                  const SizedBox(width: 8),
                  _BlinkingText(
                    text: title,
                    isBlinking: !ok,
                    healthyColor: healthyColor,
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ok ? 'OK' : 'FAULT',
                  style: TextStyle(
                    color: color,
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
}

// ─── Bottom row cards ─────────────────────────────────────────────────────────

/// Shared glass wrapper for bottom-row cards.
class _BottomCard extends StatelessWidget {
  final Widget child;
  const _BottomCard({required this.child});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: _C.glassCard(),
      child: child,
    ),
  );
}

class _LightingCard extends StatelessWidget {
  final ESP32Provider espPro;
  const _LightingCard({required this.espPro});

  @override
  Widget build(BuildContext context) {
    final onCount = espPro.allLightStates.take(4).where((l) => l).length;
    return _BottomCard(
      child: _CardContent(
        title: 'LIGHTING',
        icon: Icons.wb_sunny_outlined,
        value: onCount.toString(),
        onTap: () => _LightControlDialog.show(context, espPro),
      ),
    );
  }
}

class _TempCard extends StatelessWidget {
  final ORSystemProvider ui;
  final ESP32Provider esp;
  const _TempCard({required this.ui, required this.esp});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: MedicalFlipCard(
        isFlipped: ui.showTempSettings,
        front: Consumer<ESP32Provider>(
          builder: (_, e, __) => _CardContent(
            title: 'TEMP',
            icon: Icons.thermostat,
            value: '${e.currentTemperatureAsDouble.toStringAsFixed(1)}°C',
            onTap: ui.toggleTempFlip,
          ),
        ),
        back: _Adjuster(
          title: 'SET TEMP',
          val: esp.pendingTemperature,
          onAdjust: esp.updatePendingTemperature,
          onClose: () async {
            ui.toggleTempFlip();
            await esp.setTemperature(esp.pendingTemperature);
          },
        ),
      ),
    ),
  );
}

class _HumidityCard extends StatelessWidget {
  final ORSystemProvider ui;
  final ESP32Provider esp;
  const _HumidityCard({required this.ui, required this.esp});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: MedicalFlipCard(
        isFlipped: ui.showHumiditySettings,
        front: Consumer<ESP32Provider>(
          builder: (_, e, __) => _CardContent(
            title: 'HUMIDITY',
            icon: Icons.water_drop_outlined,
            value:
                '${double.tryParse(e.currentHumidity)?.toStringAsFixed(1) ?? "0.0"}%',
            onTap: ui.toggleHumidityFlip,
          ),
        ),
        back: _Adjuster(
          title: 'SET RH %',
          val: esp.humiditySetpointAsDouble,
          onAdjust: esp.adjustHumidity,
          onClose: () async {
            ui.toggleHumidityFlip();
            await esp.setHumiditySetpoint();
          },
        ),
      ),
    ),
  );
}

class _PressureCard extends StatelessWidget {
  const _PressureCard();

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Consumer<ESP32Provider>(
        builder: (_, esp, __) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: _C.glassCard(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'PRESSURE',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _C.darkText.withOpacity(0.5),
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
                '${esp.getFormattedPressure()} Pa',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: esp.getPressureColor(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MusicCard extends StatelessWidget {
  final ORSystemProvider pro;
  const _MusicCard({required this.pro});

  @override
  Widget build(BuildContext context) => _BottomCard(
    child: _CardContent(
      title: 'MUSIC',
      icon: pro.isMusicPlaying ? Icons.music_note : Icons.music_off,
      value: pro.isMusicPlaying ? 'ON' : 'OFF',
      onTap: pro.toggleMusicFlip,
    ),
  );
}

// ─── Flipping timer / music panel ────────────────────────────────────────────

class _FlippingTimerPanel extends StatelessWidget {
  final ORSystemProvider pro;
  const _FlippingTimerPanel({required this.pro});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: 2,
    child: MedicalFlipCard(
      isFlipped: pro.showMusic,
      front: _TimerFront(pro: pro),
      back: _MusicBack(pro: pro),
    ),
  );
}

class _TimerFront extends StatelessWidget {
  final ORSystemProvider pro;
  const _TimerFront({required this.pro});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        'OR CONTROL PANEL',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: _C.darkText,
        ),
      ),
      Text(
        pro.formattedFullDate,
        style: TextStyle(fontSize: 12, color: _C.darkText.withOpacity(0.6)),
      ),
      const Divider(height: 30, indent: 60, endIndent: 60),
      Text(
        pro.stopwatchDisplay,
        style: const TextStyle(
          fontSize: 60,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StopwatchBtn(
            icon: Icons.refresh,
            label: 'RESET',
            onTap: pro.resetStopwatch,
          ),
          const SizedBox(width: 30),
          _StopwatchBtn(
            icon: pro.timerRunning ? Icons.pause : Icons.play_arrow,
            label: pro.timerRunning ? 'PAUSE' : 'START',
            onTap: pro.toggleStopwatch,
            primary: true,
          ),
        ],
      ),
    ],
  );
}

class _MusicBack extends StatelessWidget {
  final ORSystemProvider pro;
  const _MusicBack({required this.pro});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.library_music, color: _C.teal, size: 30),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          pro.currentTrack,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: _C.darkText,
          ),
          textAlign: TextAlign.center,
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.skip_previous, color: _C.teal),
            onPressed: pro.prevTrack,
          ),
          CircleAvatar(
            backgroundColor: _C.teal,
            child: IconButton(
              icon: Icon(
                pro.isMusicPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: pro.togglePlayPause,
            ),
          ),
          IconButton(
            icon: Icon(Icons.skip_next, color: _C.teal),
            onPressed: pro.nextTrack,
          ),
        ],
      ),
      TextButton(
        onPressed: pro.toggleMusicFlip,
        child: const Text(
          'CLOSE PLAYER',
          style: TextStyle(color: Colors.white),
        ),
      ),
    ],
  );
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final ScreenSize screenSize;
  final VoidCallback onLogout;
  const _Footer({required this.screenSize, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PowerButton(),
        const SizedBox(width: 20),
        _HepaStatus(),
        const Spacer(),
        _LogoPanel(screenSize: screenSize),
      ],
    );
  }
}

class _PowerButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ESP32Provider>(
      builder: (context, esp, _) => GestureDetector(
        onTap: () => _handleTap(context, esp),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (esp.systemPower ? Colors.green : Colors.red).withOpacity(
              0.1,
            ),
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
    );
  }

  Future<void> _handleTap(BuildContext context, ESP32Provider esp) async {
    final newState = !esp.systemPower;
    if (!newState) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Confirm'),
          content: const Text('Are you sure you want to turn off the system?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await esp.toggleSystemPower(newState);
  }
}

class _HepaStatus extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ESP32Provider>(
      builder: (_, esp, __) {
        final healthy = esp.sensor10Color == Colors.green;
        final color = healthy ? Colors.green : Colors.red;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(healthy ? Icons.air : Icons.warning, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                healthy ? 'HEPA Healthy' : 'HEPA Fault',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogoPanel extends StatelessWidget {
  final ScreenSize screenSize;
  const _LogoPanel({required this.screenSize});

  bool get _isTablet => screenSize == ScreenSize.tablet;

  Widget _blurContainer(double h, double w, {Widget? child}) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      _blurContainer(_isTablet ? 100 : 120, _isTablet ? 200 : 270),
      _blurContainer(
        _isTablet ? 80 : 100,
        _isTablet ? 180 : 250,
        child: Center(
          child: Image.asset(
            'assets/app_logo-removebg-preview.png',
            height: _isTablet ? 80 : 100,
            width: _isTablet ? 240 : 300,
            fit: BoxFit.contain,
          ),
        ),
      ),
    ],
  );
}

// ─── Shared small widgets ─────────────────────────────────────────────────────

class _CardContent extends StatelessWidget {
  final String title;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  const _CardContent({
    required this.title,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _C.darkText.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Icon(icon, color: _C.teal, size: 36),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _C.darkText,
          ),
        ),
      ],
    ),
  );
}

class _Adjuster extends StatelessWidget {
  final String title;
  final double val;
  final ValueChanged<double> onAdjust;
  final VoidCallback onClose;
  const _Adjuster({
    required this.title,
    required this.val,
    required this.onAdjust,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Column(
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
            icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
            onPressed: () => onAdjust(-0.5),
          ),
          Text(
            val.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _C.teal,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            onPressed: () => onAdjust(0.5),
          ),
        ],
      ),
      TextButton(
        onPressed: onClose,
        child: const Text(
          'DONE',
          style: TextStyle(fontSize: 10, color: Colors.white),
        ),
      ),
    ],
  );
}

class _StopwatchBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _StopwatchBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      GestureDetector(
        onTap: onTap,
        child: CircleAvatar(
          radius: 22,
          backgroundColor: primary ? _C.teal : Colors.teal,
          child: Icon(icon, color: primary ? Colors.white : _C.teal, size: 20),
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

class _CircleSetting extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isOn;
  final VoidCallback? onTap;
  final Color? color;
  const _CircleSetting({
    required this.icon,
    required this.label,
    required this.isOn,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: isOn ? (color ?? _C.teal) : Colors.black12,
              width: 2,
            ),
          ),
          child: Icon(
            icon,
            color: isOn ? (color ?? _C.teal) : Colors.black26,
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

// ─── Light control dialog ─────────────────────────────────────────────────────

class _LightControlDialog extends StatefulWidget {
  final ESP32Provider pro;
  const _LightControlDialog({required this.pro});

  static void show(BuildContext context, ESP32Provider pro) {
    showDialog(
      context: context,
      builder: (_) => _LightControlDialog(pro: pro),
    );
  }

  @override
  State<_LightControlDialog> createState() => _LightControlDialogState();
}

class _LightControlDialogState extends State<_LightControlDialog> {
  @override
  Widget build(BuildContext context) {
    final pro = widget.pro;
    final allOn = pro.allLightStates.take(4).every((on) => on);

    return AlertDialog(
      backgroundColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      content: Container(
        width: double.maxFinite,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color.fromARGB(50, 33, 33, 33).withOpacity(0.5),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
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
              'LIGHTING CONTROL',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 24),
            ...List.generate(
              4,
              (i) => _LightZoneRow(
                index: i,
                pro: pro,
                onChanged: () => setState(() {}),
              ),
            ),
            const Divider(color: Colors.white24, height: 32),
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: allOn ? _C.lightPurple : Colors.grey.shade600,
                  size: 28,
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'ALL LIGHTS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: allOn,
                  activeColor: _C.lightPurple,
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
                style: FilledButton.styleFrom(backgroundColor: Colors.white24),
                onPressed: () => Navigator.pop(context),
                child: const Text('DONE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LightZoneRow extends StatelessWidget {
  final int index;
  final ESP32Provider pro;
  final VoidCallback onChanged;
  const _LightZoneRow({
    required this.index,
    required this.pro,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isOn = pro.getLightState(index);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb,
            color: isOn ? _C.lightPurple : Colors.grey.shade600,
            size: 32,
            shadows: isOn
                ? [
                    Shadow(
                      color: _C.lightPurple.withOpacity(0.6),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'ZONE ${index + 1}',
              style: TextStyle(
                fontSize: 16,
                color: isOn ? Colors.white : Colors.grey.shade400,
                fontWeight: isOn ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Switch.adaptive(
            value: isOn,
            activeColor: _C.lightPurple,
            onChanged: (val) async {
              try {
                await pro.toggleLight(index + 1, val);
                onChanged();
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'ESP32 Offline: Check your Wi-Fi connection',
                      ),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// ─── Blinking text ────────────────────────────────────────────────────────────

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
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 1.0,
    end: 0.2,
  ).animate(_ctrl);

  @override
  void initState() {
    super.initState();
    if (widget.isBlinking) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _BlinkingText old) {
    super.didUpdateWidget(old);
    if (!widget.isBlinking) {
      _ctrl
        ..stop()
        ..value = 1.0;
    } else {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
      opacity: _opacity,
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
}
