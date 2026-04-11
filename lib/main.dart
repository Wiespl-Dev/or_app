// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:wiespl_contrl_panel/home/homescreen.dart';
// import 'package:wiespl_contrl_panel/provider/espprovider.dart';
// import 'package:wiespl_contrl_panel/provider/orsystemprovider.dart';
// import 'package:wiespl_contrl_panel/provider/streamrecorderprovider.dart';

// // ─── Enums ───────────────────────────────────────────────────────────────────

// enum ScreenSize { mobile, tablet, desktop }

// enum ORViewMode { dashboard, orMode }

// // ─── Constants ───────────────────────────────────────────────────────────────

// class _AppColors {
//   static const background = Color(0xFF0F1117);
//   static const surface = Color(0xFF1A1D26);
//   static const inputFill = Color(0xFF252936);
//   static const inputBorder = Color(0xFF3D4454);
//   static const gradientStart = Color(0xFF2C10_5A); // deep purple
//   static const gradientEnd = Color(0xFF44317F);
//   static const btnBlue = Color(0xFF4285F4);
//   static const btnPink = Color(0xFFD977A3);
// }

// const _kCardWidth = 900.0;
// const _kFormPaddingH = 40.0;
// const _kFormPaddingV = 20.0;
// const _kFieldSpacing = 15.0;

// // ─── Prefs keys ──────────────────────────────────────────────────────────────

// class _PrefKeys {
//   static const isLoggedIn = 'is_logged_in';
//   static const selectedMode = 'selected_mode';
//   static const selectedOT = 'selected_ot';
//   static const accessCode = 'access_code';
//   static const patientSystemIp = 'patient_system_ip';
//   static const storeMgmtIp = 'store_management_ip';
//   static const cameraIp = 'camera_ip';
//   static const esp32Ip = 'esp32_ip';
//   static const uniqueCode = 'unique_code';
// }

// // ─── Entry point ─────────────────────────────────────────────────────────────

// void main() => runApp(
//   MultiProvider(
//     providers: [
//       ChangeNotifierProvider(create: (_) => ORSystemProvider()),
//       ChangeNotifierProvider(create: (_) => ESP32Provider()),

//       //
//     ],
//     child: MaterialApp(
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         brightness: Brightness.light,
//         fontFamily: 'Roboto',
//         primaryColor: const Color(0xFF00796B),
//       ),
//       home: const ModernLoginScreen(),
//     ),
//   ),
// );

// // ─── Login Screen ─────────────────────────────────────────────────────────────

// class ModernLoginScreen extends StatefulWidget {
//   const ModernLoginScreen({super.key});

//   @override
//   State<ModernLoginScreen> createState() => _ModernLoginScreenState();
// }

// class _ModernLoginScreenState extends State<ModernLoginScreen> {
//   // ── Static data ──────────────────────────────────────────────────────────
//   static const _modes = ['Main', 'Entrance', 'Store', 'CSSD'];
//   static const _otNumbers = ['OT 1', 'OT 2', 'OT 3', 'OT 4', 'OT 5'];

//   // ── State ────────────────────────────────────────────────────────────────
//   String? _selectedMode;
//   String? _selectedOT;
//   bool _isLoading = false;

//   // ── Controllers ──────────────────────────────────────────────────────────
//   final _formKey = GlobalKey<FormState>();
//   final _codeController = TextEditingController();
//   final _patientSystemIpController = TextEditingController();
//   final _storeMgmtIpController = TextEditingController();
//   final _cameraIpController = TextEditingController();
//   final _esp32IpController = TextEditingController();
//   final _uniqueCodeController = TextEditingController();

//   // ── Lifecycle ─────────────────────────────────────────────────────────────
//   @override
//   void initState() {
//     super.initState();
//     _checkLoginStatus();
//   }

//   @override
//   void dispose() {
//     _codeController.dispose();
//     _patientSystemIpController.dispose();
//     _storeMgmtIpController.dispose();
//     _cameraIpController.dispose();
//     _esp32IpController.dispose();
//     _uniqueCodeController.dispose();
//     super.dispose();
//   }

//   // ── Persistence ───────────────────────────────────────────────────────────
//   Future<void> _checkLoginStatus() async {
//     final prefs = await SharedPreferences.getInstance();
//     if (prefs.getBool(_PrefKeys.isLoggedIn) ?? false) {
//       _navigateToDashboard();
//     } else {
//       await _loadSavedValues();
//     }
//   }

