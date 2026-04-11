// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';
// import 'dart:typed_data';
// import 'dart:ui' as ui;
// import 'dart:math';

// import 'package:chewie/chewie.dart';
// import 'package:device_info_plus/device_info_plus.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/rendering.dart';
// import 'package:flutter/services.dart';

// import 'package:path/path.dart' as path;
// import 'package:permission_handler/permission_handler.dart';
// import 'package:fluttertoast/fluttertoast.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:open_filex/open_filex.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:provider/provider.dart';
// import 'package:video_player/video_player.dart';
// import 'package:intl/intl.dart';
// import 'package:wiespl_contrl_panel/or/gridscreen.dart';
// import 'package:wiespl_contrl_panel/pi_api/piapi.dart';
// import 'package:wiespl_contrl_panel/provider/videoprovider.dart';

// class VideoPlayerScreen extends StatefulWidget {
//   final String filePath;
//   final String fileName;

//   const VideoPlayerScreen({
//     Key? key,
//     required this.filePath,
//     required this.fileName,
//   }) : super(key: key);

//   @override
//   State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
// }

// class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
//   late VideoPlayerController _videoController;
//   ChewieController? _chewieController;
//   bool _isInitialized = false;
//   String? _error;
//   bool _isMp4 = true;

//   @override
//   void initState() {
//     super.initState();
//     _initializePlayer();
//   }

//   Future<void> _initializePlayer() async {
//     try {
//       final file = File(widget.filePath);
//       if (!await file.exists()) {
//         throw "File not found at ${widget.filePath}";
//       }

//       _isMp4 = widget.filePath.toLowerCase().endsWith('.mp4');

//       _videoController = VideoPlayerController.file(file);
//       await _videoController.initialize();

//       // Mute the video
//       await _videoController.setVolume(0.0);

//       _chewieController = ChewieController(
//         videoPlayerController: _videoController,
//         autoPlay: true,
//         looping: false,
//         aspectRatio: _videoController.value.aspectRatio,
//         // Remove audio controls
//         showControls: true,
//         allowMuting: false, // Disable mute button
//         allowPlaybackSpeedChanging: true,
//         autoInitialize: true,
//         errorBuilder: (context, errorMessage) {
//           return Center(
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Icon(Icons.error_outline, color: Colors.red, size: 50),
//                 SizedBox(height: 10),
//                 Text(
//                   "Video Error",
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 SizedBox(height: 5),
//                 Text(
//                   errorMessage,
//                   style: TextStyle(color: Colors.white70),
//                   textAlign: TextAlign.center,
//                 ),
//                 SizedBox(height: 20),
//                 if (!_isMp4)
//                   Text(
//                     "Note: This is a raw MJPEG file. Try converting to MP4 first.",
//                     style: TextStyle(color: Colors.orange, fontSize: 12),
//                     textAlign: TextAlign.center,
//                   ),
//               ],
//             ),
//           );
//         },
//         allowedScreenSleep: false,
//         materialProgressColors: ChewieProgressColors(
//           playedColor: Colors.red,
//           handleColor: Colors.red,
//           backgroundColor: Colors.grey,
//           bufferedColor: Colors.grey.withOpacity(0.5),
//         ),
//       );

//       if (mounted) {
//         setState(() => _isInitialized = true);
//       }

//       Future.delayed(Duration(seconds: 3), () {
//         if (mounted && !_videoController.value.isPlaying && _isInitialized) {
//           setState(() {
//             _error = "Video failed to play. May be corrupted or wrong format.";
//           });
//         }
//       });
//     } catch (e) {
//       print("=== DEBUG: Video player error: $e ===");
//       if (mounted) {
//         setState(() => _error = e.toString());
//       }
//     }
//   }

//   @override
//   void dispose() {
//     _videoController.dispose();
//     _chewieController?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         title: Row(
//           children: [
//             Icon(
//               _isMp4 ? Icons.videocam : Icons.warning_amber,
//               color: _isMp4 ? Colors.white : Colors.orange,
//             ),
//             SizedBox(width: 8),
//             Expanded(
//               child: Text(widget.fileName, overflow: TextOverflow.ellipsis),
//             ),
//             if (!_isMp4)
//               Container(
//                 margin: EdgeInsets.only(left: 8),
//                 padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: Colors.orange.withOpacity(0.2),
//                   borderRadius: BorderRadius.circular(4),
//                   border: Border.all(color: Colors.orange),
//                 ),
//                 child: Text(
//                   "MJPEG",
//                   style: TextStyle(
//                     color: Colors.orange,
//                     fontSize: 10,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ),
//           ],
//         ),
//         backgroundColor: Colors.black,
//         actions: [
//           if (_isMp4)
//             IconButton(
//               icon: Icon(Icons.info_outline),
//               onPressed: () => _showVideoInfo(context),
//             ),
//         ],
//       ),
//       body: _error != null
//           ? Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Icon(Icons.error_outline, color: Colors.red, size: 60),
//                   SizedBox(height: 20),
//                   Text(
//                     "Error playing video",
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 20,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   SizedBox(height: 10),
//                   Padding(
//                     padding: const EdgeInsets.symmetric(horizontal: 20),
//                     child: Text(
//                       _error!,
//                       style: TextStyle(color: Colors.white70),
//                       textAlign: TextAlign.center,
//                     ),
//                   ),
//                   SizedBox(height: 20),
//                   ElevatedButton(
//                     onPressed: () => Navigator.pop(context),
//                     child: Text("Go Back"),
//                   ),
//                 ],
//               ),
//             )
//           : _isInitialized
//           ? Chewie(controller: _chewieController!)
//           : Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   CircularProgressIndicator(color: Colors.red),
//                   SizedBox(height: 20),
//                   Text(
//                     "Loading video...",
//                     style: TextStyle(color: Colors.white70),
//                   ),
//                   SizedBox(height: 10),
//                   if (!_isMp4)
//                     Text(
//                       "MJPEG files may take longer to load",
//                       style: TextStyle(color: Colors.orange, fontSize: 12),
//                     ),
//                 ],
//               ),
//             ),
//     );
//   }

//   void _showVideoInfo(BuildContext context) async {
//     try {
//       final file = File(widget.filePath);
//       if (await file.exists()) {
//         final stat = file.statSync();
//         final fileSize = await file.length();

//         showDialog(
//           context: context,
//           builder: (context) => AlertDialog(
//             title: Text('Video Information'),
//             content: SingleChildScrollView(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Text('Name: ${widget.fileName}'),
//                   Text('Format: ${_isMp4 ? "MP4" : "MJPEG"}'),
//                   Text('Size: ${_formatBytes(fileSize)}'),
//                   Text(
//                     'Duration: ${_videoController.value.duration.toString().split('.')[0]}',
//                   ),
//                   Text(
//                     'Resolution: ${_videoController.value.size.width.toInt()}x${_videoController.value.size.height.toInt()}',
//                   ),
//                   Text(
//                     'Aspect Ratio: ${_videoController.value.aspectRatio.toStringAsFixed(2)}',
//                   ),
//                   Text(
//                     'Created: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(stat.changed)}',
//                   ),
//                 ],
//               ),
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.pop(context),
//                 child: Text('Close'),
//               ),
//             ],
//           ),
//         );
//       }
//     } catch (e) {
//       print("=== DEBUG: Error getting video info: $e ===");
//     }
//   }
// }

// // Helper function for formatting bytes
// String _formatBytes(int bytes) {
//   if (bytes <= 0) return '0 B';
//   const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
//   final i = (bytes > 0 ? (log(bytes) / log(1024)) : 0).floor();
//   return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
// }

// // ==================== HELPER METHODS ====================

// Color _getStatusColor(String? status) {
//   if (status == null) return Colors.grey;
//   switch (status.toLowerCase()) {
//     case 'in surgery':
//       return Colors.red;
//     case 'waiting':
//       return Colors.orange;
//     case 'recovery':
//       return Colors.blue;
//     case 'discharged':
//       return Colors.green;
//     case 'pre-op':
//       return Colors.purple;
//     default:
//       return Colors.grey;
//   }
// }

// String _getStatusText(Patient patient) {
//   if (patient.operationDate != null) {
//     final now = DateTime.now();
//     final opDate = DateTime.tryParse(patient.operationDate ?? '');
//     if (opDate != null && opDate.isAfter(now)) return 'Scheduled';
//     if (opDate != null && opDate.isBefore(now)) return 'Completed';
//   }
//   return patient.patientCategory ?? 'General';
// }

// String _getTodayDate() {
//   final now = DateTime.now();
//   return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
// }

// // ==================== CHECKLIST DISPLAY METHODS ====================

// Widget _buildChecklistItem(String label, dynamic value, {Color? color}) {
//   String displayValue = '';

//   if (value == null || value == '') {
//     displayValue = 'Not specified';
//   } else if (value is List) {
//     displayValue = value.isEmpty ? 'None' : value.join(', ');
//   } else if (value is Map) {
//     displayValue = '${value.length} items';
//   } else {
//     displayValue = value.toString();
//   }

//   return Padding(
//     padding: const EdgeInsets.symmetric(vertical: 4),
//     child: Row(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         SizedBox(
//           width: 120,
//           child: Text(
//             '$label:',
//             style: TextStyle(
//               color: Colors.white70,
//               fontSize: 12,
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//         ),
//         SizedBox(width: 8),
//         Expanded(
//           child: Text(
//             displayValue,
//             style: TextStyle(color: color ?? Colors.white, fontSize: 12),
//           ),
//         ),
//       ],
//     ),
//   );
// }

// Widget _buildChecklistSection(String title, List<Widget> children) {
//   return Container(
//     margin: const EdgeInsets.only(top: 12),
//     padding: const EdgeInsets.all(12),
//     decoration: BoxDecoration(
//       color: Colors.blue.withOpacity(0.1),
//       borderRadius: BorderRadius.circular(8),
//       border: Border.all(color: Colors.blue.withOpacity(0.3)),
//     ),
//     child: Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           children: [
//             Icon(Icons.checklist, size: 16, color: Colors.blueAccent),
//             SizedBox(width: 8),
//             Text(
//               title,
//               style: TextStyle(
//                 color: Colors.blueAccent,
//                 fontSize: 14,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//           ],
//         ),
//         SizedBox(height: 8),
//         ...children,
//       ],
//     ),
//   );
// }

// List<Widget> _buildChecklistWidgets(Map<String, dynamic> checklistData) {
//   final List<Widget> widgets = [];

//   // Metadata section
//   if (checklistData['metadata'] != null) {
//     final metadata = checklistData['metadata'] as Map<String, dynamic>;
//     widgets.addAll([
//       _buildChecklistSection('Checklist Information', [
//         _buildChecklistItem('Form Type', metadata['formType']),
//         _buildChecklistItem('Hospital', metadata['hospitalName']),
//         _buildChecklistItem('Completed By', metadata['completedBy']),
//         _buildChecklistItem(
//           'Collection Date',
//           metadata['collectedAt']?.toString().split('T')[0],
//         ),
//       ]),
//     ]);
//   }

//   // Patient Info
//   if (checklistData['patientInfo'] != null) {
//     final patientInfo = checklistData['patientInfo'] as Map<String, dynamic>;
//     widgets.addAll([
//       _buildChecklistSection('Patient Information', [
//         _buildChecklistItem('Patient Name', patientInfo['patientName']),
//         _buildChecklistItem('MRD Number', patientInfo['mrdNumber']),
//         _buildChecklistItem('Age', patientInfo['age']),
//         _buildChecklistItem('Gender', patientInfo['gender']),
//         _buildChecklistItem('Phone', patientInfo['phone']),
//         _buildChecklistItem('Lab Name', patientInfo['labName']),
//         _buildChecklistItem('Physician', patientInfo['physician']),
//         _buildChecklistItem('Physician Date', patientInfo['physicianDate']),
//       ]),
//     ]);
//   }

