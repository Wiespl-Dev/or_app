import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiespl_contrl_panel/home/homescreen.dart';
import 'package:wiespl_contrl_panel/provider/espprovider.dart';
import 'package:wiespl_contrl_panel/provider/orsystemprovider.dart';
import 'package:wiespl_contrl_panel/provider/streamrecorderprovider.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

enum ScreenSize { mobile, tablet, desktop }

enum ORViewMode { dashboard, orMode }

// ─── Constants ───────────────────────────────────────────────────────────────

class _AppColors {
  static const background = Color(0xFF0F1117);
  static const surface = Color(0xFF1A1D26);
  static const inputFill = Color(0xFF252936);
  static const inputBorder = Color(0xFF3D4454);
  static const gradientStart = Color(0xFF2C10_5A); // deep purple
  static const gradientEnd = Color(0xFF44317F);
  static const btnBlue = Color(0xFF4285F4);
  static const btnPink = Color(0xFFD977A3);
}

const _kCardWidth = 900.0;
const _kFormPaddingH = 40.0;
const _kFormPaddingV = 20.0;
const _kFieldSpacing = 15.0;

// ─── Prefs keys ──────────────────────────────────────────────────────────────

class _PrefKeys {
  static const isLoggedIn = 'is_logged_in';
  static const selectedMode = 'selected_mode';
  static const selectedOT = 'selected_ot';
  static const accessCode = 'access_code';
  static const patientSystemIp = 'patient_system_ip';
  static const storeMgmtIp = 'store_management_ip';
  static const cameraIp = 'camera_ip';
  static const esp32Ip = 'esp32_ip';
  static const uniqueCode = 'unique_code';
}

// ─── Entry point ─────────────────────────────────────────────────────────────

void main() => runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ORSystemProvider()),
      ChangeNotifierProvider(create: (_) => ESP32Provider()),

      //
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'Roboto',
        primaryColor: const Color(0xFF00796B),
      ),
      home: const ModernLoginScreen(),
    ),
  ),
);

// ─── Login Screen ─────────────────────────────────────────────────────────────

class ModernLoginScreen extends StatefulWidget {
  const ModernLoginScreen({super.key});

  @override
  State<ModernLoginScreen> createState() => _ModernLoginScreenState();
}

class _ModernLoginScreenState extends State<ModernLoginScreen> {
  // ── Static data ──────────────────────────────────────────────────────────
  static const _modes = ['Main', 'Entrance', 'Store', 'CSSD'];
  static const _otNumbers = ['OT 1', 'OT 2', 'OT 3', 'OT 4', 'OT 5'];

  // ── State ────────────────────────────────────────────────────────────────
  String? _selectedMode;
  String? _selectedOT;
  bool _isLoading = false;