//   Future<void> _loadSavedValues() async {
//     final prefs = await SharedPreferences.getInstance();

//     String? mode = prefs.getString(_PrefKeys.selectedMode);
//     String? ot = prefs.getString(_PrefKeys.selectedOT);

//     setState(() {
//       _selectedMode = _modes.contains(mode) ? mode : null;
//       _selectedOT = _otNumbers.contains(ot) ? ot : null;

//       _codeController.text = prefs.getString(_PrefKeys.accessCode) ?? '';
//       _patientSystemIpController.text =
//           prefs.getString(_PrefKeys.patientSystemIp) ?? '';
//       _storeMgmtIpController.text =
//           prefs.getString(_PrefKeys.storeMgmtIp) ?? '';
//       _cameraIpController.text = prefs.getString(_PrefKeys.cameraIp) ?? '';
//       _esp32IpController.text = prefs.getString(_PrefKeys.esp32Ip) ?? '';
//       _uniqueCodeController.text = prefs.getString(_PrefKeys.uniqueCode) ?? '';
//     });
//   }

//   Future<void> _saveValues() async {
//     final prefs = await SharedPreferences.getInstance();
//     await Future.wait([
//       prefs.setString(_PrefKeys.selectedMode, _selectedMode ?? ''),
//       prefs.setString(_PrefKeys.selectedOT, _selectedOT ?? ''),
//       prefs.setString(_PrefKeys.accessCode, _codeController.text),
//       prefs.setString(
//         _PrefKeys.patientSystemIp,
//         _patientSystemIpController.text,
//       ),
//       prefs.setString(_PrefKeys.storeMgmtIp, _storeMgmtIpController.text),
//       prefs.setString(_PrefKeys.cameraIp, _cameraIpController.text),
//       prefs.setString(_PrefKeys.esp32Ip, _esp32IpController.text),
//       prefs.setString(_PrefKeys.uniqueCode, _uniqueCodeController.text),
//     ]);
//   }

//   // ── Auth actions ──────────────────────────────────────────────────────────
//   Future<void> _handleLogin() async {
//     if (!(_formKey.currentState?.validate() ?? false)) {
//       _showSnack('Please fill all required fields', Colors.orange);
//       return;
//     }

//     setState(() => _isLoading = true);

//     try {
//       await _saveValues();
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setBool(_PrefKeys.isLoggedIn, true);
//       if (mounted) _navigateToDashboard();
//     } catch (e) {
//       if (mounted) _showSnack('Login failed: $e', Colors.red);
//     } finally {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }

//   Future<void> _handleLogout() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.clear();

//     if (mounted) {
//       Navigator.of(context).pushAndRemoveUntil(
//         MaterialPageRoute(builder: (_) => const ModernLoginScreen()),
//         (_) => false,
//       );
//     }
//   }

//   void _navigateToDashboard() {
//     Navigator.pushReplacement(
//       context,
//       PageRouteBuilder(
//         transitionDuration: const Duration(milliseconds: 400),
//         pageBuilder: (_, __, ___) => MedicalDashboard(onLogout: _handleLogout),
//         transitionsBuilder: (_, animation, __, child) => SlideTransition(
//           position: animation.drive(
//             Tween(
//               begin: const Offset(1.0, 0.0),
//               end: Offset.zero,
//             ).chain(CurveTween(curve: Curves.easeInOut)),
//           ),
//           child: child,
//         ),
//       ),
//     );
//   }

//   // ── Helpers ───────────────────────────────────────────────────────────────
//   void _showSnack(String msg, Color color) {
//     ScaffoldMessenger.of(
//       context,
//     ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
//   }

//   // ── Validators ────────────────────────────────────────────────────────────
//   static final _ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(:\d{1,5})?$');

//   String? _validateIp(String? value) {
//     if (value == null || value.isEmpty) return 'IP address is required';
//     if (!_ipRegex.hasMatch(value)) {
//       return 'Enter a valid IP (e.g. 192.168.1.1 or 192.168.1.1:8080)';
//     }

//     final ipPart = value.split(':').first;
//     for (final part in ipPart.split('.')) {
//       final n = int.tryParse(part);
//       if (n == null || n < 0 || n > 255) {
//         return 'Each octet must be 0–255';
//       }
//     }

