import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiespl_contrl_panel/home/homescreen.dart';
import 'package:wiespl_contrl_panel/or/orscreen.dart';
import 'package:wiespl_contrl_panel/provider/espprovider.dart';
import 'package:wiespl_contrl_panel/provider/orsystemprovider.dart';

enum ScreenSize { mobile, tablet, desktop }

enum ORViewMode { dashboard, orMode }

void main() => runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ORSystemProvider()),
      ChangeNotifierProvider(
        create: (_) => StreamViewerProvider(),
      ), //ESP32Provider
      ChangeNotifierProvider(create: (_) => ESP32Provider()),
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

class ModernLoginScreen extends StatefulWidget {
  const ModernLoginScreen({super.key});

  @override
  State<ModernLoginScreen> createState() => _ModernLoginScreenState();
}

class _ModernLoginScreenState extends State<ModernLoginScreen> {
  final List<String> _modes = ['Main', 'Entrance', 'Store', 'CSSD'];
  final List<String> _otNumbers = ['OT 1', 'OT 2', 'OT 3', 'OT 4', 'OT 5'];

  String? _selectedMode;
  String? _selectedOT;

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _patientSystemIpController =
      TextEditingController();
  final TextEditingController _storeManagementIpController =
      TextEditingController();
  final TextEditingController _cameraIpController = TextEditingController();
  final TextEditingController _esp32IpController = TextEditingController();
  final TextEditingController _uniqueCodeController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