  // ── Controllers ──────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _patientSystemIpController = TextEditingController();
  final _storeMgmtIpController = TextEditingController();
  final _cameraIpController = TextEditingController();
  final _esp32IpController = TextEditingController();
  final _uniqueCodeController = TextEditingController();

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _patientSystemIpController.dispose();
    _storeMgmtIpController.dispose();
    _cameraIpController.dispose();
    _esp32IpController.dispose();
    _uniqueCodeController.dispose();
    super.dispose();
  }

  // ── Persistence ───────────────────────────────────────────────────────────
  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_PrefKeys.isLoggedIn) ?? false) {
      _navigateToDashboard();
    } else {
      await _loadSavedValues();
    }
  }

  Future<void> _loadSavedValues() async {
    final prefs = await SharedPreferences.getInstance();

    String? mode = prefs.getString(_PrefKeys.selectedMode);
    String? ot = prefs.getString(_PrefKeys.selectedOT);

    setState(() {
      _selectedMode = _modes.contains(mode) ? mode : null;
      _selectedOT = _otNumbers.contains(ot) ? ot : null;

      _codeController.text = prefs.getString(_PrefKeys.accessCode) ?? '';
      _patientSystemIpController.text =
          prefs.getString(_PrefKeys.patientSystemIp) ?? '';
      _storeMgmtIpController.text =
          prefs.getString(_PrefKeys.storeMgmtIp) ?? '';
      _cameraIpController.text = prefs.getString(_PrefKeys.cameraIp) ?? '';
      _esp32IpController.text = prefs.getString(_PrefKeys.esp32Ip) ?? '';
      _uniqueCodeController.text = prefs.getString(_PrefKeys.uniqueCode) ?? '';
    });
  }

  Future<void> _saveValues() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_PrefKeys.selectedMode, _selectedMode ?? ''),
      prefs.setString(_PrefKeys.selectedOT, _selectedOT ?? ''),
      prefs.setString(_PrefKeys.accessCode, _codeController.text),
      prefs.setString(
        _PrefKeys.patientSystemIp,
        _patientSystemIpController.text,
      ),
      prefs.setString(_PrefKeys.storeMgmtIp, _storeMgmtIpController.text),
      prefs.setString(_PrefKeys.cameraIp, _cameraIpController.text),
      prefs.setString(_PrefKeys.esp32Ip, _esp32IpController.text),
      prefs.setString(_PrefKeys.uniqueCode, _uniqueCodeController.text),
    ]);
  }

  // ── Auth actions ──────────────────────────────────────────────────────────
  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSnack('Please fill all required fields', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _saveValues();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_PrefKeys.isLoggedIn, true);
      if (mounted) _navigateToDashboard();
    } catch (e) {
      if (mounted) _showSnack('Login failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ModernLoginScreen()),
        (_) => false,
      );
    }
  }

  void _navigateToDashboard() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => MedicalDashboard(onLogout: _handleLogout),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: animation.drive(
            Tween(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeInOut)),
          ),
          child: child,
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── Validators ────────────────────────────────────────────────────────────
  static final _ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(:\d{1,5})?$');

  String? _validateIp(String? value) {
    if (value == null || value.isEmpty) return 'IP address is required';
    if (!_ipRegex.hasMatch(value)) {
      return 'Enter a valid IP (e.g. 192.168.1.1 or 192.168.1.1:8080)';
    }

    final ipPart = value.split(':').first;
    for (final part in ipPart.split('.')) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) {
        return 'Each octet must be 0–255';
      }
    }

    if (value.contains(':')) {
      final port = int.tryParse(value.split(':').last);
      if (port == null || port < 1 || port > 65535) {
        return 'Port must be 1–65535';
      }
    }
    return null;
  }

  String? _validateRequired(String? value) =>
      (value == null || value.isEmpty) ? 'This field is required' : null;

  // ── Border helpers ────────────────────────────────────────────────────────
  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: color),
  );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    const Text(
                      'WELCOME TO WIESPL DIGITAL OR',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    Center(
                      child: Container(
                        width: _kCardWidth,
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight - 200,
                        ),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: _AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _AppColors.gradientStart.withOpacity(0.5),
                              blurRadius: 80,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _buildLeftPanel()),
                            Expanded(child: _buildRightPanel()),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Left panel (image) ────────────────────────────────────────────────────
  Widget _buildLeftPanel() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [_AppColors.gradientStart, _AppColors.gradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      image: DecorationImage(
        image: AssetImage('assets/nbnb.jpeg'),
        fit: BoxFit.cover,
      ),
    ),
  );

  // ── Right panel (form) ────────────────────────────────────────────────────
  Widget _buildRightPanel() => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: _kFormPaddingH,
      vertical: _kFormPaddingV,
    ),
    child: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'System Configuration',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 25),

            _buildDropdown(
              'Select Mode *',
              _modes,
              _selectedMode,
              (v) => setState(() => _selectedMode = v),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Please select a mode' : null,
            ),
            const SizedBox(height: _kFieldSpacing),

            _buildDropdown(
              'Select OT *',
              _otNumbers,
              _selectedOT,
              (v) => setState(() => _selectedOT = v),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Please select an OT' : null,
            ),
            const SizedBox(height: _kFieldSpacing),

            _buildTextField(
              _codeController,
              'Access Code *',
              Icons.lock_outline,
              validator: _validateRequired,
            ),
            _buildTextField(
              _patientSystemIpController,
              'Patient System IP *',
              Icons.computer,
              validator: _validateIp,
            ),
            _buildTextField(
              _storeMgmtIpController,
              'Store Management IP *',
              Icons.storage,
              validator: _validateIp,
            ),
            _buildTextField(
              _cameraIpController,
              'Camera IP *',
              Icons.videocam_outlined,
              validator: _validateIp,
            ),
            _buildTextField(
              _esp32IpController,
              'ESP32 IP *',
              Icons.memory,
              validator: _validateIp,
            ),
            _buildTextField(
              _uniqueCodeController,
              'Unique Code *',
              Icons.qr_code,
              validator: _validateRequired,
            ),

            const SizedBox(height: 30),
            _buildLoginButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );

  // ── Login button ──────────────────────────────────────────────────────────
  Widget _buildLoginButton() => Container(
    width: double.infinity,
    height: 50,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      gradient: const LinearGradient(
        colors: [_AppColors.btnBlue, _AppColors.btnPink],
      ),
    ),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: _isLoading ? null : _handleLogin,
      child: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Text(
              'LOGIN',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
    ),
  );

  // ── Reusable text field ───────────────────────────────────────────────────
  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey, size: 20),
        filled: true,
        fillColor: _AppColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        enabledBorder: _inputBorder(_AppColors.inputBorder),
        focusedBorder: _inputBorder(Colors.blueAccent),
        errorBorder: _inputBorder(Colors.red),
        focusedErrorBorder: _inputBorder(Colors.red),
        errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
      ),
    ),
  );

  // ── Reusable dropdown ─────────────────────────────────────────────────────
  Widget _buildDropdown(
    String hint,
    List<String> items,
    String? selectedValue,
    ValueChanged<String?> onChanged, {
    String? Function(String?)? validator,
  }) => FormField<String>(
    validator: validator,
    builder: (state) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _AppColors.inputFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: state.hasError ? Colors.red : _AppColors.inputBorder,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(selectedValue) ? selectedValue : null,
              hint: Text(
                hint,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              dropdownColor: _AppColors.surface,
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              items: items
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) {
                onChanged(v);
                state.didChange(v);
              },
            ),
          ),
        ),
        if (state.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              state.errorText ?? '',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    ),
  );
}