//     if (value.contains(':')) {
//       final port = int.tryParse(value.split(':').last);
//       if (port == null || port < 1 || port > 65535) {
//         return 'Port must be 1–65535';
//       }
//     }
//     return null;
//   }

//   String? _validateRequired(String? value) =>
//       (value == null || value.isEmpty) ? 'This field is required' : null;

//   // ── Border helpers ────────────────────────────────────────────────────────
//   static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
//     borderRadius: BorderRadius.circular(8),
//     borderSide: BorderSide(color: color),
//   );

//   // ── Build ─────────────────────────────────────────────────────────────────
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: _AppColors.background,
//       body: SafeArea(
//         child: LayoutBuilder(
//           builder: (context, constraints) => SingleChildScrollView(
//             child: ConstrainedBox(
//               constraints: BoxConstraints(minHeight: constraints.maxHeight),
//               child: IntrinsicHeight(
//                 child: Column(
//                   children: [
//                     const SizedBox(height: 40),
//                     const Text(
//                       'WELCOME TO WIESPL DIGITAL OR',
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontWeight: FontWeight.bold,
//                         fontSize: 24,
//                       ),
//                       textAlign: TextAlign.center,
//                     ),
//                     const SizedBox(height: 40),
//                     Center(
//                       child: Container(
//                         width: _kCardWidth,
//                         constraints: BoxConstraints(
//                           maxHeight: constraints.maxHeight - 200,
//                         ),
//                         clipBehavior: Clip.antiAlias,
//                         decoration: BoxDecoration(
//                           color: _AppColors.surface,
//                           borderRadius: BorderRadius.circular(20),
//                           boxShadow: [
//                             BoxShadow(
//                               color: _AppColors.gradientStart.withOpacity(0.5),
//                               blurRadius: 80,
//                               spreadRadius: 5,
//                             ),
//                           ],
//                         ),
//                         child: Row(
//                           children: [
//                             Expanded(child: _buildLeftPanel()),
//                             Expanded(child: _buildRightPanel()),
//                           ],
//                         ),
//                       ),
//                     ),
//                     const SizedBox(height: 40),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   // ── Left panel (image) ────────────────────────────────────────────────────
//   Widget _buildLeftPanel() => Container(
//     decoration: const BoxDecoration(
//       gradient: LinearGradient(
//         colors: [_AppColors.gradientStart, _AppColors.gradientEnd],
//         begin: Alignment.topLeft,
//         end: Alignment.bottomRight,
//       ),
//       image: DecorationImage(
//         image: AssetImage('assets/nbnb.jpeg'),
//         fit: BoxFit.cover,
//       ),
//     ),
//   );

//   // ── Right panel (form) ────────────────────────────────────────────────────
//   Widget _buildRightPanel() => Padding(
//     padding: const EdgeInsets.symmetric(
//       horizontal: _kFormPaddingH,
//       vertical: _kFormPaddingV,
//     ),
//     child: Form(
//       key: _formKey,
//       child: SingleChildScrollView(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text(
//               'System Configuration',
//               style: TextStyle(
//                 color: Colors.white,
//                 fontSize: 22,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//             const SizedBox(height: 25),

//             _buildDropdown(
//               'Select Mode *',
//               _modes,
//               _selectedMode,
//               (v) => setState(() => _selectedMode = v),
//               validator: (v) =>
//                   (v == null || v.isEmpty) ? 'Please select a mode' : null,
//             ),
//             const SizedBox(height: _kFieldSpacing),

//             _buildDropdown(
//               'Select OT *',
//               _otNumbers,
//               _selectedOT,
//               (v) => setState(() => _selectedOT = v),
//               validator: (v) =>
//                   (v == null || v.isEmpty) ? 'Please select an OT' : null,
//             ),
//             const SizedBox(height: _kFieldSpacing),

//             _buildTextField(
//               _codeController,
//               'Access Code *',
//               Icons.lock_outline,
//               validator: _validateRequired,
//             ),
//             _buildTextField(
//               _patientSystemIpController,
//               'Patient System IP *',
//               Icons.computer,
//               validator: _validateIp,
//             ),
//             _buildTextField(
//               _storeMgmtIpController,
//               'Store Management IP *',
//               Icons.storage,
//               validator: _validateIp,
//             ),
//             _buildTextField(
//               _cameraIpController,
//               'Camera IP *',
//               Icons.videocam_outlined,
//               validator: _validateIp,
//             ),
//             _buildTextField(
//               _esp32IpController,
//               'ESP32 IP *',
//               Icons.memory,
//               validator: _validateIp,
//             ),
//             _buildTextField(
//               _uniqueCodeController,
//               'Unique Code *',
//               Icons.qr_code,
//               validator: _validateRequired,
//             ),