    if (isLoggedIn) {
      _navigateToDashboard();
    } else {
      _loadSavedValues();
    }
  }

  Future<void> _loadSavedValues() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedMode = prefs.getString('selected_mode');
      _selectedOT = prefs.getString('selected_ot');

      // Ensure selected values are valid (exist in the lists)
      if (_selectedMode != null && !_modes.contains(_selectedMode)) {
        _selectedMode = null;
      }
      if (_selectedOT != null && !_otNumbers.contains(_selectedOT)) {
        _selectedOT = null;
      }

      _codeController.text = prefs.getString('access_code') ?? '';
      _patientSystemIpController.text =
          prefs.getString('patient_system_ip') ?? '';
      _storeManagementIpController.text =
          prefs.getString('store_management_ip') ?? '';
      _cameraIpController.text = prefs.getString('camera_ip') ?? '';
      _esp32IpController.text = prefs.getString('esp32_ip') ?? '';
      _uniqueCodeController.text = prefs.getString('unique_code') ?? '';
    });
  }

  Future<void> _saveValues() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_mode', _selectedMode ?? '');
    await prefs.setString('selected_ot', _selectedOT ?? '');
    await prefs.setString('access_code', _codeController.text);
    await prefs.setString('patient_system_ip', _patientSystemIpController.text);
    await prefs.setString(
      'store_management_ip',
      _storeManagementIpController.text,
    );
    await prefs.setString('camera_ip', _cameraIpController.text);
    await prefs.setString('esp32_ip', _esp32IpController.text);
    await prefs.setString('unique_code', _uniqueCodeController.text);
  }

  Future<void> _handleLogin() async {
    // Validate form
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Save all values
        await _saveValues();

        // Save login state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);

        // Navigate to dashboard
        if (mounted) {
          _navigateToDashboard();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Login failed: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      // Show validation error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _navigateToDashboard() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MedicalDashboard(onLogout: _handleLogout),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clear ALL shared preferences

    if (mounted) {
      // Completely reset the app
      Navigator.of(context).popUntil((route) => route.isFirst);

      // Replace with login screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ModernLoginScreen()),
      );
    }
  }

  // UPDATED VALIDATION FUNCTION - Now accepts IP addresses with ports
  String? _validateIp(String? value) {
    if (value == null || value.isEmpty) {
      return 'IP address is required';
    }

    // Regular expression for IP address with optional port
    // Pattern: IP (xxx.xxx.xxx.xxx) optionally followed by :port (1-65535)
    final ipWithPortRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(:\d{1,5})?$');

    if (!ipWithPortRegex.hasMatch(value)) {
      return 'Enter a valid IP address (e.g., 192.168.1.242 or 192.168.1.242:8080)';
    }

    // Validate IP parts (each octet must be 0-255)
    final ipPart = value.split(':')[0]; // Get IP part before port if exists
    final parts = ipPart.split('.');

    for (String part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0 || number > 255) {
        return 'Invalid IP address: each octet must be between 0 and 255';
      }
    }

    // If port exists, validate it
    if (value.contains(':')) {
      final portPart = value.split(':')[1];
      final port = int.tryParse(portPart);
      if (port == null || port < 1 || port > 65535) {
        return 'Invalid port number: must be between 1 and 65535';
      }
    }

    return null;
  }

  String? _validateRequired(String? value) {
    if (value == null || value.isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
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
                          width: 900,
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight - 200,
                          ),
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1D26),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color.fromARGB(
                                  255,
                                  44,
                                  16,
                                  90,
                                ).withOpacity(0.5),
                                blurRadius: 80,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // --- LEFT SIDE: Image/Art ---
                              Expanded(
                                flex: 1,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color.fromARGB(255, 44, 16, 90),
                                        Color.fromARGB(255, 68, 49, 127),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    image: DecorationImage(
                                      image: AssetImage("assets/nbnb.jpeg"),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),

                              // --- RIGHT SIDE: Form ---
                              Expanded(
                                flex: 1,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 40,
                                    vertical: 20,
                                  ),
                                  child: Form(
                                    key: _formKey,
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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

                                          // First Dropdown
                                          _buildDropdown(
                                            "Select Mode *",
                                            _modes,
                                            _selectedMode,
                                            (value) {
                                              setState(() {
                                                _selectedMode = value;
                                              });
                                            },
                                            validator: (value) {
                                              if (value == null ||
                                                  value.isEmpty) {
                                                return 'Please select a mode';
                                              }
                                              return null;
                                            },
                                          ),
                                          const SizedBox(height: 15),

                                          // Second Dropdown (OT 1-5)
                                          _buildDropdown(
                                            "Select OT *",
                                            _otNumbers,
                                            _selectedOT,
                                            (value) {
                                              setState(() {
                                                _selectedOT = value;
                                              });
                                            },
                                            validator: (value) {
                                              if (value == null ||
                                                  value.isEmpty) {
                                                return 'Please select an OT';
                                              }
                                              return null;
                                            },
                                          ),
                                          const SizedBox(height: 15),

                                          // Text Fields with validation
                                          _buildTextField(
                                            _codeController,
                                            "Access Code *",
                                            Icons.lock_outline,
                                            validator: _validateRequired,
                                          ),
                                          _buildTextField(
                                            _patientSystemIpController,
                                            "Patient System IP *",
                                            Icons.computer,
                                            validator: _validateIp,
                                          ),
                                          _buildTextField(
                                            _storeManagementIpController,
                                            "Store Management IP *",
                                            Icons.storage,
                                            validator: _validateIp,
                                          ),
                                          _buildTextField(
                                            _cameraIpController,
                                            "Camera IP *",
                                            Icons.videocam_outlined,
                                            validator: _validateIp,
                                          ),
                                          _buildTextField(
                                            _esp32IpController,
                                            "ESP32 IP *",
                                            Icons.memory,
                                            validator:
                                                _validateIp, // Now accepts 192.168.1.242:8080
                                          ),
                                          _buildTextField(
                                            _uniqueCodeController,
                                            "Unique Code *",
                                            Icons.qr_code,
                                            validator: _validateRequired,
                                          ),

                                          const SizedBox(height: 30),

                                          // --- Gradient Button ---
                                          Container(
                                            width: double.infinity,
                                            height: 50,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF4285F4),
                                                  Color(0xFFD977A3),
                                                ],
                                              ),
                                            ),
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              onPressed: _isLoading
                                                  ? null
                                                  : _handleLogin,
                                              child: _isLoading
                                                  ? const SizedBox(
                                                      height: 20,
                                                      width: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                            color: Colors.white,
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : const Text(
                                                      'LOGIN',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    String? Function(String?)? validator,
  }) {
    return Padding(
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
          fillColor: const Color(0xFF252936),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3D4454)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.blueAccent),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red),
          ),
          errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String hint,
    List<String> items,
    String? selectedValue,
    Function(String?) onChanged, {
    String? Function(String?)? validator,
  }) {
    return FormField<String>(
      validator: validator,
      builder: (FormFieldState<String> state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF252936),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: state.hasError ? Colors.red : const Color(0xFF3D4454),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedValue != null && items.contains(selectedValue)
                      ? selectedValue
                      : null,
                  hint: Text(
                    hint,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  dropdownColor: const Color(0xFF1A1D26),
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white),
                  items: items.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    onChanged(value);
                    state.didChange(value);
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
        );
      },
    );
  }
}