//   // Medical History
//   if (checklistData['medicalHistory'] != null) {
//     final medicalHistory =
//         checklistData['medicalHistory'] as Map<String, dynamic>;
//     widgets.addAll([
//       _buildChecklistSection('Medical History', [
//         _buildChecklistItem('Diabetic', medicalHistory['diabetic']),
//         _buildChecklistItem('Diabetic Since', medicalHistory['diabeticSince']),
//         _buildChecklistItem('Insulin', medicalHistory['insulin']),
//         _buildChecklistItem('Cardiac Issues', medicalHistory['cardiac']),
//         _buildChecklistItem('Angioplasty', medicalHistory['angioplasty']),
//         _buildChecklistItem('Bypass Surgery', medicalHistory['bypass']),
//         _buildChecklistItem('Blood Thinners', medicalHistory['bloodThinner']),
//         _buildChecklistItem('Kidney Issues', medicalHistory['kidney']),
//         _buildChecklistItem('Dialysis', medicalHistory['dialysis']),
//         _buildChecklistItem('Other', medicalHistory['other']),
//       ]),
//     ]);
//   }

//   // Blood Tests
//   if (checklistData['bloodTests'] != null) {
//     final bloodTests = checklistData['bloodTests'] as Map<String, dynamic>;
//     final bloodTestWidgets = <Widget>[
//       _buildChecklistItem('Hemoglobin', bloodTests['hemoglobin']),
//       _buildChecklistItem('ESR', bloodTests['esr']),
//       _buildChecklistItem('CRP', bloodTests['crp']),
//       _buildChecklistItem('Platelet', bloodTests['platelet']),
//       _buildChecklistItem('TLC', bloodTests['tlc']),
//     ];

//     // DLC (Differential Count)
//     if (bloodTests['dlc'] != null) {
//       final dlc = bloodTests['dlc'] as Map<String, dynamic>;
//       bloodTestWidgets.addAll([
//         SizedBox(height: 8),
//         Text(
//           'Differential Count:',
//           style: TextStyle(color: Colors.white70, fontSize: 12),
//         ),
//         _buildChecklistItem('  Neutrophil', dlc['neutrophil']),
//         _buildChecklistItem('  Lymphocyte', dlc['lymphocyte']),
//         _buildChecklistItem('  Eosinophil', dlc['eosinophil']),
//         _buildChecklistItem('  Monocyte', dlc['monocyte']),
//         _buildChecklistItem('  Basophil', dlc['basophil']),
//       ]);
//     }

//     // Blood Sugar
//     if (bloodTests['bloodSugar'] != null) {
//       final bloodSugar = bloodTests['bloodSugar'] as Map<String, dynamic>;
//       bloodTestWidgets.addAll([
//         SizedBox(height: 8),
//         Text(
//           'Blood Sugar:',
//           style: TextStyle(color: Colors.white70, fontSize: 12),
//         ),
//         _buildChecklistItem('  FBS', bloodSugar['fbs']),
//         _buildChecklistItem('  PPBS', bloodSugar['ppbs']),
//         _buildChecklistItem('  RBS', bloodSugar['rbs']),
//         _buildChecklistItem('  HbA1c', bloodSugar['hba1c']),
//       ]);
//     }

//     // Biochemistry
//     if (bloodTests['biochemistry'] != null) {
//       final biochemistry = bloodTests['biochemistry'] as Map<String, dynamic>;
//       bloodTestWidgets.addAll([
//         SizedBox(height: 8),
//         Text(
//           'Biochemistry:',
//           style: TextStyle(color: Colors.white70, fontSize: 12),
//         ),
//         _buildChecklistItem('  Creatinine', biochemistry['creatinine']),
//         _buildChecklistItem('  BUN', biochemistry['bun']),
//         _buildChecklistItem('  Sodium', biochemistry['sodium']),
//         _buildChecklistItem('  Potassium', biochemistry['potassium']),
//         _buildChecklistItem('  Chloride', biochemistry['chloride']),
//       ]);
//     }

//     widgets.add(_buildChecklistSection('Blood Tests', bloodTestWidgets));
//   }

//   // Urine Tests
//   if (checklistData['urineTests'] != null) {
//     final urineTests = checklistData['urineTests'] as Map<String, dynamic>;
//     widgets.addAll([
//       _buildChecklistSection('Urine Tests', [
//         _buildChecklistItem('Protein', urineTests['protein']),
//         _buildChecklistItem('Glucose', urineTests['glucose']),
//         _buildChecklistItem('Ketone', urineTests['ketone']),
//         _buildChecklistItem('Blood', urineTests['blood']),
//         _buildChecklistItem('Pus Cells', urineTests['pusCells']),
//         _buildChecklistItem('Epithelial Cells', urineTests['epithelialCells']),
//         _buildChecklistItem('Bacteria', urineTests['bacteria']),
//         _buildChecklistItem('Cast', urineTests['cast']),
//       ]),
//     ]);
//   }

//   // Infective Profile
//   if (checklistData['infectiveProfile'] != null) {
//     final infectiveProfile =
//         checklistData['infectiveProfile'] as Map<String, dynamic>;
//     widgets.addAll([
//       _buildChecklistSection('Infective Profile', [
//         _buildChecklistItem('HBsAg', infectiveProfile['hbsag']),
//         _buildChecklistItem('HIV', infectiveProfile['hiv']),
//         _buildChecklistItem('HCV', infectiveProfile['hcv']),
//         _buildChecklistItem('HBV', infectiveProfile['hbv']),
//       ]),
//     ]);
//   }

//   // Verification
//   if (checklistData['verification'] != null) {
//     final verification = checklistData['verification'] as Map<String, dynamic>;
//     widgets.addAll([
//       _buildChecklistSection('Verification', [
//         _buildChecklistItem('Nurse Verified', verification['nurseVerified']),
//         _buildChecklistItem('Nurse Time', verification['nurseTime']),
//         _buildChecklistItem('Doctor Verified', verification['doctorVerified']),
//         _buildChecklistItem('Doctor Time', verification['doctorTime']),
//       ]),
//     ]);
//   }

//   return widgets;
// }

// // ==================== MAIN VIDEO SWITCHER SCREEN ====================

// class VideoSwitcherScreen extends StatefulWidget {
//   const VideoSwitcherScreen({super.key});

//   @override
//   State<VideoSwitcherScreen> createState() => _VideoSwitcherScreenState();
// }

// class _VideoSwitcherScreenState extends State<VideoSwitcherScreen> {
//   final String baseUrl = 'http://192.168.0.43:5000';
//   late VideoSwitcherProvider _provider;
//   String otNumber = ""; // OT number variable

//   // Demo patients list - 10 patients
//   final List<Patient> _demoPatients = [
//     Patient(
//       patientId: 'MRD001',
//       name: 'Rajesh Sharma',
//       age: 45,
//       gender: 'Male',
//       phone: '+91 98765 43210',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '09:00',
//       operationDoctor: 'Dr. Patel',
//       bloodGroup: 'B+',
//       email: 'rajesh.sharma@email.com',
//       address: '123 Main Street, Mumbai',
//       allergies: 'None',
//       medications: 'None',
//     ),
//     Patient(
//       patientId: 'MRD002',
//       name: 'Priya Mehta',
//       age: 32,
//       gender: 'Female',
//       phone: '+91 98765 43211',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '10:30',
//       operationDoctor: 'Dr. Kumar',
//       bloodGroup: 'A+',
//       email: 'priya.mehta@email.com',
//       address: '456 Park Avenue, Mumbai',
//       allergies: 'Penicillin',
//       medications: 'None',
//     ),
//     Patient(
//       patientId: 'MRD003',
//       name: 'Amit Singh',
//       age: 58,
//       gender: 'Male',
//       phone: '+91 98765 43212',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '12:00',
//       operationDoctor: 'Dr. Patel',
//       bloodGroup: 'O+',
//       email: 'amit.singh@email.com',
//       address: '789 Lake View, Mumbai',
//       allergies: 'None',
//       medications: 'Blood pressure medicine',
//     ),
//     Patient(
//       patientId: 'MRD004',
//       name: 'Sunita Reddy',
//       age: 28,
//       gender: 'Female',
//       phone: '+91 98765 43213',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '13:30',
//       operationDoctor: 'Dr. Sharma',
//       bloodGroup: 'AB+',
//       email: 'sunita.reddy@email.com',
//       address: '321 Hill Road, Mumbai',
//       allergies: 'None',
//       medications: 'None',
//     ),
//     Patient(
//       patientId: 'MRD005',
//       name: 'Vikram Joshi',
//       age: 52,
//       gender: 'Male',
//       phone: '+91 98765 43214',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '15:00',
//       operationDoctor: 'Dr. Kumar',
//       bloodGroup: 'B-',
//       email: 'vikram.joshi@email.com',
//       address: '654 Beach Road, Mumbai',
//       allergies: 'Sulfa drugs',
//       medications: 'Diabetes medication',
//     ),
//     Patient(
//       patientId: 'MRD006',
//       name: 'Neha Gupta',
//       age: 41,
//       gender: 'Female',
//       phone: '+91 98765 43215',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '16:30',
//       operationDoctor: 'Dr. Patel',
//       bloodGroup: 'O-',
//       email: 'neha.gupta@email.com',
//       address: '987 Garden Street, Mumbai',
//       allergies: 'None',
//       medications: 'None',
//     ),
//     Patient(
//       patientId: 'MRD007',
//       name: 'Ramesh Kumar',
//       age: 65,
//       gender: 'Male',
//       phone: '+91 98765 43216',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '18:00',
//       operationDoctor: 'Dr. Sharma',
//       bloodGroup: 'A-',
//       email: 'ramesh.kumar@email.com',
//       address: '147 Temple Road, Mumbai',
//       allergies: 'Aspirin',
//       medications: 'Heart medication',
//     ),
//     Patient(
//       patientId: 'MRD008',
//       name: 'Kavita Nair',
//       age: 35,
//       gender: 'Female',
//       phone: '+91 98765 43217',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '19:30',
//       operationDoctor: 'Dr. Kumar',
//       bloodGroup: 'AB-',
//       email: 'kavita.nair@email.com',
//       address: '258 Lake Road, Mumbai',
//       allergies: 'None',
//       medications: 'None',
//     ),
//     Patient(
//       patientId: 'MRD009',
//       name: 'Suresh Menon',
//       age: 47,
//       gender: 'Male',
//       phone: '+91 98765 43218',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '21:00',
//       operationDoctor: 'Dr. Patel',
//       bloodGroup: 'B+',
//       email: 'suresh.menon@email.com',
//       address: '369 Hill View, Mumbai',
//       allergies: 'None',
//       medications: 'Cholesterol medicine',
//     ),
//     Patient(
//       patientId: 'MRD010',
//       name: 'Anjali Desai',
//       age: 29,
//       gender: 'Female',
//       phone: '+91 98765 43219',
//       operationOt: 'OT-01',
//       operationDate: _getTodayDate(),
//       operationTime: '22:30',
//       operationDoctor: 'Dr. Sharma',
//       bloodGroup: 'O+',
//       email: 'anjali.desai@email.com',
//       address: '741 Park Street, Mumbai',
//       allergies: 'None',
//       medications: 'None',
//     ),
//   ];

//   // Asset video list
//   final List<Map<String, dynamic>> _assetVideos = [
//     {
//       'name': 'Surgery Video 1',
//       'path': 'assets/surgery1.mp4',
//       'controller': null,
//     },
//     {
//       'name': 'Surgery Video 2',
//       'path': 'assets/surgery2.mp4',
//       'controller': null,
//     },
//     {
//       'name': 'Surgery Video 3',
//       'path': 'assets/surgery3.mp4',
//       'controller': null,
//     },
//     {
//       'name': 'Surgery Video 4',
//       'path': 'assets/surgery4.mp4',
//       'controller': null,
//     },
//   ];

//   // Track selected video index
//   int _selectedVideoIndex = 0;

//   // Video player controller
//   VideoPlayerController? _videoController;
//   ChewieController? _chewieController;
//   bool _isVideoInitialized = false;

//   @override
//   void initState() {
//     super.initState();
//     _provider = Provider.of<VideoSwitcherProvider>(context, listen: false);
//     _initializeApp();
//     _initializeVideoPlayer(0); // Initialize first video
//   }

//   Future<void> _initializeVideoPlayer(int index) async {
//     try {
//       // Dispose old controllers
//       _videoController?.dispose();
//       _chewieController?.dispose();

//       // Get video path
//       final videoPath = _assetVideos[index]['path'];

//       // Create and initialize video controller
//       _videoController = VideoPlayerController.asset(videoPath);
//       await _videoController!.initialize();

//       // Mute the video - NO AUDIO
//       await _videoController!.setVolume(0.0);