//             const SizedBox(height: 30),
//             _buildLoginButton(),
//             const SizedBox(height: 20),
//           ],
//         ),
//       ),
//     ),
//   );

//   // ── Login button ──────────────────────────────────────────────────────────
//   Widget _buildLoginButton() => Container(
//     width: double.infinity,
//     height: 50,
//     decoration: BoxDecoration(
//       borderRadius: BorderRadius.circular(8),
//       gradient: const LinearGradient(
//         colors: [_AppColors.btnBlue, _AppColors.btnPink],
//       ),
//     ),
//     child: ElevatedButton(
//       style: ElevatedButton.styleFrom(
//         backgroundColor: Colors.transparent,
//         shadowColor: Colors.transparent,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//       ),
//       onPressed: _isLoading ? null : _handleLogin,
//       child: _isLoading
//           ? const SizedBox(
//               height: 20,
//               width: 20,
//               child: CircularProgressIndicator(
//                 color: Colors.white,
//                 strokeWidth: 2,
//               ),
//             )
//           : const Text(
//               'LOGIN',
//               style: TextStyle(
//                 color: Colors.white,
//                 fontWeight: FontWeight.bold,
//                 fontSize: 16,
//               ),
//             ),
//     ),
//   );

//   // ── Reusable text field ───────────────────────────────────────────────────
//   Widget _buildTextField(
//     TextEditingController controller,
//     String hint,
//     IconData icon, {
//     String? Function(String?)? validator,
//   }) => Padding(
//     padding: const EdgeInsets.only(bottom: 12),
//     child: TextFormField(
//       controller: controller,
//       style: const TextStyle(color: Colors.white, fontSize: 14),
//       validator: validator,
//       decoration: InputDecoration(
//         hintText: hint,
//         hintStyle: const TextStyle(color: Colors.grey),
//         prefixIcon: Icon(icon, color: Colors.grey, size: 20),
//         filled: true,
//         fillColor: _AppColors.inputFill,
//         contentPadding: const EdgeInsets.symmetric(horizontal: 16),
//         enabledBorder: _inputBorder(_AppColors.inputBorder),
//         focusedBorder: _inputBorder(Colors.blueAccent),
//         errorBorder: _inputBorder(Colors.red),
//         focusedErrorBorder: _inputBorder(Colors.red),
//         errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
//       ),
//     ),
//   );

//   // ── Reusable dropdown ─────────────────────────────────────────────────────
//   Widget _buildDropdown(
//     String hint,
//     List<String> items,
//     String? selectedValue,
//     ValueChanged<String?> onChanged, {
//     String? Function(String?)? validator,
//   }) => FormField<String>(
//     validator: validator,
//     builder: (state) => Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Container(
//           padding: const EdgeInsets.symmetric(horizontal: 16),
//           decoration: BoxDecoration(
//             color: _AppColors.inputFill,
//             borderRadius: BorderRadius.circular(8),
//             border: Border.all(
//               color: state.hasError ? Colors.red : _AppColors.inputBorder,
//             ),
//           ),
//           child: DropdownButtonHideUnderline(
//             child: DropdownButton<String>(
//               value: items.contains(selectedValue) ? selectedValue : null,
//               hint: Text(
//                 hint,
//                 style: const TextStyle(color: Colors.grey, fontSize: 14),
//               ),
//               dropdownColor: _AppColors.surface,
//               isExpanded: true,
//               style: const TextStyle(color: Colors.white),
//               items: items
//                   .map((v) => DropdownMenuItem(value: v, child: Text(v)))
//                   .toList(),
//               onChanged: (v) {
//                 onChanged(v);
//                 state.didChange(v);
//               },
//             ),
//           ),
//         ),
//         if (state.hasError)
//           Padding(
//             padding: const EdgeInsets.only(top: 4, left: 12),
//             child: Text(
//               state.errorText ?? '',
//               style: const TextStyle(color: Colors.red, fontSize: 12),
//             ),
//           ),
//       ],
//     ),
//   );
// }