// // Note: You'll need to import the MedicalDashboard class
// //Make sure MedicalDashboard is defined in your project
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// void main() => runApp(const MyApp());

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'TinyCam Controller',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData.dark(),
//       home: const TinyCamPage(),
//     );
//   }
// }

// class TinyCamPage extends StatefulWidget {
//   const TinyCamPage({super.key});
//   @override
//   State<TinyCamPage> createState() => _TinyCamPageState();
// }

// class _TinyCamPageState extends State<TinyCamPage> {
//   // ── Config — change these if needed ─────────────────────
//   final String host = '192.168.1.207';
//   final int port = 8083;
//   final String username = 'admin';
//   final String password = ''; // leave empty if no password set

//   // ── State ────────────────────────────────────────────────
//   String? _token; // auth token from login
//   bool _loggedIn = false;
//   bool _recording = false;
//   bool _loading = false;
//   final List<String> _logs = [];

//   String get base => 'http://$host:$port';

//   // ── Logging ──────────────────────────────────────────────
//   void _log(String msg) {
//     final now = DateTime.now();
//     final t =
//         '${now.hour.toString().padLeft(2, '0')}:'
//         '${now.minute.toString().padLeft(2, '0')}:'
//         '${now.second.toString().padLeft(2, '0')}';
//     setState(() {
//       _logs.insert(0, '[$t] $msg');
//       if (_logs.length > 100) _logs.removeLast();
//     });
//   }

//   // ── Step 1: Login → get token ────────────────────────────
//   // Official TinyCam API: POST /api/v1/login  (or GET with Basic Auth)
//   Future<bool> _login() async {
//     setState(() => _loading = true);
//     _log('🔑 Logging in as "$username"...');

//     try {
//       // TinyCam supports Basic Auth on every request OR token-based login
//       // Try token login first
//       final uri = Uri.parse('$base/api/v1/login');
//       final res = await http
//           .post(
//             uri,
//             headers: {'Content-Type': 'application/json'},
//             body: jsonEncode({'username': username, 'password': password}),
//           )
//           .timeout(const Duration(seconds: 6));

//       _log('Login response ${res.statusCode}: ${res.body}');

//       if (res.statusCode == 200) {
//         try {
//           final data = jsonDecode(res.body);
//           _token = data['data']?['token'] ?? data['token'];
//           if (_token != null) {
//             _log('✅ Logged in! Token: ${_token!.substring(0, 8)}...');
//             setState(() {
//               _loggedIn = true;
//               _loading = false;
//             });
//             return true;
//           }
//         } catch (_) {}
//       }

