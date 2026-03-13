import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:math';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:photo_view/photo_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==================== DATA MODELS ====================

class Patient {
  final int? id;
  final String patientId; // MRD number (patient_id in JSON)
  final String? patientCategory;
  final String name;
  final int age;
  final String gender;
  final String phone;
  final String? email;
  final String? bloodGroup;
  final String? address;
  final String? emergencyContact;
  final String? emergencyName;
  final String? allergies;
  final String? medications;
  final String? medicalHistory;
  final String? insurance;
  final String? insuranceId;
  final String? operationOt;
  final String? operationDate;
  final String? operationTime;
  final String? operationDoctor;
  final String? operationDoctorRole;
  final String? operationNotes;
  final String? createdAt;
  final int? reportCount;

  // New fields from JSON
  final String? eye;
  final String? eyeCondition;
  final String? eyeSurgery;
  final String? visionLeft;
  final String? visionRight;
  final Map<String, dynamic>? checklist;
  final String? currentUser;

  Patient({
    this.id,
    required this.patientId,
    this.patientCategory,
    required this.name,
    required this.age,
    required this.gender,
    required this.phone,
    this.email,
    this.bloodGroup,
    this.address,
    this.emergencyContact,
    this.emergencyName,
    this.allergies,
    this.medications,
    this.medicalHistory,
    this.insurance,
    this.insuranceId,
    this.operationOt,
    this.operationDate,
    this.operationTime,
    this.operationDoctor,
    this.operationDoctorRole,
    this.operationNotes,
    this.createdAt,
    this.reportCount,

    // New fields
    this.eye,
    this.eyeCondition,
    this.eyeSurgery,
    this.visionLeft,
    this.visionRight,
    this.checklist,
    this.currentUser,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    // Handle checklist parsing
    Map<String, dynamic>? parsedChecklist;
    if (json['checklist'] != null && json['checklist'] is String) {
      try {
        parsedChecklist = jsonDecode(json['checklist']);
      } catch (e) {
        print('Error parsing checklist: $e');
        parsedChecklist = null;
      }
    } else if (json['checklist'] != null && json['checklist'] is Map) {
      parsedChecklist = Map<String, dynamic>.from(json['checklist']);
    }

    return Patient(
      id: json['id'],
      patientId:
          json['patient_id'] ??
          json['mrd_number'] ??
          '', // MRD number is most important
      patientCategory: json['patient_category'],
      name: json['name'] ?? '',
      age: json['age'] is String
          ? int.tryParse(json['age']) ?? 0
          : json['age'] ?? 0,
      gender: json['gender'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'],
      bloodGroup: json['blood_group'],
      address: json['address'],
      emergencyContact: json['emergency_contact'],
      emergencyName: json['emergency_name'],
      allergies: json['allergies'],
      medications: json['medications'],
      medicalHistory: json['medical_history'],
      insurance: json['insurance'],
      insuranceId: json['insurance_id'],
      operationOt: json['operation_ot'],
      operationDate: json['operation_date'],
      operationTime: json['operation_time'],
      operationDoctor: json['operation_doctor'],
      operationDoctorRole: json['operation_doctor_role'],
      operationNotes: json['operation_notes'],
      createdAt: json['created_at'],
      reportCount: json['report_count'],

      // New fields
      eye: json['eye'],
      eyeCondition: json['eye_condition'],
      eyeSurgery: json['eye_surgery'],
      visionLeft: json['vision_left'],
      visionRight: json['vision_right'],
      checklist: parsedChecklist,
      currentUser: json['currentUser'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'patient_id': patientId, // MRD number
      'mrd_number':
          patientId, // Also include as mrd_number for backward compatibility
      'patient_category': patientCategory,
      'name': name,
      'age': age,
      'gender': gender,
      'phone': phone,
      'email': email,
      'blood_group': bloodGroup,
      'address': address,
      'emergency_contact': emergencyContact,
      'emergency_name': emergencyName,
      'allergies': allergies,
      'medications': medications,
      'medical_history': medicalHistory,
      'insurance': insurance,
      'insurance_id': insuranceId,
      'operation_ot': operationOt,
      'operation_date': operationDate,
      'operation_time': operationTime,
      'operation_doctor': operationDoctor,
      'operation_doctor_role': operationDoctorRole,
      'operation_notes': operationNotes,

      // New fields
      'eye': eye,
      'eye_condition': eyeCondition,
      'eye_surgery': eyeSurgery,
      'vision_left': visionLeft,
      'vision_right': visionRight,
      'checklist': checklist != null ? jsonEncode(checklist) : null,
      'currentUser': currentUser,
    };
  }

  // Helper method to display MRD number prominently
  String get displayMrdNumber {
    return patientId.isNotEmpty ? 'MRD: $patientId' : 'MRD: Not assigned';
  }

  // Helper method to check if MRD is valid
  bool get hasValidMrd => patientId.isNotEmpty && patientId != 'Not assigned';
}

class Report {
  final int id;
  final String patientId;
  final String originalName;
  final String filename;
  final int fileSize;
  final String fileType;
  final String description;
  final String fileUrl;
  final String? uploadDate;

  Report({
    required this.id,
    required this.patientId,
    required this.originalName,
    required this.filename,
    required this.fileSize,
    required this.fileType,
    required this.description,
    required this.fileUrl,
    this.uploadDate,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] ?? 0,
      patientId: json['patient_id'] ?? '',
      originalName: json['original_name'] ?? 'Unknown Report',
      filename: json['filename'] ?? '',
      fileSize: json['file_size'] ?? 0,
      fileType: json['file_type'] ?? 'application/octet-stream',
      description: json['description'] ?? '',
      fileUrl: json['file_url'] ?? '',
      uploadDate: json['upload_date'],
    );
  }
}

// ==================== API SERVICE ====================

class ApiService {
  // Remove hardcoded IP and use SharedPreferences
  static String baseUrl = 'http://192.168.1.132:3000/api'; // Default fallback

  // Initialize baseUrl from SharedPreferences
  static Future<void> initializeBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final patientSystemIp = prefs.getString('patientSystemIp');
    if (patientSystemIp != null && patientSystemIp.isNotEmpty) {
      baseUrl = 'http://192.168.0.139:3000/api';
    }
    // If patientSystemIp is not set, it will use the default fallback
  }

  // Handle API errors
  void _handleError(http.Response response) {
    if (response.statusCode >= 400) {
      final errorData = json.decode(response.body);
      throw Exception(errorData['error'] ?? 'An error occurred');
    }
  }

  // Get all patients
  Future<List<Patient>> getPatients() async {
    await initializeBaseUrl(); // Ensure baseUrl is updated
    final response = await http.get(Uri.parse('$baseUrl/patients'));
    _handleError(response);
    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => Patient.fromJson(json)).toList();
  }