// // import 'dart:io';
// // import 'dart:convert';
// // import 'package:flutter/material.dart';
// // import 'package:audioplayers/audioplayers.dart';
// // import 'package:image_picker/image_picker.dart';
// // import 'package:http/http.dart' as http;
// // import 'package:http_parser/http_parser.dart';
// // import 'package:path/path.dart' as path;

// // void main() {
// //   runApp(const MyApp());
// // }

// // class MyApp extends StatelessWidget {
// //   const MyApp({Key? key}) : super(key: key);

// //   @override
// //   Widget build(BuildContext context) {
// //     return MaterialApp(
// //       debugShowCheckedModeBanner: false,
// //       theme: ThemeData(primarySwatch: Colors.teal),
// //       home: const MusicScreen(),
// //     );
// //   }
// // }

// // class MusicScreen extends StatefulWidget {
// //   const MusicScreen({Key? key}) : super(key: key);

// //   @override
// //   State<MusicScreen> createState() => _MusicScreenState();
// // }

// // class _MusicScreenState extends State<MusicScreen> {
// //   final String serverUrl = 'http://192.168.0.137:3000';

// //   late AudioPlayer _audioPlayer;
// //   List<Map<String, dynamic>> _musicList = [];
// //   bool _isLoading = false;
// //   bool _isUploading = false;

// //   Map<String, dynamic>? _currentPlaying;
// //   bool _isPlaying = false;
// //   Duration _position = Duration.zero;
// //   Duration _duration = Duration.zero;

// //   @override
// //   void initState() {
// //     super.initState();
// //     _audioPlayer = AudioPlayer();
// //     _setupAudioPlayer();
// //     _fetchMusic();
// //   }

// //   void _setupAudioPlayer() {
// //     _audioPlayer.onPlayerStateChanged.listen((state) {
// //       if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
// //     });

// //     _audioPlayer.onDurationChanged.listen((d) {
// //       if (mounted) setState(() => _duration = d);
// //     });

// //     _audioPlayer.onPositionChanged.listen((p) {
// //       if (mounted) setState(() => _position = p);
// //     });

// //     _audioPlayer.onPlayerComplete.listen((_) => _playNext());
// //   }

// //   Future<void> _fetchMusic() async {
// //     setState(() => _isLoading = true);
// //     try {
// //       final response = await http.get(Uri.parse('$serverUrl/api/music'));
// //       if (response.statusCode == 200) {
// //         final data = json.decode(response.body);
// //         if (data is List) {
// //           setState(() {
// //             _musicList = data.map((item) {
// //               return {
// //                 'id': item['id'] ?? 0,
// //                 'name': item['name'] ?? 'Unknown',
// //                 'filename': item['filename'] ?? '',
// //                 'file_size': item['file_size'] ?? 0,
// //                 'file_type': item['file_type'] ?? 'audio/mpeg',
// //                 'upload_date':
// //                     item['upload_date'] ?? DateTime.now().toIso8601String(),
// //               };
// //             }).toList();
// //           });
// //         }
// //       }
// //     } catch (e) {
// //       _showSnackBar('Error: $e');
// //     }
// //     setState(() => _isLoading = false);
// //   }

// //   Future<void> _pickAndUpload() async {
// //     final ImagePicker picker = ImagePicker();

// //     try {
// //       final XFile? file = await picker.pickMedia();

// //       if (file == null) return;

// //       final bytes = await file.readAsBytes();
// //       String fileName = path.basename(file.path);

// //       if (!fileName.toLowerCase().endsWith('.mp3')) {
// //         fileName = '${path.basenameWithoutExtension(fileName)}.mp3';
// //       }

// //       if (bytes.length > 60 * 1024 * 1024) {
// //         _showSnackBar('File too large (max 60MB)');
// //         return;
// //       }

