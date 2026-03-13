import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// ==================== DATA MODELS ====================

class Patient {
  final int? id;
  final String patientId;
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

  final String? eye;
  final String? eyeCondition;
  final String? eyeSurgery;
  final String? visionLeft;
  final String? visionRight;
  final Map<String, dynamic>? checklist;

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
    this.eye,
    this.eyeCondition,
    this.eyeSurgery,
    this.visionLeft,
    this.visionRight,
    this.checklist,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    // Handle checklist parsing
    Map<String, dynamic>? parsedChecklist;
    if (json['checklist'] != null) {
      try {
        if (json['checklist'] is String) {
          parsedChecklist = jsonDecode(json['checklist']);
        } else if (json['checklist'] is Map) {
          parsedChecklist = Map<String, dynamic>.from(json['checklist']);
        }
      } catch (e) {
        print('Error parsing checklist: $e');
        parsedChecklist = null;
      }
    }

    return Patient(
      id: json['id'],
      patientId: json['patient_id'] ?? json['mrd_number'] ?? '',
      patientCategory: json['patient_category'],
      name: json['name'] ?? '',
      age: json['age'] is int
          ? json['age']
          : int.tryParse(json['age']?.toString() ?? '0') ?? 0,
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
      eye: json['eye'],
      eyeCondition: json['eye_condition'],
      eyeSurgery: json['eye_surgery'],
      visionLeft: json['vision_left'],
      visionRight: json['vision_right'],
      checklist: parsedChecklist,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'patient_id': patientId,
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
    };
  }

  // Helper method to get formatted checklist data
  Map<String, dynamic>? get formattedChecklist {
    if (checklist == null) return null;

    try {
      // Check if it's the detailed checklist structure
      if (checklist!['detailedChecklist'] != null) {
        return checklist!['detailedChecklist'] as Map<String, dynamic>;
      }
      return checklist;
    } catch (e) {
      print('Error formatting checklist: $e');
      return null;
    }
  }

  // Helper method to check if checklist exists
  bool get hasChecklist {
    return checklist != null;
  }

  // Helper method to get checklist type
  String? get checklistType {
    if (checklist == null) return null;

    final formatted = formattedChecklist;
    if (formatted != null && formatted['metadata'] != null) {
      return formatted['metadata']['formType']?.toString();
    }
    return null;
  }

  // Helper method to get checklist hospital name
  String? get checklistHospital {
    if (checklist == null) return null;

    final formatted = formattedChecklist;
    if (formatted != null && formatted['metadata'] != null) {
      return formatted['metadata']['hospitalName']?.toString();
    }
    return null;
  }
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
  static String baseUrl = 'http://192.168.1.139:3000/api';

  static Future<void> initializeBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final patientSystemIp = prefs.getString('patientSystemIp');
    if (patientSystemIp != null && patientSystemIp.isNotEmpty) {
      baseUrl = 'http://$patientSystemIp:3000/api';
      print("=== DEBUG: API Base URL set to: $baseUrl ===");
    } else {
      print("=== DEBUG: Using default API Base URL: $baseUrl ===");
    }
  }

  void _handleError(http.Response response) {
    if (response.statusCode >= 400) {
      final errorData = json.decode(response.body);
      throw Exception(errorData['error'] ?? 'An error occurred');
    }
  }

  Future<List<Patient>> getPatientsWithReports() async {
    await initializeBaseUrl();
    print("=== DEBUG: Calling API: $baseUrl/patients-with-reports ===");

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/patients-with-reports'),
        headers: {'Accept': 'application/json'},
      );

      print("=== DEBUG: Response Status: ${response.statusCode} ===");

      _handleError(response);

      final List<dynamic> data = json.decode(response.body);
      print("=== DEBUG: Parsed ${data.length} total patients from API ===");

      if (data.isNotEmpty) {
        print(
          "=== DEBUG: Sample patient - Name: ${data[0]['name']}, Date: ${data[0]['operation_date']}, OT: ${data[0]['operation_ot']} ===",
        );
      }

      return data.map((json) => Patient.fromJson(json)).toList();
    } catch (e) {
      print("=== DEBUG: Error in getPatientsWithReports: $e ===");
      rethrow;
    }
  }

  Future<List<Patient>> getPatientsByDate(String date) async {
    await initializeBaseUrl();
    print("=== DEBUG: Calling getPatientsByDate with date: $date ===");

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/patients-by-date?date=$date'),
        headers: {'Accept': 'application/json'},
      );

      print("=== DEBUG: Date Response Status: ${response.statusCode} ===");

      if (response.statusCode != 200) {
        print(
          "=== DEBUG: Date API failed with status ${response.statusCode}, using fallback ===",
        );
        throw Exception('Date-specific API failed');
      }

      final List<dynamic> data = json.decode(response.body);
      print("=== DEBUG: Found ${data.length} patients for date $date ===");

      return data.map((json) => Patient.fromJson(json)).toList();
    } catch (e) {
      print("=== DEBUG: Error in getPatientsByDate: $e ===");
      rethrow;
    }
  }

  Future<Patient> getPatient(String patientId) async {
    await initializeBaseUrl();
    final response = await http.get(Uri.parse('$baseUrl/patients/$patientId'));
    _handleError(response);
    final data = json.decode(response.body);
    return Patient.fromJson(data);
  }

  Future<bool> checkServerStatus() async {
    await initializeBaseUrl();
    try {
      print("=== DEBUG: Checking server status at: $baseUrl/test ===");
      final response = await http.get(
        Uri.parse('$baseUrl/test'),
        headers: {'Accept': 'application/json'},
      );
      print("=== DEBUG: Server status response: ${response.statusCode} ===");
      return response.statusCode == 200;
    } catch (e) {
      print("=== DEBUG: Server status check failed: $e ===");
      return false;
    }
  }

  Future<List<Report>> getReports(String patientId) async {
    await initializeBaseUrl();
    final response = await http.get(
      Uri.parse('$baseUrl/patients/$patientId/reports'),
    );
    _handleError(response);
    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => Report.fromJson(json)).toList();
  }

  Future<List<int>> downloadReport(String patientId, int reportId) async {
    await initializeBaseUrl();
    final response = await http.get(
      Uri.parse('$baseUrl/patients/$patientId/reports/$reportId/download'),
    );
    _handleError(response);
    return response.bodyBytes;
  }
}