//       // Fallback: use HTTP Basic Auth (no token needed, just attach header each time)
//       _log('ℹ️ Using Basic Auth instead of token');
//       setState(() {
//         _loggedIn = true;
//         _loading = false;
//       });
//       return true;
//     } catch (e) {
//       _log('❌ Login failed: $e');
//       setState(() {
//         _loggedIn = false;
//         _loading = false;
//       });
//       return false;
//     }
//   }

//   // ── Build auth headers ───────────────────────────────────
//   Map<String, String> get _authHeaders {
//     if (_token != null) {
//       // Token-based (preferred by TinyCam API)
//       return {'token': _token!};
//     }
//     // HTTP Basic Auth fallback
//     if (username.isNotEmpty) {
//       final encoded = base64Encode(utf8.encode('$username:$password'));
//       return {'Authorization': 'Basic $encoded'};
//     }
//     return {};
//   }

//   // ── GET helper ───────────────────────────────────────────
//   Future<http.Response?> _get(String path) async {
//     try {
//       final res = await http
//           .get(Uri.parse('$base$path'), headers: _authHeaders)
//           .timeout(const Duration(seconds: 6));
//       _log('→ GET $path  ←  ${res.statusCode}: ${res.body}');
//       return res;
//     } catch (e) {
//       _log('❌ $path failed: $e');
//       return null;
//     }
//   }

//   // ── Start Recording ──────────────────────────────────────
//   // TinyCam API: param.cgi?action=update&root.BackgroundMode=on
//   // This starts background mode which includes recording
//   Future<void> _startRecording() async {
//     if (!_loggedIn) {
//       await _login();
//     }
//     setState(() => _loading = true);
//     _log('▶ Starting recording...');

//     // Try official TinyCam API endpoints in order
//     final endpoints = [
//       '/param.cgi?action=update&root.BackgroundMode=on',
//       '/api/v1/set_params?backgroundMode=on',
//       '/api/v1/start_record',
//     ];

//     for (final ep in endpoints) {
//       final res = await _get(ep);
//       if (res != null && res.statusCode == 200) {
//         setState(() {
//           _recording = true;
//           _loading = false;
//         });
//         _log('✅ Recording started!');
//         return;
//       }
//     }

//     _log('⚠️ Could not start — try tapping "Scan" to find correct endpoint');
//     setState(() => _loading = false);
//   }

//   // ── Stop Recording ───────────────────────────────────────
//   Future<void> _stopRecording() async {
//     if (!_loggedIn) {
//       await _login();
//     }
//     setState(() => _loading = true);
//     _log('⏹ Stopping recording...');

//     final endpoints = [
//       '/param.cgi?action=update&root.BackgroundMode=off',
//       '/api/v1/set_params?backgroundMode=off',
//       '/api/v1/stop_record',
//     ];

//     for (final ep in endpoints) {
//       final res = await _get(ep);
//       if (res != null && res.statusCode == 200) {
//         setState(() {
//           _recording = false;
//           _loading = false;
//         });
//         _log('✅ Recording stopped!');
//         return;
//       }
//     }

//     _log('⚠️ Could not stop');
//     setState(() => _loading = false);
//   }

//   // ── Get Status ───────────────────────────────────────────
//   Future<void> _getStatus() async {
//     if (!_loggedIn) {
//       await _login();
//     }
//     _log('🔍 Getting status...');
//     final res = await _get('/api/v1/get_status');
//     if (res != null && res.statusCode == 200) {
//       try {
//         final data = jsonDecode(res.body);
//         final bg = data['data']?['backgroundMode'] ?? false;
//         setState(() => _recording = bg);
//         _log('Status OK — backgroundMode: $bg');
//       } catch (_) {}
//     }
//   }

//   // ── Scan all known endpoints ─────────────────────────────
//   Future<void> _scan() async {
//     if (!_loggedIn) {
//       await _login();
//     }
//     _log('🔎 Scanning all endpoints...');