// //       String? musicName = await showDialog<String>(
// //         context: context,
// //         builder: (context) {
// //           String name = path.basenameWithoutExtension(fileName);
// //           final controller = TextEditingController(text: name);
// //           return AlertDialog(
// //             title: const Text('Add Music'),
// //             content: TextField(
// //               autofocus: true,
// //               decoration: const InputDecoration(
// //                 labelText: 'Music Name',
// //                 border: OutlineInputBorder(),
// //               ),
// //               controller: controller,
// //             ),
// //             actions: [
// //               TextButton(
// //                 onPressed: () => Navigator.pop(context),
// //                 child: const Text('Cancel'),
// //               ),
// //               ElevatedButton(
// //                 onPressed: () => Navigator.pop(context, controller.text),
// //                 child: const Text('Upload'),
// //               ),
// //             ],
// //           );
// //         },
// //       );

// //       if (musicName == null || musicName.isEmpty) return;

// //       setState(() => _isUploading = true);

// //       var request = http.MultipartRequest(
// //         'POST',
// //         Uri.parse('$serverUrl/api/music'),
// //       );
// //       request.fields['name'] = musicName;

// //       request.files.add(
// //         http.MultipartFile.fromBytes(
// //           'music',
// //           bytes,
// //           filename: fileName,
// //           contentType: MediaType('audio', 'mpeg'),
// //         ),
// //       );

// //       final response = await request.send();
// //       final responseBody = await response.stream.bytesToString();

// //       if (response.statusCode == 200) {
// //         var data = json.decode(responseBody);
// //         // Add with null safety
// //         setState(() {
// //           _musicList.insert(0, {
// //             'id': data['id'] ?? 0,
// //             'name': data['name'] ?? musicName,
// //             'filename': data['filename'] ?? fileName,
// //             'file_size': data['file_size'] ?? bytes.length,
// //             'file_type': data['file_type'] ?? 'audio/mpeg',
// //             'upload_date':
// //                 data['upload_date'] ?? DateTime.now().toIso8601String(),
// //           });
// //         });
// //         _showSnackBar('Uploaded successfully!', false);
// //       } else {
// //         _showSnackBar('Upload failed: ${response.statusCode}');
// //       }
// //     } catch (e) {
// //       print('Upload error: $e');
// //       _showSnackBar('Upload error: $e');
// //     } finally {
// //       setState(() => _isUploading = false);
// //     }
// //   }

// //   Future<void> _deleteMusic(Map<String, dynamic> music) async {
// //     bool? confirm = await showDialog<bool>(
// //       context: context,
// //       builder: (c) => AlertDialog(
// //         title: const Text('Delete'),
// //         content: Text('Delete "${music['name']}"?'),
// //         actions: [
// //           TextButton(
// //             onPressed: () => Navigator.pop(c, false),
// //             child: const Text('Cancel'),
// //           ),
// //           TextButton(
// //             onPressed: () => Navigator.pop(c, true),
// //             style: TextButton.styleFrom(foregroundColor: Colors.red),
// //             child: const Text('Delete'),
// //           ),
// //         ],
// //       ),
// //     );

// //     if (confirm != true) return;

// //     try {
// //       await http.delete(Uri.parse('$serverUrl/api/music/${music['id']}'));
// //       if (_currentPlaying?['id'] == music['id']) {
// //         await _audioPlayer.stop();
// //         setState(() => _currentPlaying = null);
// //       }
// //       setState(() => _musicList.removeWhere((m) => m['id'] == music['id']));
// //       _showSnackBar('Deleted', false);
// //     } catch (e) {
// //       _showSnackBar('Delete failed');
// //     }
// //   }

// //   Future<void> _playMusic(Map<String, dynamic> music) async {
// //     try {
// //       if (_currentPlaying?['id'] == music['id']) {
// //         _isPlaying ? await _audioPlayer.pause() : await _audioPlayer.resume();
// //         return;
// //       }

// //       setState(() => _currentPlaying = music);
// //       await _audioPlayer.play(
// //         UrlSource('$serverUrl/uploads/music/${music['filename']}'),
// //       );
// //     } catch (e) {
// //       _showSnackBar('Playback error');
// //     }
// //   }

// //   void _playNext() {
// //     if (_musicList.isEmpty || _currentPlaying == null) return;
// //     int index = _musicList.indexWhere((m) => m['id'] == _currentPlaying!['id']);
// //     if (index != -1 && index < _musicList.length - 1) {
// //       _playMusic(_musicList[index + 1]);
// //     }
// //   }

// //   void _playPrevious() {
// //     if (_musicList.isEmpty || _currentPlaying == null) return;
// //     int index = _musicList.indexWhere((m) => m['id'] == _currentPlaying!['id']);
// //     if (index > 0) _playMusic(_musicList[index - 1]);
// //   }