//       // Create chewie controller without audio controls
//       _chewieController = ChewieController(
//         videoPlayerController: _videoController!,
//         autoPlay: true,
//         looping: true,
//         aspectRatio: _videoController!.value.aspectRatio,
//         allowFullScreen: true,
//         allowMuting: false, // Disable mute button
//         allowPlaybackSpeedChanging: true,
//         autoInitialize: true,
//         deviceOrientationsAfterFullScreen: [
//           DeviceOrientation.landscapeRight,
//           DeviceOrientation.landscapeLeft,
//         ],
//         materialProgressColors: ChewieProgressColors(
//           playedColor: Colors.red,
//           handleColor: Colors.red,
//           backgroundColor: Colors.grey,
//           bufferedColor: Colors.grey.withOpacity(0.5),
//         ),
//         placeholder: Container(
//           color: Colors.black,
//           child: const Center(
//             child: CircularProgressIndicator(color: Colors.red),
//           ),
//         ),
//         errorBuilder: (context, errorMessage) {
//           return Center(
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Icon(Icons.error_outline, color: Colors.red, size: 50),
//                 SizedBox(height: 10),
//                 Text(
//                   "Error playing video",
//                   style: TextStyle(color: Colors.white, fontSize: 16),
//                 ),
//                 SizedBox(height: 5),
//                 Text(
//                   errorMessage,
//                   style: TextStyle(color: Colors.white70),
//                   textAlign: TextAlign.center,
//                 ),
//               ],
//             ),
//           );
//         },
//       );

//       setState(() {
//         _isVideoInitialized = true;
//         _selectedVideoIndex = index;
//       });
//     } catch (e) {
//       print("=== DEBUG: Error initializing video player: $e ===");
//       setState(() {
//         _isVideoInitialized = false;
//       });

//       Fluttertoast.showToast(
//         msg: "Error loading video: ${_assetVideos[index]['name']}",
//         gravity: ToastGravity.BOTTOM,
//         backgroundColor: Colors.red,
//       );
//     }
//   }

//   @override
//   void dispose() {
//     _videoController?.dispose();
//     _chewieController?.dispose();
//     super.dispose();
//   }

//   Future<void> _initializeApp() async {
//     try {
//       print("=== DEBUG: Starting app initialization ===");

//       // Load OT number first
//       await lodeotno();
//       print("=== DEBUG: OT Number loaded: $otNumber ===");

//       await _loadUSBPath(_provider);
//       print("=== DEBUG: USB Path loaded: ${_provider.usbPath} ===");

//       await _requestPermissions();
//       print("=== DEBUG: Permissions requested ===");

//       await _loadPatients(_provider);
//       print("=== DEBUG: Patients loaded: ${_provider.patientsList.length} ===");

//       print("=== DEBUG: App initialization complete ===");
//     } catch (e) {
//       print("=== DEBUG: Error during initialization: $e ===");
//     }
//   }

//   Future<void> lodeotno() async {
//     final prefs = await SharedPreferences.getInstance();
//     otNumber = prefs.getString('otNumber') ?? "OT-01";
//     print("=== DEBUG: Loaded OT Number from SharedPreferences: $otNumber ===");
//   }

//   Future<void> _loadUSBPath(VideoSwitcherProvider provider) async {
//     try {
//       print("=== DEBUG: Loading USB path from SharedPreferences ===");
//       final prefs = await SharedPreferences.getInstance();
//       final savedPath = prefs.getString("usbPath");

//       if (savedPath != null && savedPath.isNotEmpty) {
//         print("=== DEBUG: Found saved path: $savedPath ===");

//         final directory = Directory(savedPath);
//         if (await directory.exists()) {
//           provider.setUsbPath(savedPath);
//           provider.setUsbConnected(true);
//           print("=== DEBUG: USB path loaded successfully ===");
//         } else {
//           print("=== DEBUG: Saved directory doesn't exist ===");
//           try {
//             await directory.create(recursive: true);
//             provider.setUsbPath(savedPath);
//             provider.setUsbConnected(true);
//             print("=== DEBUG: Directory created successfully ===");
//           } catch (e) {
//             print("=== DEBUG: Failed to create directory: $e ===");
//             await prefs.remove("usbPath");
//             provider.setUsbPath(null);
//             provider.setUsbConnected(false);
//           }
//         }
//       } else {
//         print("=== DEBUG: No saved USB path found ===");
//         provider.setUsbPath(null);
//         provider.setUsbConnected(false);
//       }
//     } catch (e) {
//       print("=== DEBUG: Error loading USB path: $e ===");
//       provider.setUsbPath(null);
//       provider.setUsbConnected(false);
//     }
//   }

//   Future<void> _loadPatients(VideoSwitcherProvider provider) async {
//     final ApiService apiServdice = ApiService();
//     provider.setIsLoadingPatients(true);
//     provider.setPatientError('');

//     try {
//       await _checkServerStatus(provider);

//       final todayDate = _getTodayDate();

//       print("=== DEBUG: Loading patients for today: $todayDate ===");
//       print("=== DEBUG: Filtering by OT: $otNumber ===");

//       if (provider.serverOnline) {
//         print("=== DEBUG: Server is online, trying to fetch real data ===");

//         try {
//           print("=== DEBUG: Attempting API call ===");
//           final datePatients = await apiServdice.getPatientsByDate(todayDate);

//           // Filter patients by OT number
//           List<Patient> filteredPatients = datePatients.where((patient) {
//             final patientOt = patient.operationOt ?? '';
//             final matchesOt = patientOt == otNumber;
//             return matchesOt;
//           }).toList();

//           if (filteredPatients.isNotEmpty) {
//             filteredPatients.sort((a, b) {
//               final timeA = a.operationTime ?? '';
//               final timeB = b.operationTime ?? '';
//               return timeA.compareTo(timeB);
//             });
//             provider.setPatientsList(filteredPatients);
//             print(
//               "=== DEBUG: Loaded ${filteredPatients.length} patients from API ===",
//             );
//           } else {
//             print("=== DEBUG: No patients from API, using demo data ===");
//             _useDemoPatients(provider);
//           }
//         } catch (apiError) {
//           print("=== DEBUG: API error: $apiError, using demo data ===");
//           _useDemoPatients(provider);
//         }
//       } else {
//         print("=== DEBUG: Server offline, using demo patients ===");
//         _useDemoPatients(provider);
//         provider.setPatientError('Server offline - Showing demo patients');
//       }

//       provider.setIsLoadingPatients(false);
//     } catch (e) {
//       print("=== DEBUG: Error in _loadPatients: $e ===");
//       print("=== DEBUG: Using demo patients as fallback ===");
//       _useDemoPatients(provider);
//       provider.setPatientError('Error loading patients - Showing demo data');
//       provider.setIsLoadingPatients(false);
//     }
//   }

//   void _useDemoPatients(VideoSwitcherProvider provider) {
//     final filteredPatients = _demoPatients.where((patient) {
//       return patient.operationOt == otNumber;
//     }).toList();

//     filteredPatients.sort((a, b) {
//       final timeA = a.operationTime ?? '';
//       final timeB = b.operationTime ?? '';
//       return timeA.compareTo(timeB);
//     });

//     provider.setPatientsList(filteredPatients);
//     print("=== DEBUG: Loaded ${filteredPatients.length} demo patients ===");
//   }

//   Future<void> _checkServerStatus(VideoSwitcherProvider provider) async {
//     final ApiService apiService = ApiService();
//     final isOnline = await apiService.checkServerStatus();
//     provider.setServerOnline(isOnline);
//   }

//   // HDMI Source Selection Popup
//   void _showHdmiPadPopup(BuildContext context) {
//     showDialog(
//       context: context,
//       barrierDismissible: true,
//       barrierColor: Colors.black.withOpacity(0.5), // Blur background effect
//       builder: (BuildContext context) {
//         return Dialog(
//           backgroundColor: Colors.transparent,
//           insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
//           child: BackdropFilter(
//             filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
//             child: Container(
//               decoration: BoxDecoration(
//                 color: Color(0xFF2C105A).withOpacity(0.95),
//                 borderRadius: BorderRadius.circular(20),
//                 border: Border.all(
//                   color: Colors.white.withOpacity(0.3),
//                   width: 1,
//                 ),
//               ),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   // Header
//                   Container(
//                     padding: EdgeInsets.all(16),
//                     decoration: BoxDecoration(
//                       color: Colors.blueAccent.withOpacity(0.2),
//                       borderRadius: BorderRadius.only(
//                         topLeft: Radius.circular(20),
//                         topRight: Radius.circular(20),
//                       ),
//                     ),
//                     child: Row(
//                       children: [
//                         Icon(Icons.hd, color: Colors.white, size: 28),
//                         SizedBox(width: 12),
//                         Text(
//                           'Select HDMI Source',
//                           style: TextStyle(
//                             color: Colors.white,
//                             fontSize: 20,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),

//                   // HDMI Options
//                   Padding(
//                     padding: EdgeInsets.all(16),
//                     child: Column(
//                       children: [
//                         _buildHdmiOption(
//                           icon: Icons.hd,
//                           title: 'HDMI 1',
//                           subtitle: 'Primary Source',
//                           color: Colors.blue,
//                           onTap: () {
//                             Navigator.pop(context);
//                             _showSourcePadPopup(context, 'HDMI 1');
//                           },
//                         ),
//                         SizedBox(height: 12),
//                         _buildHdmiOption(
//                           icon: Icons.hd,
//                           title: 'HDMI 2',
//                           subtitle: 'Secondary Source',
//                           color: Colors.green,
//                           onTap: () {
//                             Navigator.pop(context);
//                             _showSourcePadPopup(context, 'HDMI 2');
//                           },
//                         ),
//                       ],
//                     ),
//                   ),

//                   // Close Button
//                   Padding(
//                     padding: EdgeInsets.only(bottom: 16),
//                     child: TextButton(
//                       onPressed: () => Navigator.pop(context),
//                       child: Text(
//                         'Close',
//                         style: TextStyle(color: Colors.white70, fontSize: 16),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }

//   void _showSourcePadPopup(BuildContext context, String hdmiSource) {
//     showDialog(
//       context: context,
//       barrierDismissible: true,
//       barrierColor: Colors.black.withOpacity(0.5), // Blur background effect
//       builder: (BuildContext context) {
//         return Dialog(
//           backgroundColor: Colors.transparent,
//           insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
//           child: BackdropFilter(
//             filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
//             child: Container(
//               decoration: BoxDecoration(
//                 color: Color(0xFF2C105A).withOpacity(0.95),
//                 borderRadius: BorderRadius.circular(20),
//                 border: Border.all(
//                   color: Colors.white.withOpacity(0.3),
//                   width: 1,
//                 ),
//               ),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   // Header
//                   Container(
//                     padding: EdgeInsets.all(16),
//                     decoration: BoxDecoration(
//                       color: Colors.purpleAccent.withOpacity(0.2),
//                       borderRadius: BorderRadius.only(
//                         topLeft: Radius.circular(20),
//                         topRight: Radius.circular(20),
//                       ),
//                     ),
//                     child: Row(
//                       children: [
//                         Icon(Icons.source, color: Colors.white, size: 28),
//                         SizedBox(width: 12),
//                         Expanded(
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Text(
//                                 'Select Source',
//                                 style: TextStyle(
//                                   color: Colors.white,
//                                   fontSize: 18,
//                                   fontWeight: FontWeight.bold,
//                                 ),
//                               ),
//                               Text(
//                                 'for $hdmiSource',
//                                 style: TextStyle(
//                                   color: Colors.white70,
//                                   fontSize: 14,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),

//                   // Source Options
//                   Padding(
//                     padding: EdgeInsets.all(16),
//                     child: Column(
//                       children: [
//                         _buildSourceOption(
//                           icon: Icons.videocam,
//                           title: 'Source 1',
//                           subtitle: 'Camera Feed',
//                           color: Colors.red,
//                           onTap: () {
//                             Navigator.pop(context);
//                             _switchSource(hdmiSource, 'Source 1');
//                           },
//                         ),
//                         SizedBox(height: 12),
//                         _buildSourceOption(
//                           icon: Icons.computer,
//                           title: 'Source 2',
//                           subtitle: 'Endoscopy',
//                           color: Colors.orange,
//                           onTap: () {
//                             Navigator.pop(context);
//                             _switchSource(hdmiSource, 'Source 2');
//                           },
//                         ),
//                         SizedBox(height: 12),
//                         _buildSourceOption(
//                           icon: Icons.monitor,
//                           title: 'Source 3',
//                           subtitle: 'Ultrasound',
//                           color: Colors.green,
//                           onTap: () {
//                             Navigator.pop(context);
//                             _switchSource(hdmiSource, 'Source 3');
//                           },
//                         ),
//                         SizedBox(height: 12),
//                         _buildSourceOption(
//                           icon: Icons.laptop,
//                           title: 'Source 4',
//                           subtitle: 'External Device',
//                           color: Colors.blue,
//                           onTap: () {
//                             Navigator.pop(context);
//                             _switchSource(hdmiSource, 'Source 4');
//                           },
//                         ),
//                       ],
//                     ),
//                   ),

//                   // Close Button
//                   Padding(
//                     padding: EdgeInsets.only(bottom: 16),
//                     child: TextButton(
//                       onPressed: () => Navigator.pop(context),
//                       child: Text(
//                         'Close',
//                         style: TextStyle(color: Colors.white70, fontSize: 16),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildHdmiOption({
//     required IconData icon,
//     required String title,
//     required String subtitle,
//     required Color color,
//     required VoidCallback onTap,
//   }) {
//     return InkWell(
//       onTap: onTap,
//       child: Container(
//         padding: EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           gradient: LinearGradient(
//             colors: [color.withOpacity(0.2), color.withOpacity(0.1)],
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//           ),
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(color: color.withOpacity(0.5), width: 1),
//         ),
//         child: Row(
//           children: [
//             Container(
//               padding: EdgeInsets.all(10),
//               decoration: BoxDecoration(
//                 color: color.withOpacity(0.3),
//                 borderRadius: BorderRadius.circular(10),
//               ),
//               child: Icon(icon, color: color, size: 28),
//             ),
//             SizedBox(width: 16),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     title,
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   Text(
//                     subtitle,
//                     style: TextStyle(color: Colors.white70, fontSize: 12),
//                   ),
//                 ],
//               ),
//             ),
//             Icon(Icons.arrow_forward_ios, color: color, size: 16),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildSourceOption({
//     required IconData icon,
//     required String title,
//     required String subtitle,
//     required Color color,
//     required VoidCallback onTap,
//   }) {
//     return InkWell(
//       onTap: onTap,
//       child: Container(
//         padding: EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           gradient: LinearGradient(
//             colors: [color.withOpacity(0.2), color.withOpacity(0.1)],
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//           ),
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(color: color.withOpacity(0.5), width: 1),
//         ),
//         child: Row(
//           children: [
//             Container(
//               padding: EdgeInsets.all(10),
//               decoration: BoxDecoration(
//                 color: color.withOpacity(0.3),
//                 borderRadius: BorderRadius.circular(10),
//               ),
//               child: Icon(icon, color: color, size: 24),
//             ),
//             SizedBox(width: 16),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     title,
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 16,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   Text(
//                     subtitle,
//                     style: TextStyle(color: Colors.white70, fontSize: 11),
//                   ),
//                 ],
//               ),
//             ),
//             Icon(Icons.switch_access_shortcut, color: color, size: 16),
//           ],
//         ),
//       ),
//     );
//   }

//   void _switchSource(String hdmiSource, String source) {
//     Fluttertoast.showToast(
//       msg: "Switched to $hdmiSource - $source",
//       gravity: ToastGravity.BOTTOM,
//       backgroundColor: Colors.green,
//     );
//     // Add your source switching logic here
//     print("=== DEBUG: Switched to $hdmiSource - $source ===");
//   }

//   Widget _buildPatientCard(BuildContext context, Patient patient, int index) {
//     // Check if patient has checklist
//     bool hasChecklist = patient.hasChecklist;

//     String timeStatus = '';
//     Color timeColor = Colors.white70;
//     if (patient.operationTime != null) {
//       final now = DateTime.now();
//       final timeParts = patient.operationTime!.split(':');
//       if (timeParts.length >= 2) {
//         final hour = int.tryParse(timeParts[0]) ?? 0;
//         final minute = int.tryParse(timeParts[1]) ?? 0;
//         final patientTime = DateTime(
//           now.year,
//           now.month,
//           now.day,
//           hour,
//           minute,
//         );

//         if (patientTime.isBefore(now.subtract(Duration(minutes: 30)))) {
//           timeStatus = 'Completed';
//           timeColor = Colors.green;
//         } else if (patientTime.isBefore(now)) {
//           timeStatus = 'In Progress';
//           timeColor = Colors.orange;
//         } else if (patientTime.isBefore(now.add(Duration(minutes: 30)))) {
//           timeStatus = 'Upcoming';
//           timeColor = Colors.blue;
//         } else {
//           timeStatus = 'Scheduled';
//           timeColor = Colors.white70;
//         }
//       }
//     }

//     return Card(
//       margin: const EdgeInsets.only(bottom: 8),
//       color: Colors.white.withOpacity(0.1),
//       child: InkWell(
//         onTap: () => _showPatientDetails(context, patient),
//         borderRadius: BorderRadius.circular(8),
//         child: Padding(
//           padding: const EdgeInsets.all(12),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Expanded(
//                     child: Row(
//                       children: [
//                         Text(
//                           patient.name,
//                           style: const TextStyle(
//                             color: Colors.white,
//                             fontWeight: FontWeight.bold,
//                             fontSize: 16,
//                           ),
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                         SizedBox(width: 6),
//                         // Checklist indicator
//                         if (hasChecklist)
//                           Container(
//                             padding: EdgeInsets.all(2),
//                             decoration: BoxDecoration(
//                               color: Colors.green,
//                               shape: BoxShape.circle,
//                             ),
//                             child: Icon(
//                               Icons.check,
//                               size: 10,
//                               color: Colors.white,
//                             ),
//                           ),
//                       ],
//                     ),
//                   ),
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 8,
//                       vertical: 4,
//                     ),
//                     decoration: BoxDecoration(
//                       color: timeColor.withOpacity(0.2),
//                       borderRadius: BorderRadius.circular(4),
//                       border: Border.all(color: timeColor, width: 1),
//                     ),
//                     child: Text(
//                       timeStatus,
//                       style: TextStyle(
//                         color: timeColor,
//                         fontSize: 11,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 6),
//               Row(
//                 children: [
//                   Icon(Icons.person_outline, size: 14, color: Colors.white70),
//                   const SizedBox(width: 6),
//                   Text(
//                     "MRD: ${patient.patientId}",
//                     style: const TextStyle(color: Colors.white70, fontSize: 12),
//                   ),
//                   const Spacer(),
//                   // Show OT number
//                   if (patient.operationOt != null)
//                     Container(
//                       padding: const EdgeInsets.symmetric(
//                         horizontal: 6,
//                         vertical: 2,
//                       ),
//                       decoration: BoxDecoration(
//                         color: patient.operationOt == otNumber
//                             ? Colors.green.withOpacity(0.2)
//                             : Colors.blue.withOpacity(0.2),
//                         borderRadius: BorderRadius.circular(4),
//                         border: Border.all(
//                           color: patient.operationOt == otNumber
//                               ? Colors.green
//                               : Colors.blue,
//                         ),
//                       ),
//                       child: Text(
//                         patient.operationOt!,
//                         style: TextStyle(
//                           color: patient.operationOt == otNumber
//                               ? Colors.green
//                               : Colors.blueAccent,
//                           fontSize: 10,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                 ],
//               ),
//               const SizedBox(height: 4),
//               // Show current OT indicator
//               if (patient.operationOt == otNumber)
//                 Container(
//                   margin: EdgeInsets.only(bottom: 4),
//                   padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                   decoration: BoxDecoration(
//                     color: Colors.green.withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(4),
//                   ),
//                   child: Row(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       Icon(Icons.meeting_room, size: 10, color: Colors.green),
//                       SizedBox(width: 4),
//                       Text(
//                         'Current OT',
//                         style: TextStyle(
//                           color: Colors.green,
//                           fontSize: 10,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               const SizedBox(height: 4),
//               Row(
//                 children: [
//                   Icon(Icons.calendar_today, size: 14, color: Colors.white70),
//                   const SizedBox(width: 6),
//                   Text(
//                     "${patient.age} years, ${patient.gender}",
//                     style: const TextStyle(color: Colors.white70, fontSize: 12),
//                   ),
//                   const Spacer(),
//                   if (patient.operationTime != null)
//                     Row(
//                       children: [
//                         Icon(Icons.access_time, size: 14, color: Colors.yellow),
//                         const SizedBox(width: 4),
//                         Text(
//                           patient.operationTime!,
//                           style: const TextStyle(
//                             color: Colors.yellow,
//                             fontSize: 12,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ],
//                     ),
//                 ],
//               ),
//               const SizedBox(height: 4),
//               Row(
//                 children: [
//                   Icon(Icons.phone, size: 14, color: Colors.white70),
//                   const SizedBox(width: 6),
//                   Expanded(
//                     child: Text(
//                       patient.phone,
//                       style: const TextStyle(
//                         color: Colors.white70,
//                         fontSize: 12,
//                       ),
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                   ),
//                 ],
//               ),
//               if (patient.operationDoctor != null) ...[
//                 const SizedBox(height: 4),
//                 Row(
//                   children: [
//                     Icon(
//                       Icons.medical_services,
//                       size: 14,
//                       color: Colors.white70,
//                     ),
//                     const SizedBox(width: 6),
//                     Expanded(
//                       child: Text(
//                         "Dr. ${patient.operationDoctor}",
//                         style: const TextStyle(
//                           color: Colors.white70,
//                           fontSize: 12,
//                         ),
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//               if (patient.reportCount != null && patient.reportCount! > 0) ...[
//                 const SizedBox(height: 4),
//                 Row(
//                   children: [
//                     Icon(Icons.folder, size: 14, color: Colors.blueAccent),
//                     const SizedBox(width: 6),
//                     Text(
//                       "${patient.reportCount} reports",
//                       style: const TextStyle(
//                         color: Colors.blueAccent,
//                         fontSize: 12,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//               // Show checklist type if available
//               if (hasChecklist && patient.checklistType != null) ...[
//                 const SizedBox(height: 4),
//                 Row(
//                   children: [
//                     Icon(Icons.checklist, size: 14, color: Colors.green),
//                     const SizedBox(width: 6),
//                     Text(
//                       patient.checklistType!,
//                       style: const TextStyle(
//                         color: Colors.green,
//                         fontSize: 11,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   void _showPatientDetails(BuildContext context, Patient patient) {
//     // Check if patient has checklist
//     bool hasChecklist = patient.hasChecklist;
//     String checklistType = patient.checklistType ?? 'No Checklist';
//     String? hospitalName = patient.checklistHospital;

//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         backgroundColor: const Color(0xFF3D8A8F),
//         title: Row(
//           children: [
//             CircleAvatar(
//               backgroundColor: Colors.white,
//               child: Text(
//                 patient.name[0].toUpperCase(),
//                 style: const TextStyle(color: Color(0xFF3D8A8F)),
//               ),
//             ),
//             const SizedBox(width: 12),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     patient.name,
//                     style: const TextStyle(
//                       color: Colors.white,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   if (patient.operationOt != null)
//                     Text(
//                       "OT: ${patient.operationOt}",
//                       style: const TextStyle(
//                         color: Colors.white70,
//                         fontSize: 12,
//                       ),
//                     ),
//                   // Show current OT indicator
//                   if (patient.operationOt == otNumber)
//                     Container(
//                       margin: EdgeInsets.only(top: 4),
//                       padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                       decoration: BoxDecoration(
//                         color: Colors.green.withOpacity(0.2),
//                         borderRadius: BorderRadius.circular(4),
//                         border: Border.all(color: Colors.green),
//                       ),
//                       child: Row(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Icon(
//                             Icons.meeting_room,
//                             size: 10,
//                             color: Colors.green,
//                           ),
//                           SizedBox(width: 4),
//                           Text(
//                             'Current OT',
//                             style: TextStyle(
//                               color: Colors.green,
//                               fontSize: 10,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   // Show checklist indicator
//                   if (hasChecklist)
//                     Container(
//                       margin: EdgeInsets.only(top: 4),
//                       padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                       decoration: BoxDecoration(
//                         color: Colors.green.withOpacity(0.2),
//                         borderRadius: BorderRadius.circular(4),
//                         border: Border.all(color: Colors.green),
//                       ),
//                       child: Row(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Icon(Icons.checklist, size: 10, color: Colors.green),
//                           SizedBox(width: 4),
//                           Text(
//                             'Medical Checklist Available',
//                             style: TextStyle(
//                               color: Colors.green,
//                               fontSize: 10,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//         content: SingleChildScrollView(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               _buildDetailRow("Patient MRD:", patient.patientId),
//               _buildDetailRow("Name:", patient.name),
//               _buildDetailRow("Age:", "${patient.age} years"),
//               _buildDetailRow("Gender:", patient.gender),
//               _buildDetailRow("Phone:", patient.phone),
//               if (patient.email != null)
//                 _buildDetailRow("Email:", patient.email!),
//               if (patient.bloodGroup != null)
//                 _buildDetailRow("Blood Group:", patient.bloodGroup!),
//               if (patient.address != null)
//                 _buildDetailRow("Address:", patient.address!),
//               if (patient.operationOt != null)
//                 _buildDetailRow("OT Number:", patient.operationOt!),
//               if (patient.operationDoctor != null)
//                 _buildDetailRow("Doctor:", patient.operationDoctor!),
//               if (patient.operationDate != null)
//                 _buildDetailRow("Operation Date:", patient.operationDate!),
//               if (patient.operationTime != null)
//                 _buildDetailRow("Operation Time:", patient.operationTime!),

//               // Eye Information
//               if (patient.eye != null || patient.eyeCondition != null)
//                 Container(
//                   margin: EdgeInsets.only(top: 8),
//                   padding: EdgeInsets.all(8),
//                   decoration: BoxDecoration(
//                     color: Colors.blue.withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         'Eye Information:',
//                         style: TextStyle(
//                           color: Colors.blueAccent,
//                           fontSize: 14,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       if (patient.eye != null)
//                         _buildDetailRow("  Eye:", patient.eye!),
//                       if (patient.eyeCondition != null)
//                         _buildDetailRow("  Condition:", patient.eyeCondition!),
//                       if (patient.eyeSurgery != null)
//                         _buildDetailRow("  Surgery:", patient.eyeSurgery!),
//                       if (patient.visionLeft != null)
//                         _buildDetailRow("  Vision Left:", patient.visionLeft!),
//                       if (patient.visionRight != null)
//                         _buildDetailRow(
//                           "  Vision Right:",
//                           patient.visionRight!,
//                         ),
//                     ],
//                   ),
//                 ),

//               if (patient.reportCount != null)
//                 _buildDetailRow(
//                   "Medical Reports:",
//                   "${patient.reportCount} files",
//                   color: Colors.green,
//                 ),

//               // Checklist summary
//               if (hasChecklist)
//                 Container(
//                   margin: EdgeInsets.only(top: 12),
//                   padding: EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: Colors.green.withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(8),
//                     border: Border.all(color: Colors.green.withOpacity(0.3)),
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         children: [
//                           Icon(
//                             Icons.medical_services,
//                             size: 16,
//                             color: Colors.green,
//                           ),
//                           SizedBox(width: 8),
//                           Text(
//                             'Medical Checklist',
//                             style: TextStyle(
//                               color: Colors.green,
//                               fontSize: 14,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                         ],
//                       ),
//                       SizedBox(height: 6),
//                       _buildDetailRow("Type:", checklistType),
//                       if (hospitalName != null && hospitalName.isNotEmpty)
//                         _buildDetailRow("Hospital:", hospitalName),
//                       SizedBox(height: 8),
//                       ElevatedButton(
//                         onPressed: () {
//                           Navigator.pop(context); // Close current dialog
//                           _showChecklistDetails(context, patient);
//                         },
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: Colors.green,
//                           foregroundColor: Colors.white,
//                           minimumSize: Size(double.infinity, 36),
//                         ),
//                         child: Text('View Complete Checklist'),
//                       ),
//                     ],
//                   ),
//                 ),
//             ],
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text("Close", style: TextStyle(color: Colors.white)),
//           ),
//           ElevatedButton(
//             onPressed: () {
//               Navigator.pop(context);
//               _navigateToFullPatientDetails(context, patient);
//             },
//             style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
//             child: const Text("View Full Details"),
//           ),
//           if (hasChecklist)
//             ElevatedButton.icon(
//               onPressed: () {
//                 Navigator.pop(context);
//                 _showChecklistDetails(context, patient);
//               },
//               icon: Icon(Icons.checklist, size: 18),
//               label: Text("Checklist"),
//               style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDetailRow(String label, String value, {Color? color}) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           SizedBox(
//             width: 100,
//             child: Text(
//               label,
//               style: const TextStyle(
//                 fontWeight: FontWeight.w600,
//                 color: Colors.white70,
//                 fontSize: 14,
//               ),
//             ),
//           ),
//           const SizedBox(width: 10),
//           Expanded(
//             child: Text(
//               value,
//               style: TextStyle(
//                 fontSize: 14,
//                 color: color ?? Colors.white,
//                 fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   void _showChecklistDetails(BuildContext context, Patient patient) {
//     if (patient.checklist == null || patient.formattedChecklist == null) {
//       Fluttertoast.showToast(
//         msg: "No checklist data available",
//         gravity: ToastGravity.BOTTOM,
//       );
//       return;
//     }

//     final checklistData = patient.formattedChecklist!;

//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         backgroundColor: const Color(0xFF3D8A8F),
//         title: Row(
//           children: [
//             Icon(Icons.medical_services, color: Colors.white),
//             SizedBox(width: 8),
//             Text(
//               'Medical Checklist',
//               style: TextStyle(color: Colors.white, fontSize: 18),
//             ),
//           ],
//         ),
//         content: SingleChildScrollView(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisSize: MainAxisSize.min,
//             children: _buildChecklistWidgets(checklistData),
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: Text('Close', style: TextStyle(color: Colors.white)),
//           ),
//         ],
//       ),
//     );
//   }

//   void _navigateToFullPatientDetails(BuildContext context, Patient patient) {
//     // Check if patient has checklist
//     bool hasChecklist = patient.hasChecklist;

//     showDialog(
//       context: context,
//       builder: (context) => Dialog(
//         backgroundColor: const Color(0xFF3D8A8F),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         child: SingleChildScrollView(
//           child: Padding(
//             padding: const EdgeInsets.all(20),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Center(
//                   child: Column(
//                     children: [
//                       CircleAvatar(
//                         radius: 40,
//                         backgroundColor: Colors.white,
//                         child: Text(
//                           patient.name[0].toUpperCase(),
//                           style: const TextStyle(
//                             fontSize: 32,
//                             fontWeight: FontWeight.bold,
//                             color: Color(0xFF3D8A8F),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                       if (patient.operationOt != null)
//                         Container(
//                           padding: const EdgeInsets.symmetric(
//                             horizontal: 12,
//                             vertical: 4,
//                           ),
//                           decoration: BoxDecoration(
//                             color: Colors.blue.withOpacity(0.2),
//                             borderRadius: BorderRadius.circular(20),
//                             border: Border.all(color: Colors.blue),
//                           ),
//                           child: Text(
//                             "OT: ${patient.operationOt}",
//                             style: const TextStyle(
//                               color: Colors.blueAccent,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                         ),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 20),
//                 Center(
//                   child: Text(
//                     patient.name,
//                     style: const TextStyle(
//                       fontSize: 24,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.white,
//                     ),
//                   ),
//                 ),
//                 Center(
//                   child: Text(
//                     "MRD: ${patient.patientId}",
//                     style: const TextStyle(color: Colors.white70, fontSize: 14),
//                   ),
//                 ),
//                 const SizedBox(height: 20),
//                 const Divider(color: Colors.white38),
//                 const SizedBox(height: 10),

//                 if (patient.operationDate != null ||
//                     patient.operationTime != null)
//                   Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       const Text(
//                         "Operation Schedule",
//                         style: TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.bold,
//                           color: Colors.white,
//                         ),
//                       ),
//                       const SizedBox(height: 10),
//                       if (patient.operationDate != null)
//                         _buildFullDetailRow("Date", patient.operationDate!),
//                       if (patient.operationTime != null)
//                         _buildFullDetailRow("Time", patient.operationTime!),
//                       if (patient.operationOt != null)
//                         _buildFullDetailRow("OT Room", patient.operationOt!),
//                       if (patient.operationDoctor != null)
//                         _buildFullDetailRow("Doctor", patient.operationDoctor!),
//                       const SizedBox(height: 20),
//                       const Divider(color: Colors.white38),
//                     ],
//                   ),

//                 const Text(
//                   "Personal Information",
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.white,
//                   ),
//                 ),
//                 const SizedBox(height: 10),
//                 _buildFullDetailRow("Age", "${patient.age} years"),
//                 _buildFullDetailRow("Gender", patient.gender),
//                 _buildFullDetailRow("Phone", patient.phone),
//                 if (patient.email != null)
//                   _buildFullDetailRow("Email", patient.email!),
//                 if (patient.bloodGroup != null)
//                   _buildFullDetailRow("Blood Group", patient.bloodGroup!),
//                 if (patient.address != null)
//                   _buildFullDetailRow("Address", patient.address!),

//                 // Eye Information
//                 if (patient.eye != null || patient.eyeCondition != null) ...[
//                   const SizedBox(height: 20),
//                   const Divider(color: Colors.white38),
//                   const SizedBox(height: 10),
//                   const Text(
//                     "Eye Information",
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.white,
//                     ),
//                   ),
//                   const SizedBox(height: 10),
//                   if (patient.eye != null)
//                     _buildFullDetailRow("Eye", patient.eye!),
//                   if (patient.eyeCondition != null)
//                     _buildFullDetailRow("Condition", patient.eyeCondition!),
//                   if (patient.eyeSurgery != null)
//                     _buildFullDetailRow("Surgery History", patient.eyeSurgery!),
//                   if (patient.visionLeft != null)
//                     _buildFullDetailRow("Vision (Left)", patient.visionLeft!),
//                   if (patient.visionRight != null)
//                     _buildFullDetailRow("Vision (Right)", patient.visionRight!),
//                 ],

//                 if (patient.allergies != null ||
//                     patient.medications != null) ...[
//                   const SizedBox(height: 20),
//                   const Divider(color: Colors.white38),
//                   const SizedBox(height: 10),
//                   const Text(
//                     "Medical Information",
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.white,
//                     ),
//                   ),
//                   const SizedBox(height: 10),
//                   if (patient.allergies != null)
//                     _buildFullDetailRow("Allergies", patient.allergies!),
//                   if (patient.medications != null)
//                     _buildFullDetailRow("Medications", patient.medications!),
//                 ],

//                 // Checklist section
//                 if (hasChecklist) ...[
//                   const SizedBox(height: 20),
//                   const Divider(color: Colors.white38),
//                   const SizedBox(height: 10),
//                   const Text(
//                     "Medical Checklist",
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.white,
//                     ),
//                   ),
//                   const SizedBox(height: 10),
//                   Container(
//                     padding: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(
//                       color: Colors.green.withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(8),
//                       border: Border.all(color: Colors.green),
//                     ),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Row(
//                           children: [
//                             Icon(Icons.checklist, color: Colors.green),
//                             SizedBox(width: 8),
//                             Text(
//                               patient.checklistType ?? 'Medical Checklist',
//                               style: TextStyle(
//                                 color: Colors.green,
//                                 fontSize: 16,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                           ],
//                         ),
//                         SizedBox(height: 8),
//                         if (patient.checklistHospital != null)
//                           Text(
//                             'Hospital: ${patient.checklistHospital}',
//                             style: TextStyle(color: Colors.white70),
//                           ),
//                         SizedBox(height: 12),
//                         ElevatedButton(
//                           onPressed: () =>
//                               _showChecklistDetails(context, patient),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Colors.green,
//                             minimumSize: Size(double.infinity, 40),
//                           ),
//                           child: Row(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               Icon(Icons.visibility, size: 18),
//                               SizedBox(width: 8),
//                               Text('View Complete Checklist'),
//                             ],
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],

//                 const SizedBox(height: 20),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                   children: [
//                     ElevatedButton(
//                       onPressed: () => Navigator.pop(context),
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.orange,
//                       ),
//                       child: const Text("Edit"),
//                     ),
//                     ElevatedButton(
//                       onPressed: () {
//                         Navigator.pop(context);
//                         _viewMedicalReports(context, patient);
//                       },
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.green,
//                       ),
//                       child: const Text("Medical Reports"),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Future<void> _viewMedicalReports(
//     BuildContext context,
//     Patient patient,
//   ) async {
//     final provider = Provider.of<VideoSwitcherProvider>(context, listen: false);

//     try {
//       provider.setIsLoadingPatients(true);
//       final ApiService apiService = ApiService();
//       final reports = await apiService.getReports(patient.patientId);

//       if (reports.isEmpty) {
//         Fluttertoast.showToast(
//           msg: "No medical reports available for ${patient.name}",
//           gravity: ToastGravity.BOTTOM,
//         );
//         provider.setIsLoadingPatients(false);
//         return;
//       }

//       showDialog(
//         context: context,
//         builder: (context) => AlertDialog(
//           backgroundColor: const Color(0xFF3D8A8F),
//           title: Text(
//             "Medical Reports - ${patient.name}",
//             style: const TextStyle(color: Colors.white),
//           ),
//           content: SizedBox(
//             width: double.maxFinite,
//             child: ListView.builder(
//               shrinkWrap: true,
//               itemCount: reports.length,
//               itemBuilder: (context, index) {
//                 final report = reports[index];
//                 return ListTile(
//                   leading: const Icon(Icons.description, color: Colors.white),
//                   title: Text(
//                     report.originalName,
//                     style: const TextStyle(color: Colors.white),
//                   ),
//                   subtitle: Text(
//                     "${report.fileType.split('/').last.toUpperCase()} • ${_formatBytes(report.fileSize)}",
//                     style: const TextStyle(color: Colors.white70),
//                   ),
//                   trailing: IconButton(
//                     icon: const Icon(Icons.download, color: Colors.green),
//                     onPressed: () =>
//                         _downloadAndOpenReport(context, patient, report),
//                   ),
//                 );
//               },
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(context),
//               child: const Text("Close", style: TextStyle(color: Colors.white)),
//             ),
//           ],
//         ),
//       );
//     } catch (e) {
//       Fluttertoast.showToast(
//         msg: "Error loading reports: $e",
//         gravity: ToastGravity.BOTTOM,
//       );
//     } finally {
//       provider.setIsLoadingPatients(false);
//     }
//   }

//   Future<void> _downloadAndOpenReport(
//     BuildContext context,
//     Patient patient,
//     Report report,
//   ) async {
//     final ApiService apiService = ApiService();
//     try {
//       Fluttertoast.showToast(
//         msg: "Downloading ${report.originalName}...",
//         gravity: ToastGravity.BOTTOM,
//       );

//       final bytes = await apiService.downloadReport(
//         patient.patientId,
//         report.id,
//       );

//       final directory = await getTemporaryDirectory();
//       final filePath = '${directory.path}/${report.originalName}';
//       final file = File(filePath);
//       await file.writeAsBytes(bytes);

//       final isPdf = report.fileType.toLowerCase().contains('pdf');
//       final isImage =
//           report.fileType.toLowerCase().contains('jpg') ||
//           report.fileType.toLowerCase().contains('jpeg') ||
//           report.fileType.toLowerCase().contains('png');

//       if (isPdf || isImage) {
//         // You'll need to add your FileViewerScreen here
//       } else {
//         final result = await OpenFilex.open(filePath);
//         if (result.type != ResultType.done) {
//           Fluttertoast.showToast(
//             msg: "Failed to open file: ${result.message}",
//             gravity: ToastGravity.BOTTOM,
//             backgroundColor: Colors.red,
//           );
//         }
//       }
//     } catch (e) {
//       Fluttertoast.showToast(
//         msg: "Error downloading report: $e",
//         gravity: ToastGravity.BOTTOM,
//         backgroundColor: Colors.red,
//       );
//     }
//   }

//   Widget _buildFullDetailRow(String label, String value) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 8),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             label,
//             style: const TextStyle(color: Colors.white70, fontSize: 14),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             value,
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 16,
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildFullScreenView(BuildContext context) {
//     final provider = Provider.of<VideoSwitcherProvider>(context);

//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         children: [
//           // Full screen video player
//           Center(
//             child: _isVideoInitialized && _chewieController != null
//                 ? Chewie(controller: _chewieController!)
//                 : const Center(
//                     child: CircularProgressIndicator(color: Colors.red),
//                   ),
//           ),

//           if (provider.isRecording)
//             Positioned(
//               top: 15,
//               left: 15,
//               child: Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 12,
//                   vertical: 6,
//                 ),
//                 decoration: BoxDecoration(
//                   color: Colors.black87,
//                   borderRadius: BorderRadius.circular(4),
//                 ),
//                 child: Row(
//                   children: [
//                     const Icon(Icons.circle, color: Colors.red, size: 12),
//                     const SizedBox(width: 8),
//                     Text(
//                       "${_getDuration(provider.recordingStartTime)} | ${_formatBytes(provider.bytesDownloaded)}",
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//           Positioned(
//             top: 40,
//             right: 20,
//             child: Container(
//               decoration: BoxDecoration(
//                 color: Colors.black54,
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: IconButton(
//                 icon: const Icon(
//                   Icons.fullscreen_exit,
//                   color: Colors.white,
//                   size: 30,
//                 ),
//                 onPressed: () => provider.toggleFullScreen(),
//               ),
//             ),
//           ),

//           Positioned(
//             top: 40,
//             left: provider.isRecording ? 180 : 20,
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//               decoration: BoxDecoration(
//                 color: Colors.black54,
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: Text(
//                 _assetVideos[_selectedVideoIndex]['name'],
//                 style: const TextStyle(
//                   color: Colors.white,
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//             ),
//           ),

//           Positioned(
//             bottom: 20,
//             left: 0,
//             right: 0,
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   _buildFullScreenControlBtn(
//                     Icons.videocam,
//                     provider.isRecording ? "Stop" : "Record",
//                     onPressed: () => () {},
//                   ),
//                   const SizedBox(width: 16),
//                   _buildFullScreenControlBtn(
//                     Icons.camera_alt,
//                     "Screenshot",
//                     onPressed: () => _takeScreenshot(context),
//                   ),
//                   const SizedBox(width: 16),
//                   _buildFullScreenControlBtn(
//                     Icons.fullscreen_exit,
//                     "Exit Full",
//                     onPressed: () => provider.toggleFullScreen(),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildFullScreenControlBtn(
//     IconData icon,
//     String label, {
//     VoidCallback? onPressed,
//   }) {
//     return Consumer<VideoSwitcherProvider>(
//       builder: (context, provider, child) {
//         bool hasFolder = provider.usbPath != null && provider.usbConnected;

//         return Column(
//           children: [
//             Stack(
//               children: [
//                 Container(
//                   decoration: BoxDecoration(
//                     color: Colors.black54,
//                     shape: BoxShape.circle,
//                   ),
//                   child: IconButton(
//                     icon: Icon(icon, color: Colors.white, size: 24),
//                     onPressed: onPressed,
//                   ),
//                 ),
//                 if (label.contains("Record") && hasFolder)
//                   Positioned(
//                     top: 2,
//                     right: 2,
//                     child: Container(
//                       padding: const EdgeInsets.all(2),
//                       decoration: BoxDecoration(
//                         color: Colors.green,
//                         shape: BoxShape.circle,
//                         border: Border.all(color: Colors.black, width: 1),
//                       ),
//                       child: const Icon(
//                         Icons.check,
//                         size: 10,
//                         color: Colors.white,
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//             const SizedBox(height: 4),
//             Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Text(
//                   label,
//                   style: const TextStyle(color: Colors.white, fontSize: 12),
//                 ),
//                 if (label.contains("Record") && hasFolder)
//                   const Icon(Icons.check, size: 10, color: Colors.green),
//               ],
//             ),
//           ],
//         );
//       },
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Consumer<VideoSwitcherProvider>(
//       builder: (context, provider, child) {
//         if (provider.isFullScreen) {
//           return _buildFullScreenView(context);
//         }

//         return Scaffold(
//           body: Row(
//             children: [
//               // Left Panel (Surgery Videos List)
//               Expanded(
//                 flex: 1,
//                 child: Container(
//                   decoration: const BoxDecoration(
//                     gradient: LinearGradient(
//                       colors: [
//                         Color.fromARGB(255, 44, 16, 90),
//                         Color.fromARGB(255, 68, 49, 127),
//                       ],
//                       begin: Alignment.topLeft,
//                       end: Alignment.bottomRight,
//                     ),
//                   ),
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.start,
//                     children: [
//                       const SizedBox(height: 25),
//                       Expanded(
//                         flex: 1,
//                         child: Container(
//                           decoration: const BoxDecoration(
//                             gradient: LinearGradient(
//                               colors: [
//                                 Color.fromARGB(255, 44, 16, 90),
//                                 Color.fromARGB(255, 68, 49, 127),
//                               ],
//                               begin: Alignment.topCenter,
//                               end: Alignment.bottomCenter,
//                             ),
//                           ),
//                           child: Column(
//                             children: [
//                               const SizedBox(height: 16),
//                               const Text(
//                                 "Surgery Videos",
//                                 style: TextStyle(
//                                   fontSize: 20,
//                                   fontWeight: FontWeight.bold,
//                                   color: Colors.white,
//                                 ),
//                               ),
//                               const Divider(color: Colors.white38),
//                               const SizedBox(height: 12),
//                               Expanded(
//                                 child: ListView(
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: 12,
//                                   ),
//                                   children: List.generate(_assetVideos.length, (
//                                     index,
//                                   ) {
//                                     return _buildVideoItem(context, index);
//                                   }),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                       Padding(
//                         padding: const EdgeInsets.only(bottom: 16.0),
//                         child: ElevatedButton(
//                           onPressed: () => Navigator.pop(context),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Colors.red,
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(10),
//                             ),
//                             padding: const EdgeInsets.symmetric(
//                               horizontal: 40,
//                               vertical: 12,
//                             ),
//                           ),
//                           child: const Text(
//                             "BACK",
//                             style: TextStyle(
//                               color: Colors.white70,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),

//               // Center Panel (Main Video Player)
//               Expanded(
//                 flex: 3,
//                 child: Container(
//                   decoration: const BoxDecoration(
//                     gradient: LinearGradient(
//                       colors: [
//                         Color.fromARGB(255, 44, 16, 90),
//                         Color.fromARGB(255, 68, 49, 127),
//                       ],
//                       begin: Alignment.topCenter,
//                       end: Alignment.bottomCenter,
//                     ),
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.center,
//                     children: [
//                       const SizedBox(height: 10),
//                       const Text(
//                         "Akola",
//                         style: TextStyle(
//                           fontWeight: FontWeight.bold,
//                           fontSize: 26,
//                           color: Colors.white,
//                         ),
//                       ),
//                       const SizedBox(height: 6),

//                       // HDMI Button
//                       Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 16),
//                         child: Row(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           children: [
//                             ElevatedButton.icon(
//                               onPressed: () => _showHdmiPadPopup(context),
//                               icon: Icon(Icons.hd, color: Colors.white),
//                               label: Text(
//                                 'Select HDMI Source',
//                                 style: TextStyle(
//                                   color: Colors.white,
//                                   fontWeight: FontWeight.bold,
//                                 ),
//                               ),
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: Colors.purple,
//                                 padding: EdgeInsets.symmetric(
//                                   horizontal: 20,
//                                   vertical: 12,
//                                 ),
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(30),
//                                 ),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),

//                       if (provider.isRecording || provider.isConverting)
//                         Container(
//                           padding: const EdgeInsets.all(8),
//                           color: Colors.black.withOpacity(0.5),
//                           child: Row(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               if (provider.isRecording) ...[
//                                 const Icon(
//                                   Icons.circle,
//                                   color: Colors.red,
//                                   size: 12,
//                                 ),
//                                 const SizedBox(width: 8),
//                                 Text(
//                                   "RECORDING - ${_getDuration(provider.recordingStartTime)} | ${_formatBytes(provider.bytesDownloaded)}",
//                                   style: const TextStyle(
//                                     color: Colors.white,
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                                 ),
//                               ] else if (provider.isConverting) ...[
//                                 const CircularProgressIndicator(
//                                   color: Colors.red,
//                                   strokeWidth: 2,
//                                 ),
//                                 const SizedBox(width: 8),
//                                 Text(
//                                   "Converting MJPEG to MP4: ${provider.conversionProgress.toStringAsFixed(1)}s",
//                                   style: const TextStyle(color: Colors.white),
//                                 ),
//                               ],
//                             ],
//                           ),
//                         ),

//                       Expanded(
//                         child: Stack(
//                           children: [
//                             Padding(
//                               padding: const EdgeInsets.all(8.0),
//                               child: _buildVideoPlayer(context),
//                             ),
//                             if (provider.isRecording)
//                               Positioned(
//                                 top: 15,
//                                 left: 15,
//                                 child: Container(
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: 12,
//                                     vertical: 6,
//                                   ),
//                                   decoration: BoxDecoration(
//                                     color: Colors.black87,
//                                     borderRadius: BorderRadius.circular(4),
//                                   ),
//                                   child: Row(
//                                     children: [
//                                       const Icon(
//                                         Icons.circle,
//                                         color: Colors.red,
//                                         size: 12,
//                                       ),
//                                       const SizedBox(width: 8),
//                                       Text(
//                                         "${_getDuration(provider.recordingStartTime)} | ${_formatBytes(provider.bytesDownloaded)}",
//                                         style: const TextStyle(
//                                           color: Colors.white,
//                                           fontWeight: FontWeight.bold,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               ),
//                           ],
//                         ),
//                       ),

//                       Padding(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 8,
//                           vertical: 8,
//                         ),
//                         child: Column(
//                           children: [
//                             if (provider.isConverting)
//                               Column(
//                                 children: [
//                                   const LinearProgressIndicator(
//                                     color: Colors.red,
//                                   ),
//                                   const SizedBox(height: 8),
//                                   Text(
//                                     "Converting MJPEG to MP4: ${provider.conversionProgress.toStringAsFixed(1)}s",
//                                     style: const TextStyle(color: Colors.white),
//                                   ),
//                                   const SizedBox(height: 8),
//                                 ],
//                               ),
//                             Wrap(
//                               alignment: WrapAlignment.center,
//                               spacing: 8,
//                               runSpacing: 8,
//                               children: [
//                                 buildControlBtn(
//                                   provider.isRecording
//                                       ? "Stop Recording"
//                                       : "Record",
//                                   onPressed: () => () {},
//                                   icon: provider.isRecording
//                                       ? Icons.stop
//                                       : Icons.videocam,
//                                   color: provider.isRecording
//                                       ? Colors.red
//                                       : null,
//                                 ),
//                                 buildControlBtn(
//                                   "Take SS",
//                                   icon: Icons.camera_alt,
//                                   // onPressed: () => _takeScreenshot(context),
//                                   onPressed: () {
//                                     Navigator.push(
//                                       context,
//                                       MaterialPageRoute(
//                                         builder: (context) =>
//                                             DraggableGridScreen(),
//                                       ),
//                                     );
//                                   },
//                                 ),
//                               ],
//                             ),
//                             const SizedBox(height: 8),
//                           ],
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),

//               // Right Panel (Patients List)
//               Expanded(
//                 flex: 1,
//                 child: Container(
//                   decoration: const BoxDecoration(
//                     gradient: LinearGradient(
//                       colors: [
//                         Color.fromARGB(255, 44, 16, 90),
//                         Color.fromARGB(255, 68, 49, 127),
//                       ],
//                       begin: Alignment.topCenter,
//                       end: Alignment.bottomCenter,
//                     ),
//                   ),
//                   child: Column(
//                     children: [
//                       const SizedBox(height: 16),
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Padding(
//                             padding: const EdgeInsets.only(top: 24.0, left: 16),
//                             child: const Text(
//                               "Today's Patients",
//                               style: TextStyle(
//                                 fontSize: 22,
//                                 fontWeight: FontWeight.bold,
//                                 color: Colors.white,
//                               ),
//                             ),
//                           ),
//                           Row(
//                             children: [
//                               Tooltip(
//                                 message: provider.serverOnline
//                                     ? 'Server Online'
//                                     : 'Server Offline (Showing Demo Data)',
//                                 child: Icon(
//                                   provider.serverOnline
//                                       ? Icons.cloud_done
//                                       : Icons.cloud_off,
//                                   color: provider.serverOnline
//                                       ? Colors.greenAccent
//                                       : Colors.orangeAccent,
//                                   size: 20,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ],
//                       ),
//                       const Divider(color: Colors.white38),
//                       const SizedBox(height: 8),

//                       Container(
//                         width: double.infinity,
//                         padding: const EdgeInsets.all(8),
//                         margin: const EdgeInsets.symmetric(horizontal: 12),
//                         decoration: BoxDecoration(
//                           color: Colors.blue.withOpacity(0.1),
//                           borderRadius: BorderRadius.circular(8),
//                           border: Border.all(
//                             color: Colors.blue.withOpacity(0.3),
//                           ),
//                         ),
//                         child: Row(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           children: [
//                             Icon(
//                               Icons.meeting_room,
//                               size: 14,
//                               color: Colors.blueAccent,
//                             ),
//                             const SizedBox(width: 6),
//                             Text(
//                               otNumber,
//                               style: const TextStyle(
//                                 color: Colors.blueAccent,
//                                 fontSize: 14,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                             const SizedBox(width: 6),
//                             Icon(
//                               Icons.calendar_today,
//                               size: 14,
//                               color: Colors.blueAccent,
//                             ),
//                             const SizedBox(width: 6),
//                             Text(
//                               _getTodayDate(),
//                               style: const TextStyle(
//                                 color: Colors.blueAccent,
//                                 fontSize: 12,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),

//                       Padding(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 12,
//                           vertical: 8,
//                         ),
//                         child: Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             Text(
//                               "OT: $otNumber",
//                               style: const TextStyle(
//                                 color: Colors.white,
//                                 fontSize: 14,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                             IconButton(
//                               onPressed: () => _refreshPatients(provider),
//                               icon: const Icon(
//                                 Icons.refresh,
//                                 color: Colors.white,
//                                 size: 20,
//                               ),
//                               tooltip: "Refresh demo patients",
//                             ),
//                           ],
//                         ),
//                       ),

//                       Padding(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 12,
//                           vertical: 8,
//                         ),
//                         child: Row(
//                           children: [
//                             Expanded(
//                               child: Container(
//                                 height: 40,
//                                 decoration: BoxDecoration(
//                                   color: Colors.white.withOpacity(0.1),
//                                   borderRadius: BorderRadius.circular(8),
//                                 ),
//                                 child: const Row(
//                                   children: [
//                                     Padding(
//                                       padding: EdgeInsets.symmetric(
//                                         horizontal: 12,
//                                       ),
//                                       child: Icon(
//                                         Icons.search,
//                                         color: Colors.white70,
//                                       ),
//                                     ),
//                                     Expanded(
//                                       child: TextField(
//                                         style: TextStyle(color: Colors.white),
//                                         decoration: InputDecoration(
//                                           hintText: "Search patients...",
//                                           hintStyle: TextStyle(
//                                             color: Colors.white70,
//                                           ),
//                                           border: InputBorder.none,
//                                         ),
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),

//                       if (provider.patientError.isNotEmpty)
//                         Container(
//                           width: double.infinity,
//                           padding: const EdgeInsets.all(8),
//                           margin: const EdgeInsets.symmetric(
//                             horizontal: 12,
//                             vertical: 4,
//                           ),
//                           decoration: BoxDecoration(
//                             color: Colors.orange.withOpacity(0.2),
//                             borderRadius: BorderRadius.circular(4),
//                             border: Border.all(color: Colors.orange),
//                           ),
//                           child: Text(
//                             provider.patientError,
//                             style: const TextStyle(
//                               color: Colors.orange,
//                               fontSize: 11,
//                             ),
//                             textAlign: TextAlign.center,
//                           ),
//                         ),

//                       const SizedBox(height: 4),

//                       Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 12),
//                         child: Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             Text(
//                               "Total: ${provider.patientsList.length} patients",
//                               style: const TextStyle(
//                                 color: Colors.white70,
//                                 fontSize: 12,
//                               ),
//                             ),
//                             Text(
//                               "Sorted by Time",
//                               style: const TextStyle(
//                                 color: Colors.white70,
//                                 fontSize: 10,
//                                 fontStyle: FontStyle.italic,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),

//                       const SizedBox(height: 8),

//                       Expanded(
//                         child: provider.isLoadingPatients
//                             ? const Center(
//                                 child: Column(
//                                   mainAxisAlignment: MainAxisAlignment.center,
//                                   children: [
//                                     CircularProgressIndicator(
//                                       color: Colors.white,
//                                     ),
//                                     SizedBox(height: 16),
//                                     Text(
//                                       "Loading patients...",
//                                       style: TextStyle(color: Colors.white70),
//                                     ),
//                                   ],
//                                 ),
//                               )
//                             : provider.patientsList.isEmpty
//                             ? Center(
//                                 child: Column(
//                                   mainAxisAlignment: MainAxisAlignment.center,
//                                   children: [
//                                     const Icon(
//                                       Icons.people_outline,
//                                       color: Colors.white70,
//                                       size: 50,
//                                     ),
//                                     const SizedBox(height: 16),
//                                     Text(
//                                       "No patients scheduled",
//                                       style: const TextStyle(
//                                         color: Colors.white70,
//                                         fontSize: 16,
//                                       ),
//                                     ),
//                                     const SizedBox(height: 4),
//                                     Text(
//                                       "for OT $otNumber today",
//                                       style: const TextStyle(
//                                         color: Colors.white60,
//                                         fontSize: 12,
//                                       ),
//                                     ),
//                                     const SizedBox(height: 8),
//                                     Text(
//                                       _getTodayDate(),
//                                       style: const TextStyle(
//                                         color: Colors.white60,
//                                         fontSize: 12,
//                                       ),
//                                     ),
//                                     const SizedBox(height: 16),
//                                     ElevatedButton(
//                                       onPressed: () =>
//                                           _refreshPatients(provider),
//                                       style: ElevatedButton.styleFrom(
//                                         backgroundColor: Colors.blueAccent,
//                                       ),
//                                       child: const Text("Refresh"),
//                                     ),
//                                   ],
//                                 ),
//                               )
//                             : ListView.builder(
//                                 padding: const EdgeInsets.symmetric(
//                                   horizontal: 12,
//                                 ),
//                                 itemCount: provider.patientsList.length,
//                                 itemBuilder: (context, index) {
//                                   return _buildPatientCard(
//                                     context,
//                                     provider.patientsList[index],
//                                     index,
//                                   );
//                                 },
//                               ),
//                       ),

//                       Padding(
//                         padding: const EdgeInsets.all(12),
//                         child: ElevatedButton.icon(
//                           onPressed: () => _showAddPatientDialog(context),
//                           icon: const Icon(Icons.person_add, size: 18),
//                           label: const Text("Add New Patient"),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Colors.green,
//                             foregroundColor: Colors.white,
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(8),
//                             ),
//                             minimumSize: const Size(double.infinity, 45),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }

//   // New method to build video item in left panel
//   Widget _buildVideoItem(BuildContext context, int index) {
//     final isSelected = _selectedVideoIndex == index;
//     final video = _assetVideos[index];

//     return InkWell(
//       onTap: () {
//         _initializeVideoPlayer(index);
//       },
//       child: Container(
//         margin: const EdgeInsets.only(bottom: 8),
//         padding: const EdgeInsets.all(12),
//         decoration: BoxDecoration(
//           color: isSelected ? Colors.blue.withOpacity(0.3) : Colors.transparent,
//           borderRadius: BorderRadius.circular(8),
//           border: Border.all(
//             color: isSelected ? Colors.blue : Colors.white24,
//             width: isSelected ? 2 : 1,
//           ),
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Icon(
//                   Icons.videocam,
//                   color: isSelected ? Colors.lightGreenAccent : Colors.white70,
//                   size: 24,
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: Text(
//                     video['name'],
//                     style: TextStyle(
//                       color: isSelected
//                           ? Colors.lightGreenAccent
//                           : Colors.white,
//                       fontWeight: isSelected
//                           ? FontWeight.bold
//                           : FontWeight.normal,
//                       fontSize: 16,
//                     ),
//                   ),
//                 ),
//                 if (isSelected)
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 6,
//                       vertical: 2,
//                     ),
//                     decoration: BoxDecoration(
//                       color: Colors.green,
//                       borderRadius: BorderRadius.circular(4),
//                     ),
//                     child: const Text(
//                       "PLAYING",
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontSize: 10,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//             const SizedBox(height: 8),
//             LinearProgressIndicator(
//               value:
//                   isSelected &&
//                       _videoController != null &&
//                       _videoController!.value.isPlaying
//                   ? _videoController!.value.position.inMilliseconds /
//                         _videoController!.value.duration.inMilliseconds
//                   : 0,
//               backgroundColor: Colors.white24,
//               valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // New method to build video player in center
//   Widget _buildVideoPlayer(BuildContext context) {
//     if (!_isVideoInitialized || _chewieController == null) {
//       return Container(
//         color: Colors.black,
//         child: const Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               CircularProgressIndicator(color: Colors.red),
//               SizedBox(height: 20),
//               Text("Loading video...", style: TextStyle(color: Colors.white70)),
//             ],
//           ),
//         ),
//       );
//     }

//     return ClipRRect(
//       borderRadius: BorderRadius.circular(8),
//       child: Chewie(controller: _chewieController!),
//     );
//   }

//   void _showAddPatientDialog(BuildContext context) {
//     final provider = Provider.of<VideoSwitcherProvider>(context, listen: false);
//     final nameController = TextEditingController();
//     final ageController = TextEditingController();
//     final genderController = TextEditingController();
//     final phoneController = TextEditingController();
//     final otController = TextEditingController(
//       text: otNumber,
//     ); // Default to current OT
//     final dateController = TextEditingController(text: _getTodayDate());
//     final timeController = TextEditingController();

//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         backgroundColor: const Color(0xFF3D8A8F),
//         title: const Text(
//           'Add New Patient',
//           style: TextStyle(color: Colors.white),
//         ),
//         content: SingleChildScrollView(
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               TextField(
//                 controller: nameController,
//                 style: const TextStyle(color: Colors.white),
//                 decoration: const InputDecoration(
//                   labelText: 'Full Name*',
//                   labelStyle: TextStyle(color: Colors.white70),
//                   border: OutlineInputBorder(),
//                   enabledBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white70),
//                   ),
//                   focusedBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 10),
//               TextField(
//                 controller: ageController,
//                 style: const TextStyle(color: Colors.white),
//                 decoration: const InputDecoration(
//                   labelText: 'Age*',
//                   labelStyle: TextStyle(color: Colors.white70),
//                   border: OutlineInputBorder(),
//                   enabledBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white70),
//                   ),
//                   focusedBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white),
//                   ),
//                 ),
//                 keyboardType: TextInputType.number,
//               ),
//               const SizedBox(height: 10),
//               TextField(
//                 controller: genderController,
//                 style: const TextStyle(color: Colors.white),
//                 decoration: const InputDecoration(
//                   labelText: 'Gender*',
//                   labelStyle: TextStyle(color: Colors.white70),
//                   border: OutlineInputBorder(),
//                   enabledBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white70),
//                   ),
//                   focusedBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 10),
//               TextField(
//                 controller: phoneController,
//                 style: const TextStyle(color: Colors.white),
//                 decoration: const InputDecoration(
//                   labelText: 'Phone*',
//                   labelStyle: TextStyle(color: Colors.white70),
//                   border: OutlineInputBorder(),
//                   enabledBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white70),
//                   ),
//                   focusedBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white),
//                   ),
//                 ),
//                 keyboardType: TextInputType.phone,
//               ),
//               const SizedBox(height: 10),
//               TextField(
//                 controller: otController,
//                 style: const TextStyle(color: Colors.white),
//                 decoration: const InputDecoration(
//                   labelText: 'OT Number',
//                   labelStyle: TextStyle(color: Colors.white70),
//                   border: OutlineInputBorder(),
//                   enabledBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white70),
//                   ),
//                   focusedBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 10),
//               TextField(
//                 controller: dateController,
//                 style: const TextStyle(color: Colors.white),
//                 decoration: const InputDecoration(
//                   labelText: 'Operation Date',
//                   labelStyle: TextStyle(color: Colors.white70),
//                   border: OutlineInputBorder(),
//                   enabledBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white70),
//                   ),
//                   focusedBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 10),
//               TextField(
//                 controller: timeController,
//                 style: const TextStyle(color: Colors.white),
//                 decoration: const InputDecoration(
//                   labelText: 'Operation Time (HH:MM)',
//                   labelStyle: TextStyle(color: Colors.white70),
//                   border: OutlineInputBorder(),
//                   enabledBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white70),
//                   ),
//                   focusedBorder: OutlineInputBorder(
//                     borderSide: BorderSide(color: Colors.white),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(context).pop(),
//             child: const Text('Cancel', style: TextStyle(color: Colors.white)),
//           ),
//           ElevatedButton(
//             onPressed: () async {
//               if (nameController.text.isEmpty ||
//                   ageController.text.isEmpty ||
//                   genderController.text.isEmpty ||
//                   phoneController.text.isEmpty) {
//                 Fluttertoast.showToast(
//                   msg: 'Please fill all required fields',
//                   gravity: ToastGravity.BOTTOM,
//                 );
//                 return;
//               }

//               try {
//                 final patient = Patient(
//                   patientId: 'PAT${DateTime.now().millisecondsSinceEpoch}',
//                   name: nameController.text,
//                   age: int.tryParse(ageController.text) ?? 0,
//                   gender: genderController.text,
//                   phone: phoneController.text,
//                   operationOt: otController.text,
//                   operationDate: dateController.text.isNotEmpty
//                       ? dateController.text
//                       : _getTodayDate(),
//                   operationTime: timeController.text,
//                 );

//                 // Only add to list if patient belongs to current OT
//                 if (patient.operationOt == otNumber &&
//                     (patient.operationDate == null ||
//                         patient.operationDate == _getTodayDate())) {
//                   final updatedList = List<Patient>.from(provider.patientsList);
//                   updatedList.add(patient);

//                   updatedList.sort((a, b) {
//                     final timeA = a.operationTime ?? '';
//                     final timeB = b.operationTime ?? '';
//                     return timeA.compareTo(timeB);
//                   });

//                   provider.setPatientsList(updatedList);
//                 }

//                 Navigator.of(context).pop();
//                 Fluttertoast.showToast(
//                   msg: 'Patient added to local list',
//                   gravity: ToastGravity.BOTTOM,
//                 );
//               } catch (e) {
//                 Fluttertoast.showToast(
//                   msg: 'Error adding patient: $e',
//                   gravity: ToastGravity.BOTTOM,
//                 );
//               }
//             },
//             style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
//             child: const Text('Add Patient'),
//           ),
//         ],
//       ),
//     );
//   }

//   void _refreshPatients(VideoSwitcherProvider provider) {
//     final filteredPatients = _demoPatients.where((patient) {
//       return patient.operationOt == otNumber;
//     }).toList();

//     filteredPatients.sort((a, b) {
//       final timeA = a.operationTime ?? '';
//       final timeB = b.operationTime ?? '';
//       return timeA.compareTo(timeB);
//     });

//     provider.setPatientsList(filteredPatients);
//     Fluttertoast.showToast(
//       msg: "Refreshed ${filteredPatients.length} demo patients",
//       gravity: ToastGravity.BOTTOM,
//     );
//   }

//   // ==================== FIXED RECORDING METHODS ====================

//   String _getDuration(DateTime? startTime) {
//     if (startTime == null) return "00:00";
//     final diff = DateTime.now().difference(startTime);
//     return "${diff.inMinutes.toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
//   }

//   Future<void> _requestPermissions() async {
//     if (Platform.isAndroid) {
//       try {
//         final deviceInfo = DeviceInfoPlugin();
//         final androidInfo = await deviceInfo.androidInfo;
//         final sdkInt = androidInfo.version.sdkInt;

//         print("=== DEBUG: Android SDK Version: $sdkInt ===");

//         await Permission.camera.request();
//         await Permission.microphone.request();

//         if (sdkInt >= 33) {
//           print(
//             "=== DEBUG: Android 13+ detected, requesting media permissions ===",
//           );

//           await Permission.photos.request();
//           await Permission.videos.request();
//           await Permission.audio.request();
//           await Permission.notification.request();
//           await Permission.manageExternalStorage.request();
//         } else {
//           print(
//             "=== DEBUG: Android 12 or below, requesting storage permissions ===",
//           );
//           await Permission.storage.request();
//         }

//         final manageStorageStatus = await Permission.manageExternalStorage
//             .request();
//         print(
//           "=== DEBUG: MANAGE_EXTERNAL_STORAGE status: $manageStorageStatus ===",
//         );
//       } catch (e) {
//         print("=== DEBUG: Error requesting permissions: $e ===");
//       }
//     }
//   }

//   Future<void> _takeScreenshot(BuildContext context) async {
//     final provider = Provider.of<VideoSwitcherProvider>(context, listen: false);

//     try {
//       if (!provider.usbConnected || provider.usbPath == null) {
//         Fluttertoast.showToast(
//           msg: "Please select USB storage first",
//           gravity: ToastGravity.BOTTOM,
//         );
//         return;
//       }

//       await Future.delayed(const Duration(milliseconds: 200));

//       RenderRepaintBoundary boundary =
//           provider.repaintKey.currentContext!.findRenderObject()
//               as RenderRepaintBoundary;

//       ui.Image image = await boundary.toImage(pixelRatio: 3.0);
//       ByteData? byteData = await image.toByteData(
//         format: ui.ImageByteFormat.png,
//       );

//       if (byteData == null) {
//         throw Exception("Failed to capture screenshot bytes");
//       }

//       Uint8List pngBytes = byteData.buffer.asUint8List();

//       final screenshotDir = Directory(
//         path.join(provider.usbPath!, 'Screenshots'),
//       );
//       if (!await screenshotDir.exists()) {
//         await screenshotDir.create(recursive: true);
//       }

//       final videoName = _assetVideos[_selectedVideoIndex]['name'];
//       final fileName =
//           '${videoName}_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
//       final file = File(path.join(screenshotDir.path, fileName));
//       await file.writeAsBytes(pngBytes);

//       Fluttertoast.showToast(
//         msg:
//             "Screenshot saved: $fileName\nSize: ${file.lengthSync() ~/ 1024} KB",
//         gravity: ToastGravity.BOTTOM,
//         backgroundColor: Colors.green,
//       );
//     } catch (e) {
//       print("Failed to capture screenshot: $e");
//       Fluttertoast.showToast(
//         msg: "Failed to capture screenshot",
//         gravity: ToastGravity.BOTTOM,
//         backgroundColor: Colors.red,
//       );
//     }
//   }

//   Widget buildControlBtn(
//     String label, {
//     IconData? icon,
//     VoidCallback? onPressed,
//     Color? color,
//   }) {
//     return Consumer<VideoSwitcherProvider>(
//       builder: (context, provider, child) {
//         bool hasFolder = provider.usbPath != null && provider.usbConnected;

//         return SizedBox(
//           width: 140,
//           child: ElevatedButton.icon(
//             onPressed: onPressed,
//             icon: Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 if (icon != null)
//                   Icon(
//                     icon,
//                     size: 16,
//                     color: color != null ? Colors.white : null,
//                   ),
//                 if (label.contains("Record"))
//                   Padding(
//                     padding: const EdgeInsets.only(left: 4),
//                     child: Icon(
//                       hasFolder ? Icons.folder_open : Icons.folder,
//                       size: 14,
//                       color: hasFolder ? Colors.green : Colors.yellow,
//                     ),
//                   ),
//               ],
//             ),
//             label: Text(
//               label,
//               overflow: TextOverflow.ellipsis,
//               style: TextStyle(
//                 color: color != null ? Colors.white : Colors.black,
//               ),
//             ),
//             style: ElevatedButton.styleFrom(
//               backgroundColor: color ?? Colors.white,
//               foregroundColor: color != null ? Colors.white : Colors.black,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(30),
//               ),
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
//             ),
//           ),
//         );
//       },
//     );
//   }
// }