  // Get single patient
  Future<Patient> getPatient(String patientId) async {
    await initializeBaseUrl(); // Ensure baseUrl is updated
    final response = await http.get(Uri.parse('$baseUrl/patients/$patientId'));
    _handleError(response);
    final data = json.decode(response.body);
    return Patient.fromJson(data);
  }

  // Add new patient
  Future<Patient> addPatient(Patient patient) async {
    await initializeBaseUrl(); // Ensure baseUrl is updated
    final response = await http.post(
      Uri.parse('$baseUrl/patients'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(patient.toJson()),
    );
    _handleError(response);
    final data = json.decode(response.body);
    return Patient.fromJson({...patient.toJson(), 'id': data['id']});
  }

  // Update patient
  Future<void> updatePatient(String patientId, Patient patient) async {
    await initializeBaseUrl(); // Ensure baseUrl is updated
    final response = await http.put(
      Uri.parse('$baseUrl/patients/$patientId'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(patient.toJson()),
    );
    _handleError(response);
  }

  // Delete patient
  Future<void> deletePatient(String patientId) async {
    await initializeBaseUrl(); // Ensure baseUrl is updated
    final response = await http.delete(
      Uri.parse('$baseUrl/patients/$patientId'),
    );
    _handleError(response);
  }

  // Check server status
  Future<bool> checkServerStatus() async {
    await initializeBaseUrl(); // Ensure baseUrl is updated
    try {
      final response = await http.get(Uri.parse('$baseUrl/test'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get all reports for a patient
  Future<List<Report>> getReports(String patientId) async {
    await initializeBaseUrl(); // Ensure baseUrl is updated
    final response = await http.get(
      Uri.parse('$baseUrl/patients/$patientId/reports'),
    );
    _handleError(response);
    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => Report.fromJson(json)).toList();
  }

  // Download report file
  Future<List<int>> downloadReport(String patientId, int reportId) async {
    await initializeBaseUrl(); // Ensure baseUrl is updated
    final response = await http.get(
      Uri.parse('$baseUrl/patients/$patientId/reports/$reportId/download'),
    );
    _handleError(response);
    return response.bodyBytes;
  }

  // Get patients with report counts
  Future<List<Patient>> getPatientsWithReports() async {
    await initializeBaseUrl(); // Ensure baseUrl is updated
    final response = await http.get(
      Uri.parse('$baseUrl/patients-with-reports'),
    );
    _handleError(response);
    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => Patient.fromJson(json)).toList();
  }
}

// ==================== FILE VIEWER SCREEN ====================

class FileViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;
  final String fileType;

  const FileViewerScreen({
    Key? key,
    required this.filePath,
    required this.fileName,
    required this.fileType,
  }) : super(key: key);

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  bool _isLoading = true;
  String? _pdfPath;
  int? _totalPages;
  int _currentPage = 0;
  bool _pdfReady = false;

  @override
  void initState() {
    super.initState();
    _initializeFile();
  }

  void _initializeFile() {
    setState(() {
      _isLoading = false;
      _pdfPath = widget.filePath;
      _pdfReady = true;
    });
  }

  bool get _isPdf => widget.fileType.toLowerCase().contains('pdf');
  bool get _isImage {
    final type = widget.fileType.toLowerCase();
    return type.contains('jpg') ||
        type.contains('jpeg') ||
        type.contains('png') ||
        type.contains('gif') ||
        type.contains('bmp');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => OpenFilex.open(widget.filePath),
            tooltip: 'Open with external app',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isPdf
          ? _buildPdfViewer()
          : _isImage
          ? _buildImageViewer()
          : _buildUnsupportedFileView(),
    );
  }

  Widget _buildPdfViewer() {
    return Column(
      children: [
        if (_totalPages != null)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[200],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Page $_currentPage of $_totalPages',
                  style: const TextStyle(fontSize: 14),
                ),
                if (_totalPages! > 1)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, size: 16),
                        onPressed: _currentPage > 0
                            ? () {
                                // You can add page navigation logic here
                              }
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, size: 16),
                        onPressed: _currentPage < _totalPages! - 1
                            ? () {
                                // You can add page navigation logic here
                              }
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        Expanded(
          child: PDFView(
            filePath: _pdfPath,
            autoSpacing: true,
            enableSwipe: true,
            pageSnap: true,
            swipeHorizontal: false,
            onRender: (_pages) {
              setState(() {
                _totalPages = _pages;
                _pdfReady = true;
              });
            },
            onError: (error) {
              print(error.toString());
            },
            onPageError: (page, error) {
              print('$page: ${error.toString()}');
            },
            onViewCreated: (PDFViewController pdfViewController) {
              // You can store the controller for later use
            },
            onPageChanged: (int? page, int? total) {
              setState(() {
                _currentPage = page!;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildImageViewer() {
    return PhotoView(
      imageProvider: FileImage(File(widget.filePath)),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 2,
      initialScale: PhotoViewComputedScale.contained,
      basePosition: Alignment.center,
    );
  }

  Widget _buildUnsupportedFileView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.insert_drive_file, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'File Type Not Supported',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'File type: ${widget.fileType}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => OpenFilex.open(widget.filePath),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
            ),
            child: const Text('Open with External App'),
          ),
        ],
      ),
    );
  }
}

// ==================== MAIN APP ====================

void main() {
  runApp(const HospitalManagementApp());
}

class HospitalManagementApp extends StatelessWidget {
  const HospitalManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hospital Management',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const PatientListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==================== PATIENT LIST SCREEN ====================

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({Key? key}) : super(key: key);