// //   void _showSnackBar(String msg, [bool error = true]) {
// //     if (!mounted) return;
// //     ScaffoldMessenger.of(context).showSnackBar(
// //       SnackBar(
// //         content: Text(msg),
// //         backgroundColor: error ? Colors.red : Colors.green,
// //         duration: const Duration(seconds: 2),
// //       ),
// //     );
// //   }

// //   String _formatTime(Duration d) {
// //     String minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
// //     String seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
// //     return '$minutes:$seconds';
// //   }

// //   String _formatSize(dynamic bytes) {
// //     if (bytes == null) return '--';
// //     int size = bytes is int ? bytes : int.tryParse(bytes.toString()) ?? 0;
// //     if (size < 1024) return '$size B';
// //     if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
// //     return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       backgroundColor: Colors.grey[100],
// //       appBar: AppBar(
// //         title: const Text('Music Library'),
// //         actions: [
// //           IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchMusic),
// //         ],
// //       ),
// //       body: Column(
// //         children: [
// //           Padding(
// //             padding: const EdgeInsets.all(16),
// //             child: ElevatedButton.icon(
// //               onPressed: _isUploading ? null : _pickAndUpload,
// //               icon: _isUploading
// //                   ? const SizedBox(
// //                       width: 20,
// //                       height: 20,
// //                       child: CircularProgressIndicator(strokeWidth: 2),
// //                     )
// //                   : const Icon(Icons.add),
// //               label: Text(_isUploading ? 'Uploading...' : 'Add Music'),
// //               style: ElevatedButton.styleFrom(
// //                 minimumSize: const Size(double.infinity, 50),
// //                 backgroundColor: Colors.teal,
// //                 foregroundColor: Colors.white,
// //               ),
// //             ),
// //           ),

// //           if (_currentPlaying != null) _buildMiniPlayer(),

// //           Expanded(child: _buildMusicList()),
// //         ],
// //       ),
// //       floatingActionButton: FloatingActionButton(
// //         onPressed: _isUploading ? null : _pickAndUpload,
// //         backgroundColor: Colors.teal,
// //         child: const Icon(Icons.add),
// //       ),
// //     );
// //   }

// //   Widget _buildMiniPlayer() {
// //     return Container(
// //       margin: const EdgeInsets.all(12),
// //       padding: const EdgeInsets.all(12),
// //       decoration: BoxDecoration(
// //         color: Colors.white,
// //         borderRadius: BorderRadius.circular(12),
// //       ),
// //       child: Column(
// //         children: [
// //           Row(
// //             children: [
// //               Container(
// //                 width: 45,
// //                 height: 45,
// //                 decoration: BoxDecoration(
// //                   color: Colors.teal.shade100,
// //                   borderRadius: BorderRadius.circular(8),
// //                 ),
// //                 child: Icon(Icons.music_note, color: Colors.teal.shade800),
// //               ),
// //               const SizedBox(width: 12),
// //               Expanded(
// //                 child: Column(
// //                   crossAxisAlignment: CrossAxisAlignment.start,
// //                   children: [
// //                     Text(
// //                       _currentPlaying!['name'] ?? 'Unknown',
// //                       style: const TextStyle(fontWeight: FontWeight.bold),
// //                     ),
// //                     Text(
// //                       _formatSize(_currentPlaying!['file_size']),
// //                       style: TextStyle(fontSize: 12, color: Colors.grey[600]),
// //                     ),
// //                   ],
// //                 ),
// //               ),
// //               IconButton(
// //                 icon: const Icon(Icons.skip_previous),
// //                 onPressed: _playPrevious,
// //               ),
// //               IconButton(
// //                 icon: Icon(
// //                   _isPlaying ? Icons.pause_circle : Icons.play_circle,
// //                   size: 40,
// //                   color: Colors.teal,
// //                 ),
// //                 onPressed: () => _playMusic(_currentPlaying!),
// //               ),
// //               IconButton(
// //                 icon: const Icon(Icons.skip_next),
// //                 onPressed: _playNext,
// //               ),
// //             ],
// //           ),
// //           Row(
// //             children: [
// //               Text(
// //                 _formatTime(_position),
// //                 style: const TextStyle(fontSize: 12),
// //               ),
// //               Expanded(
// //                 child: Slider(
// //                   value: _position.inSeconds.toDouble().clamp(
// //                     0,
// //                     _duration.inSeconds.toDouble(),
// //                   ),
// //                   max: _duration.inSeconds.toDouble() > 0
// //                       ? _duration.inSeconds.toDouble()
// //                       : 1.0,
// //                   activeColor: Colors.teal,
// //                   onChanged: (v) =>
// //                       _audioPlayer.seek(Duration(seconds: v.toInt())),
// //                 ),
// //               ),
// //               Text(
// //                 _formatTime(_duration),
// //                 style: const TextStyle(fontSize: 12),
// //               ),
// //             ],
// //           ),
// //         ],
// //       ),
// //     );
// //   }