//     final endpoints = [
//       '/api/v1/get_status',
//       '/api/v1/get_cam_list',
//       '/param.cgi?action=update&root.BackgroundMode=on',
//       '/param.cgi?action=update&root.BackgroundMode=off',
//       '/api/v1/login',
//       '/',
//       '/index.htm',
//     ];

//     for (final ep in endpoints) {
//       final res = await _get(ep);
//       if (res != null) {
//         _log('${res.statusCode == 200 ? '✅' : '  '} $ep → ${res.statusCode}');
//       }
//     }
//     _log('🔎 Scan done');
//   }

//   // ── UI ───────────────────────────────────────────────────
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('TinyCam Controller'),
//         backgroundColor: Colors.grey[900],
//         actions: [
//           Padding(
//             padding: const EdgeInsets.only(right: 14),
//             child: Center(
//               child: Row(
//                 children: [
//                   Container(
//                     width: 9,
//                     height: 9,
//                     decoration: BoxDecoration(
//                       shape: BoxShape.circle,
//                       color: _loggedIn ? Colors.greenAccent : Colors.red,
//                     ),
//                   ),
//                   const SizedBox(width: 6),
//                   Text(
//                     _loggedIn ? 'Online' : 'Offline',
//                     style: const TextStyle(fontSize: 13),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//       backgroundColor: Colors.grey[850],
//       body: Padding(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           children: [
//             // ── Server address ──────────────────────────────
//             Container(
//               width: double.infinity,
//               padding: const EdgeInsets.all(12),
//               decoration: BoxDecoration(
//                 color: Colors.grey[800],
//                 borderRadius: BorderRadius.circular(10),
//               ),
//               child: Text(
//                 '$base  (user: $username)',
//                 style: const TextStyle(
//                   color: Colors.white70,
//                   fontFamily: 'monospace',
//                   fontSize: 13,
//                 ),
//                 textAlign: TextAlign.center,
//               ),
//             ),

//             const SizedBox(height: 14),

//             // ── Login button ────────────────────────────────
//             SizedBox(
//               width: double.infinity,
//               height: 46,
//               child: ElevatedButton.icon(
//                 icon: const Icon(Icons.login),
//                 label: Text(_loggedIn ? 'Re-Login' : 'Connect & Login'),
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: _loggedIn
//                       ? Colors.grey[700]
//                       : Colors.blueAccent,
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                 ),
//                 onPressed: _loading ? null : _login,
//               ),
//             ),

//             const SizedBox(height: 20),

//             // ── Recording indicator ─────────────────────────
//             Container(
//               width: double.infinity,
//               padding: const EdgeInsets.symmetric(vertical: 22),
//               decoration: BoxDecoration(
//                 color: _recording
//                     ? Colors.red.withOpacity(0.15)
//                     : Colors.grey[800],
//                 borderRadius: BorderRadius.circular(14),
//                 border: Border.all(
//                   color: _recording ? Colors.red : Colors.grey[700]!,
//                   width: 1.5,
//                 ),
//               ),
//               child: Column(
//                 children: [
//                   Icon(
//                     _recording
//                         ? Icons.fiber_manual_record
//                         : Icons.videocam_outlined,
//                     color: _recording ? Colors.red : Colors.grey,
//                     size: 36,
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     _recording ? '● RECORDING' : 'STANDBY',
//                     style: TextStyle(
//                       color: _recording ? Colors.red : Colors.grey,
//                       fontWeight: FontWeight.bold,
//                       fontSize: 16,
//                       letterSpacing: 2,
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             const SizedBox(height: 20),