  @override
  _PatientListScreenState createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final ApiService _apiService = ApiService();
  List<Patient> _patients = [];
  bool _isLoading = true;
  String _error = '';
  bool _serverOnline = false;
  String _currentIp = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentIp();
    _checkServerStatus();
    _loadPatients();
  }

  Future<void> _loadCurrentIp() async {
    final prefs = await SharedPreferences.getInstance();
    final patientSystemIp = prefs.getString('patientSystemIp');
    setState(() {
      _currentIp = patientSystemIp ?? 'Not configured';
    });
  }

  Future<void> _checkServerStatus() async {
    final isOnline = await _apiService.checkServerStatus();
    setState(() {
      _serverOnline = isOnline;
    });
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final patients = await _apiService.getPatientsWithReports();
      setState(() {
        _patients = patients;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deletePatient(String patientId, String patientName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Patient'),
        content: Text('Are you sure you want to delete $patientName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiService.deletePatient(patientId);
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Patient $patientName deleted')));
        _loadPatients();
      } catch (e) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting patient: $e')));
      }
    }
  }

  void _showAddPatientDialog() {
    final nameController = TextEditingController();
    final ageController = TextEditingController();
    final genderController = TextEditingController();
    final phoneController = TextEditingController();
    final patientIdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        // The blur effect applied to everything behind the dialog
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          // Semi-transparent background for the glass effect
          backgroundColor: Colors.white.withOpacity(0.12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
          ),
          title: const Text(
            'Add New Patient',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildGlassTextField(
                    controller: patientIdController,
                    label: 'MRD Number*',
                    icon: Icons.medical_services,
                    hint: 'Enter patient MRD number',
                  ),
                  const SizedBox(height: 16),
                  _buildGlassTextField(
                    controller: nameController,
                    label: 'Full Name*',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildGlassTextField(
                          controller: ageController,
                          label: 'Age*',
                          icon: Icons.calendar_today,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildGlassTextField(
                          controller: genderController,
                          label: 'Gender*',
                          icon: Icons.transgender,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildGlassTextField(
                    controller: phoneController,
                    label: 'Phone*',
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.all(16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00796B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: () async {
                if (patientIdController.text.isEmpty ||
                    nameController.text.isEmpty ||
                    ageController.text.isEmpty ||
                    genderController.text.isEmpty ||
                    phoneController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill all required fields'),
                    ),
                  );
                  return;
                }

                try {
                  final patient = Patient(
                    patientId: patientIdController.text,
                    name: nameController.text,
                    age: int.tryParse(ageController.text) ?? 0,
                    gender: genderController.text,
                    phone: phoneController.text,
                  );

                  await _apiService.addPatient(patient);
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Patient added successfully')),
                  );
                  _loadPatients();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error adding patient: $e')),
                  );
                }
              },
              child: const Text('Add Patient'),
            ),
          ],
        ),
      ),
    );
  }

  /// Helper method to create consistent glass-styled TextFields
  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00796B), width: 2),
        ),
      ),
    );
  }

  Widget _buildPatientCard(Patient patient, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getColorByIndex(index),
          child: Text(
            patient.name[0].toUpperCase(),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          patient.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            // Highlight MRD number
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue[100]!),
              ),
              child: Text(
                'MRD: ${patient.patientId}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${patient.age} years • ${patient.gender}',
              style: const TextStyle(fontSize: 14),
            ),
            if (patient.phone.isNotEmpty)
              Text(
                'Phone: ${patient.phone}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (patient.reportCount != null && patient.reportCount! > 0)
              Chip(
                label: Text(
                  '${patient.reportCount} reports',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
                backgroundColor: Colors.blue,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'view') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PatientDetailScreen(patient: patient),
                ),
              );
            } else if (value == 'delete') {
              _deletePatient(patient.patientId, patient.name);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'view', child: Text('View Details')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PatientDetailScreen(patient: patient),
            ),
          );
        },
      ),
    );
  }

  Color _getColorByIndex(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //       static const Color _primaryColor = Color.fromARGB(255, 44, 16, 90);
      // static const Color _accentColor = Color.fromARGB(255, 68, 49, 127);
      backgroundColor: const Color.fromARGB(255, 44, 16, 90),
      appBar: AppBar(
        title: const Text('Hospital Patients'),
        backgroundColor: Color.fromARGB(255, 44, 16, 90),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Show current IP configuration
          Tooltip(
            message: 'Server IP: $_currentIp',
            child: IconButton(
              icon: Icon(
                _serverOnline ? Icons.cloud_done : Icons.cloud_off,
                color: _serverOnline ? Colors.greenAccent : Colors.redAccent,
              ),
              onPressed: _checkServerStatus,
              tooltip: _serverOnline ? 'Server Online' : 'Server Offline',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPatients,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPatientDialog,
        backgroundColor: const Color(0xFF2196F3),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading patients...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Error Loading Patients',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Using IP: $_currentIp',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loadPatients,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _patients.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Patients Found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add your first patient using the + button',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Server IP: $_currentIp',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _showAddPatientDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Add First Patient'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Show current IP configuration at the top
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.black.withOpacity(0.1),
                  child: Text(
                    'Connected to: $_currentIp',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadPatients,
                    child: ListView.builder(
                      itemCount: _patients.length,
                      itemBuilder: (context, index) {
                        return _buildPatientCard(_patients[index], index);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ==================== PATIENT DETAIL SCREEN ====================

// ==================== PATIENT DETAIL SCREEN ====================

class PatientDetailScreen extends StatelessWidget {
  final Patient patient;

  const PatientDetailScreen({Key? key, required this.patient})
    : super(key: key);

  Widget _buildInfoRow(String label, String value, {bool isImportant = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not specified' : value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isImportant ? FontWeight.w500 : FontWeight.normal,
                color: isImportant ? Colors.blue[800] : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String label, dynamic value) {
    String displayValue = '';

    if (value == null || value == '') {
      displayValue = 'Not specified';
    } else if (value is List) {
      displayValue = value.isEmpty ? 'None' : value.join(', ');
    } else if (value is Map) {
      displayValue = '${value.length} items';
    } else {
      displayValue = value.toString();
    }

    return _buildInfoRow(label, displayValue);
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2196F3),
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildExpansionSection(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2196F3),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBloodSugarSection(Map<String, dynamic> bloodSugar) {
    return _buildExpansionSection('Blood Sugar Tests', [
      _buildChecklistItem('Fasting (FBS)', bloodSugar['fbs']),
      _buildChecklistItem('Post Prandial (PPBS)', bloodSugar['ppbs']),
      _buildChecklistItem('Random (RBS)', bloodSugar['rbs']),
      _buildChecklistItem('HbA1c', bloodSugar['hba1c']),
    ]);
  }

  Widget _buildDifferentialCountSection(Map<String, dynamic> dlc) {
    return _buildExpansionSection('Differential Count (DLC)', [
      _buildChecklistItem('Neutrophil', dlc['neutrophil']),
      _buildChecklistItem('Lymphocyte', dlc['lymphocyte']),
      _buildChecklistItem('Eosinophil', dlc['eosinophil']),
      _buildChecklistItem('Monocyte', dlc['monocyte']),
      _buildChecklistItem('Basophil', dlc['basophil']),
    ]);
  }

  Widget _buildBiochemistrySection(Map<String, dynamic> biochemistry) {
    return _buildExpansionSection('Biochemistry', [
      _buildChecklistItem('Creatinine', biochemistry['creatinine']),
      _buildChecklistItem('BUN', biochemistry['bun']),
      _buildChecklistItem('Sodium', biochemistry['sodium']),
      _buildChecklistItem('Potassium', biochemistry['potassium']),
      _buildChecklistItem('Chloride', biochemistry['chloride']),
    ]);
  }

  Widget _buildUrineTestsSection(Map<String, dynamic> urineTests) {
    return _buildExpansionSection('Urine Tests', [
      _buildChecklistItem('Protein', urineTests['protein']),
      _buildChecklistItem('Glucose', urineTests['glucose']),
      _buildChecklistItem('Ketone', urineTests['ketone']),
      _buildChecklistItem('Blood', urineTests['blood']),
      _buildChecklistItem('Pus Cells', urineTests['pusCells']),
      _buildChecklistItem('Epithelial Cells', urineTests['epithelialCells']),
      _buildChecklistItem('Bacteria', urineTests['bacteria']),
      _buildChecklistItem('Cast', urineTests['cast']),
    ]);
  }

  Widget _buildInfectiveProfileSection(Map<String, dynamic> infectiveProfile) {
    return _buildExpansionSection('Infective Profile', [
      _buildChecklistItem('HBsAg', infectiveProfile['hbsag']),
      _buildChecklistItem('HIV', infectiveProfile['hiv']),
      _buildChecklistItem('HCV', infectiveProfile['hcv']),
      _buildChecklistItem('HBV', infectiveProfile['hbv']),
    ]);
  }

  Widget _buildBloodTestsSection(Map<String, dynamic> bloodTests) {
    return _buildExpansionSection('Blood Tests', [
      _buildChecklistItem('Hemoglobin', bloodTests['hemoglobin']),
      _buildChecklistItem('ESR', bloodTests['esr']),
      _buildChecklistItem('CRP', bloodTests['crp']),
      _buildChecklistItem('Platelet', bloodTests['platelet']),
      _buildChecklistItem('TLC', bloodTests['tlc']),
      if (bloodTests['dlc'] != null && bloodTests['dlc'] is Map)
        _buildDifferentialCountSection(
          Map<String, dynamic>.from(bloodTests['dlc']),
        ),
      if (bloodTests['bloodSugar'] != null && bloodTests['bloodSugar'] is Map)
        _buildBloodSugarSection(
          Map<String, dynamic>.from(bloodTests['bloodSugar']),
        ),
      if (bloodTests['biochemistry'] != null &&
          bloodTests['biochemistry'] is Map)
        _buildBiochemistrySection(
          Map<String, dynamic>.from(bloodTests['biochemistry']),
        ),
    ]);
  }

  Widget _buildMedicalHistorySection(Map<String, dynamic> medicalHistory) {
    return _buildExpansionSection('Medical History', [
      _buildChecklistItem('Diabetic', medicalHistory['diabetic']),
      _buildChecklistItem('Diabetic Since', medicalHistory['diabeticSince']),
      _buildChecklistItem('Insulin', medicalHistory['insulin']),
      _buildChecklistItem('Cardiac Issues', medicalHistory['cardiac']),
      _buildChecklistItem('Angioplasty', medicalHistory['angioplasty']),
      _buildChecklistItem('Bypass Surgery', medicalHistory['bypass']),
      _buildChecklistItem('Blood Thinners', medicalHistory['bloodThinner']),
      _buildChecklistItem('Kidney Issues', medicalHistory['kidney']),
      _buildChecklistItem('Dialysis', medicalHistory['dialysis']),
      _buildChecklistItem('Other', medicalHistory['other']),
    ]);
  }

  Widget _buildPatientInfoSection(Map<String, dynamic> patientInfo) {
    return _buildSection('Checklist - Patient Information', [
      _buildChecklistItem('Patient Name', patientInfo['patientName']),
      _buildChecklistItem('MRD Number', patientInfo['mrdNumber']),
      _buildChecklistItem('Age', patientInfo['age']),
      _buildChecklistItem('Gender', patientInfo['gender']),
      _buildChecklistItem('Phone', patientInfo['phone']),
      _buildChecklistItem('Lab Name', patientInfo['labName']),
      _buildChecklistItem('Physician', patientInfo['physician']),
      _buildChecklistItem('Physician Date', patientInfo['physicianDate']),
    ]);
  }

  Widget _buildVerificationSection(Map<String, dynamic> verification) {
    return _buildSection('Verification', [
      _buildChecklistItem('Nurse Verified', verification['nurseVerified']),
      _buildChecklistItem('Nurse Time', verification['nurseTime']),
      _buildChecklistItem('Doctor Verified', verification['doctorVerified']),
      _buildChecklistItem('Doctor Time', verification['doctorTime']),
    ]);
  }

  Widget _buildMetadataSection(Map<String, dynamic> metadata) {
    return _buildSection('Checklist Metadata', [
      _buildChecklistItem('Form Type', metadata['formType']),
      _buildChecklistItem('Completed By', metadata['completedBy']),
      _buildChecklistItem('Hospital Name', metadata['hospitalName']),
      _buildChecklistItem(
        'Collection Date',
        metadata['collectedAt']?.split('T')[0] ?? '',
      ),
    ]);
  }

  // Helper method to build checklist widgets
  List<Widget> _buildChecklistWidgets() {
    final List<Widget> widgets = [];

    if (patient.checklist == null) return widgets;

    // Checklist header
    widgets.addAll([
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          children: [
            const Icon(Icons.checklist, color: Colors.blue, size: 24),
            const SizedBox(width: 10),
            Text(
              'RETINAL SURGERY CHECKLIST',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            const Spacer(),
            Chip(
              label: const Text(
                'Complete',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
              backgroundColor: Colors.green,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ]);

    // Extract detailedChecklist
    final Map<String, dynamic>? detailedChecklist =
        patient.checklist!['detailedChecklist'] != null &&
            patient.checklist!['detailedChecklist'] is Map
        ? Map<String, dynamic>.from(
            patient.checklist!['detailedChecklist'] as Map,
          )
        : null;

    if (detailedChecklist != null) {
      // Patient Info
      if (detailedChecklist['patientInfo'] != null) {
        widgets.add(
          _buildPatientInfoSection(
            Map<String, dynamic>.from(detailedChecklist['patientInfo'] as Map),
          ),
        );
      }

      // Medical History
      if (detailedChecklist['medicalHistory'] != null) {
        widgets.add(
          _buildMedicalHistorySection(
            Map<String, dynamic>.from(
              detailedChecklist['medicalHistory'] as Map,
            ),
          ),
        );
      }

      // Blood Tests
      if (detailedChecklist['bloodTests'] != null) {
        widgets.add(
          _buildBloodTestsSection(
            Map<String, dynamic>.from(detailedChecklist['bloodTests'] as Map),
          ),
        );
      }

      // Urine Tests
      if (detailedChecklist['urineTests'] != null) {
        widgets.add(
          _buildUrineTestsSection(
            Map<String, dynamic>.from(detailedChecklist['urineTests'] as Map),
          ),
        );
      }

      // Infective Profile
      if (detailedChecklist['infectiveProfile'] != null) {
        widgets.add(
          _buildInfectiveProfileSection(
            Map<String, dynamic>.from(
              detailedChecklist['infectiveProfile'] as Map,
            ),
          ),
        );
      }

      // Verification
      if (detailedChecklist['verification'] != null) {
        widgets.add(
          _buildVerificationSection(
            Map<String, dynamic>.from(detailedChecklist['verification'] as Map),
          ),
        );
      }
    }

    // Metadata
    if (patient.checklist!['metadata'] != null) {
      widgets.add(
        _buildMetadataSection(
          Map<String, dynamic>.from(patient.checklist!['metadata'] as Map),
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf5f5f5),
      appBar: AppBar(
        title: Text(patient.name),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (patient.checklist != null)
            IconButton(
              icon: const Icon(Icons.checklist, color: Colors.white),
              onPressed: () {
                // Scroll to checklist section
                Scrollable.ensureVisible(
                  context,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                );
              },
              tooltip: 'View Checklist',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient ID Header with prominent MRD display
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.medical_services,
                      color: Colors.blue,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MRD: ${patient.patientId}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            patient.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          if (patient.reportCount != null &&
                              patient.reportCount! > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${patient.reportCount} medical reports available',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                PatientReportsScreen(patient: patient),
                          ),
                        );
                      },
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('View Reports'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Basic Information
            _buildSection('Basic Information', [
              _buildInfoRow('Full Name', patient.name, isImportant: true),
              _buildInfoRow('MRD Number', patient.patientId, isImportant: true),
              _buildInfoRow('Age', '${patient.age} years', isImportant: true),
              _buildInfoRow('Gender', patient.gender, isImportant: true),
              _buildInfoRow('Phone', patient.phone, isImportant: true),
              _buildInfoRow('Email', patient.email ?? ''),
              _buildInfoRow('Blood Group', patient.bloodGroup ?? ''),
              _buildInfoRow('Address', patient.address ?? ''),
              _buildInfoRow(
                'Patient Category',
                patient.patientCategory ?? 'General',
              ),
            ]),

            // Emergency Contact
            if (patient.emergencyContact != null ||
                patient.emergencyName != null)
              _buildSection('Emergency Contact', [
                _buildInfoRow('Contact Name', patient.emergencyName ?? ''),
                _buildInfoRow('Contact Number', patient.emergencyContact ?? ''),
              ]),

            // Medical Information
            _buildSection('Medical Information', [
              _buildInfoRow('Allergies', patient.allergies ?? 'None recorded'),
              _buildInfoRow(
                'Current Medications',
                patient.medications ?? 'None recorded',
              ),
              _buildInfoRow(
                'Medical History',
                patient.medicalHistory ?? 'None recorded',
              ),
              _buildInfoRow(
                'Insurance Provider',
                patient.insurance ?? 'Not specified',
              ),
              _buildInfoRow(
                'Insurance ID',
                patient.insuranceId ?? 'Not specified',
              ),
            ]),

            // Eye Information Section
            if (patient.eye != null ||
                patient.eyeCondition != null ||
                patient.eyeSurgery != null)
              _buildSection('Eye Information', [
                if (patient.eye != null) _buildInfoRow('Eye', patient.eye!),
                if (patient.eyeCondition != null)
                  _buildInfoRow('Eye Condition', patient.eyeCondition!),
                if (patient.eyeSurgery != null)
                  _buildInfoRow('Eye Surgery History', patient.eyeSurgery!),
                if (patient.visionLeft != null)
                  _buildInfoRow('Vision (Left)', patient.visionLeft!),
                if (patient.visionRight != null)
                  _buildInfoRow('Vision (Right)', patient.visionRight!),
              ]),

            // Operation Details
            if (patient.operationDoctor != null || patient.operationOt != null)
              _buildSection('Operation Details', [
                _buildInfoRow('Operation Theater', patient.operationOt ?? ''),
                _buildInfoRow('Operation Date', patient.operationDate ?? ''),
                _buildInfoRow('Operation Time', patient.operationTime ?? ''),
                _buildInfoRow(
                  'Operating Doctor',
                  patient.operationDoctor ?? '',
                ),
                _buildInfoRow('Doctor Role', patient.operationDoctorRole ?? ''),
                _buildInfoRow('Operation Notes', patient.operationNotes ?? ''),
              ]),

            // CHECKLIST SECTION
            ..._buildChecklistWidgets(),

            // Current User (if exists)
            if (patient.currentUser != null || patient.createdAt != null)
              _buildSection('System Information', [
                if (patient.currentUser != null)
                  _buildInfoRow('Current User', patient.currentUser!),
                if (patient.createdAt != null)
                  _buildInfoRow('Created On', patient.createdAt!),
              ]),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ==================== PATIENT REPORTS SCREEN ====================

class PatientReportsScreen extends StatefulWidget {
  final Patient patient;

  const PatientReportsScreen({super.key, required this.patient});

  @override
  State<PatientReportsScreen> createState() => _PatientReportsScreenState();
}

class _PatientReportsScreenState extends State<PatientReportsScreen> {
  final ApiService _apiService = ApiService();
  List<Report> _reports = [];
  bool _isLoading = true;
  String _error = '';
  String _currentIp = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentIp();
    _loadReports();
  }

  Future<void> _loadCurrentIp() async {
    final prefs = await SharedPreferences.getInstance();
    final patientSystemIp = prefs.getString('patientSystemIp');
    setState(() {
      _currentIp = patientSystemIp ?? 'Not configured';
    });
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final reports = await _apiService.getReports(widget.patient.patientId);
      setState(() {
        _reports = reports;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load reports: $e';
        _isLoading = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (bytes > 0 ? (log(bytes) / log(1024)) : 0).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _downloadAndOpenReport(Report report) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ${report.originalName}...')),
    );

    try {
      final bytes = await _apiService.downloadReport(
        widget.patient.patientId,
        report.id,
      );

      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/${report.originalName}';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      // Check if it's a PDF or image to use internal viewer
      final isPdf = report.fileType.toLowerCase().contains('pdf');
      final isImage =
          report.fileType.toLowerCase().contains('jpg') ||
          report.fileType.toLowerCase().contains('jpeg') ||
          report.fileType.toLowerCase().contains('png');

      if (isPdf || isImage) {
        // Use internal viewer for PDFs and images
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FileViewerScreen(
              filePath: filePath,
              fileName: report.originalName,
              fileType: report.fileType,
            ),
          ),
        );
      } else {
        // Use external app for other file types
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to open file: ${result.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading/opening report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  IconData _getIconForMimeType(String mimeType) {
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('image')) return Icons.image;
    if (mimeType.contains('text') || mimeType.contains('csv'))
      return Icons.text_snippet;
    if (mimeType.contains('word') || mimeType.contains('document'))
      return Icons.description;
    return Icons.insert_drive_file;
  }

  Color _getColorForMimeType(String mimeType) {
    if (mimeType.contains('pdf')) return Colors.red;
    if (mimeType.contains('image')) return Colors.green;
    if (mimeType.contains('text') || mimeType.contains('csv'))
      return Colors.blue;
    if (mimeType.contains('word') || mimeType.contains('document'))
      return Colors.blue;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf5f5f5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.patient.name, style: const TextStyle(fontSize: 16)),
            Text(
              'MRD: ${widget.patient.patientId}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadReports),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Server IP: $_currentIp',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _loadReports,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _reports.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No Reports Found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No medical reports available for ${widget.patient.name}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'MRD: ${widget.patient.patientId}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Server IP: $_currentIp',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Show patient MRD at the top
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.blue[50],
                  child: Column(
                    children: [
                      Text(
                        'Patient MRD: ${widget.patient.patientId}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Connected to: $_currentIp',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _reports.length,
                    itemBuilder: (context, index) {
                      final report = _reports[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 2,
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getColorForMimeType(
                                report.fileType,
                              ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _getIconForMimeType(report.fileType),
                              color: _getColorForMimeType(report.fileType),
                              size: 24,
                            ),
                          ),
                          title: Text(
                            report.originalName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                '${report.fileType.split('/').last.toUpperCase()} • ${_formatBytes(report.fileSize)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (report.description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    report.description,
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (report.uploadDate != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'Uploaded: ${report.uploadDate!.split(' ')[0]}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.download, color: Colors.blue[700]),
                            onPressed: () => _downloadAndOpenReport(report),
                            tooltip: 'Download and Open',
                          ),
                          onTap: () => _downloadAndOpenReport(report),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