// //   Widget _buildMusicList() {
// //     if (_isLoading) return const Center(child: CircularProgressIndicator());

// //     if (_musicList.isEmpty) {
// //       return Center(
// //         child: Column(
// //           mainAxisAlignment: MainAxisAlignment.center,
// //           children: [
// //             Icon(Icons.music_off, size: 64, color: Colors.grey[400]),
// //             const SizedBox(height: 16),
// //             const Text('No music files', style: TextStyle(fontSize: 18)),
// //           ],
// //         ),
// //       );
// //     }

// //     return ListView.builder(
// //       padding: const EdgeInsets.all(12),
// //       itemCount: _musicList.length,
// //       itemBuilder: (c, i) {
// //         var music = _musicList[i];
// //         var isCurrent = _currentPlaying?['id'] == music['id'];

// //         return Card(
// //           margin: const EdgeInsets.only(bottom: 8),
// //           shape: RoundedRectangleBorder(
// //             borderRadius: BorderRadius.circular(12),
// //           ),
// //           child: ListTile(
// //             leading: Container(
// //               width: 50,
// //               height: 50,
// //               decoration: BoxDecoration(
// //                 color: isCurrent ? Colors.teal.shade100 : Colors.grey.shade200,
// //                 borderRadius: BorderRadius.circular(8),
// //               ),
// //               child: Icon(
// //                 Icons.music_note,
// //                 color: isCurrent ? Colors.teal : Colors.grey,
// //               ),
// //             ),
// //             title: Text(music['name'] ?? 'Unknown'),
// //             subtitle: Text(_formatSize(music['file_size'])),
// //             trailing: Row(
// //               mainAxisSize: MainAxisSize.min,
// //               children: [
// //                 IconButton(
// //                   icon: Icon(
// //                     isCurrent && _isPlaying
// //                         ? Icons.pause_circle_outlined
// //                         : Icons.play_circle_outlined,
// //                   ),
// //                   onPressed: () => _playMusic(music),
// //                 ),
// //                 IconButton(
// //                   icon: const Icon(Icons.delete_outline, color: Colors.red),
// //                   onPressed: () => _deleteMusic(music),
// //                 ),
// //               ],
// //             ),
// //             onTap: () => _playMusic(music),
// //           ),
// //         );
// //       },
// //     );
// //   }

// //   @override
// //   void dispose() {
// //     _audioPlayer.dispose();
// //     super.dispose();
// //   }
// // }
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiespl_contrl_panel/home/homescreen.dart';
import 'package:wiespl_contrl_panel/provider/espprovider.dart';
import 'package:wiespl_contrl_panel/provider/orsystemprovider.dart';
import 'package:wiespl_contrl_panel/provider/streamrecorderprovider.dart';
import 'package:wiespl_contrl_panel/provider/videoprovider.dart'; // Add this import

// ─── Enums ───────────────────────────────────────────────────────────────────

enum ScreenSize { mobile, tablet, desktop }

enum ORViewMode { dashboard, orMode }

// ─── Constants ───────────────────────────────────────────────────────────────

class _AppColors {
  static const background = Color(0xFF0F1117);
  static const surface = Color(0xFF1A1D26);
  static const inputFill = Color(0xFF252936);
  static const inputBorder = Color(0xFF3D4454);
  static const gradientStart = Color(0xFF2C105A); // Fixed typo: was 2C10_5A
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
      ChangeNotifierProvider(
        create: (_) => VideoSwitcherProvider(),
      ), // ✅ ADD THIS
      // Add StreamRecorderProvider if you have it
      // ChangeNotifierProvider(create: (_) => StreamRecorderProvider()),
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