//             // ── START / STOP ────────────────────────────────
//             Row(
//               children: [
//                 Expanded(
//                   child: SizedBox(
//                     height: 58,
//                     child: ElevatedButton.icon(
//                       icon: const Icon(Icons.fiber_manual_record),
//                       label: const Text(
//                         'START',
//                         style: TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                           letterSpacing: 1.5,
//                         ),
//                       ),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.red,
//                         disabledBackgroundColor: Colors.red.withOpacity(0.3),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                       ),
//                       onPressed: _loading || _recording
//                           ? null
//                           : _startRecording,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 16),
//                 Expanded(
//                   child: SizedBox(
//                     height: 58,
//                     child: ElevatedButton.icon(
//                       icon: const Icon(Icons.stop),
//                       label: const Text(
//                         'STOP',
//                         style: TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                           letterSpacing: 1.5,
//                         ),
//                       ),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.blueAccent,
//                         disabledBackgroundColor: Colors.blueAccent.withOpacity(
//                           0.3,
//                         ),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                       ),
//                       onPressed: _loading || !_recording
//                           ? null
//                           : _stopRecording,
//                     ),
//                   ),
//                 ),
//               ],
//             ),

//             const SizedBox(height: 12),

//             // ── Status + Scan ───────────────────────────────
//             Row(
//               children: [
//                 Expanded(
//                   child: SizedBox(
//                     height: 42,
//                     child: OutlinedButton.icon(
//                       icon: const Icon(Icons.refresh, size: 16),
//                       label: const Text('Get Status'),
//                       style: OutlinedButton.styleFrom(
//                         foregroundColor: Colors.white54,
//                         side: BorderSide(color: Colors.grey[700]!),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(10),
//                         ),
//                       ),
//                       onPressed: _loading ? null : _getStatus,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   child: SizedBox(
//                     height: 42,
//                     child: OutlinedButton.icon(
//                       icon: const Icon(Icons.search, size: 16),
//                       label: const Text('Scan'),
//                       style: OutlinedButton.styleFrom(
//                         foregroundColor: Colors.white54,
//                         side: BorderSide(color: Colors.grey[700]!),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(10),
//                         ),
//                       ),
//                       onPressed: _loading ? null : _scan,
//                     ),
//                   ),
//                 ),
//               ],
//             ),

//             const SizedBox(height: 14),

//             // ── Log panel ───────────────────────────────────
//             Expanded(
//               child: Container(
//                 width: double.infinity,
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: Colors.black87,
//                   borderRadius: BorderRadius.circular(10),
//                   border: Border.all(color: Colors.grey[700]!),
//                 ),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(
//                       children: [
//                         const Text(
//                           'LOG',
//                           style: TextStyle(
//                             color: Colors.white54,
//                             fontSize: 11,
//                             fontWeight: FontWeight.bold,
//                             letterSpacing: 2,
//                           ),
//                         ),
//                         const Spacer(),
//                         GestureDetector(
//                           onTap: () => setState(() => _logs.clear()),
//                           child: const Text(
//                             'CLEAR',
//                             style: TextStyle(
//                               color: Colors.white38,
//                               fontSize: 11,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 8),
//                     Expanded(
//                       child: _logs.isEmpty
//                           ? const Center(
//                               child: Text(
//                                 'Tap "Connect & Login" to start',
//                                 style: TextStyle(color: Colors.white24),
//                               ),
//                             )
//                           : ListView.builder(
//                               itemCount: _logs.length,
//                               itemBuilder: (_, i) => Padding(
//                                 padding: const EdgeInsets.symmetric(
//                                   vertical: 1,
//                                 ),
//                                 child: Text(
//                                   _logs[i],
//                                   style: TextStyle(
//                                     fontFamily: 'monospace',
//                                     fontSize: 11,
//                                     color: _logs[i].contains('❌')
//                                         ? Colors.redAccent
//                                         : _logs[i].contains('✅')
//                                         ? Colors.greenAccent
//                                         : _logs[i].contains('⚠️')
//                                         ? Colors.orangeAccent
//                                         : Colors.white54,
//                                   ),
//                                 ),
//                               ),
//                             ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             if (_loading) ...[
//               const SizedBox(height: 10),
//               const LinearProgressIndicator(color: Colors.blueAccent),
//             ],
//           ],
//         ),
//       ),
//     );
//   }
// }
