import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

// =============================================================================
// 1. DATA MODELS
// =============================================================================
class CleaningProtocolItem {
  final int serialNo;
  final String activity;
  String areaEquipment;
  String selectedDisinfectant;
  bool isSignedOff;

  CleaningProtocolItem({
    required this.serialNo,
    required this.activity,
    required this.areaEquipment,
    required this.selectedDisinfectant,
    this.isSignedOff = false,
  });
}

class CleanReport {
  final String reportId;
  final String otName;
  final String reportDate;
  final String reportTime;
  final String verifiedBy;
  final String status;
  final String? notes;
  final String? nextCheckDate;
  final DateTime createdAt;
  final int photoCount;
  final List<CleanReportPhoto> photos;

  CleanReport({
    required this.reportId,
    required this.otName,
    required this.reportDate,
    required this.reportTime,
    required this.verifiedBy,
    required this.status,
    this.notes,
    this.nextCheckDate,
    required this.createdAt,
    required this.photoCount,
    required this.photos,
  });

  factory CleanReport.fromJson(Map<String, dynamic> json) {
    return CleanReport(
      reportId: json['report_id'] ?? '',
      otName: json['ot_name'] ?? '',
      reportDate: json['report_date'] ?? '',
      reportTime: json['report_time'] ?? '',
      verifiedBy: json['verified_by'] ?? '',
      status: json['status'] ?? 'satisfactory',
      notes: json['notes'],
      nextCheckDate: json['next_check_date'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      photoCount: json['photo_count'] ?? 0,
      photos: (json['photos'] as List<dynamic>? ?? [])
          .map((photo) => CleanReportPhoto.fromJson(photo))
          .toList(),
    );
  }

  Map<String, dynamic> toFormData() {
    return {
      'ot_name': otName,
      'report_date': reportDate,
      'report_time': reportTime,
      'verified_by': verifiedBy,
      'status': status,
      if (notes != null && notes!.isNotEmpty) 'notes': notes!,
      if (nextCheckDate != null && nextCheckDate!.isNotEmpty)
        'next_check_date': nextCheckDate!,
      'currentUser': 'FlutterApp',
    };
  }

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'excellent':
        return Colors.green;
      case 'good':
        return Colors.blue;
      case 'satisfactory':
        return Colors.orange;
      case 'needs_improvement':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String get statusDisplay {
    return status.replaceAll('_', ' ').toUpperCase();
  }

  String get formattedDate {
    try {
      DateTime date = DateTime.parse(reportDate);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return reportDate;
    }
  }
}

class CleanReportPhoto {
  final int id;
  final String reportId;
  final String filename;
  final String originalName;
  final int fileSize;
  final String fileType;
  final String photoUrl;

  CleanReportPhoto({
    required this.id,
    required this.reportId,
    required this.filename,
    required this.originalName,
    required this.fileSize,
    required this.fileType,
    required this.photoUrl,
  });

  factory CleanReportPhoto.fromJson(Map<String, dynamic> json) {
    return CleanReportPhoto(
      id: json['id'] ?? 0,
      reportId: json['report_id'] ?? '',
      filename: json['filename'] ?? '',
      originalName: json['original_name'] ?? '',
      fileSize: json['file_size'] ?? 0,
      fileType: json['file_type'] ?? '',
      photoUrl: json['photo_url'] ?? '',
    );
  }
}

// =============================================================================
// 2. API SERVICE
// =============================================================================
class ApiService {
  static String baseUrl = 'http://192.168.0.139:3000';
  static String get apiUrl => '$baseUrl/api';

  static Map<String, String> getHeaders() {
    return {'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  static Future<void> initializeBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final storeManagementIp = prefs.getString('storeManagementIp');
    if (storeManagementIp != null && storeManagementIp.isNotEmpty) {
      baseUrl = 'http://$storeManagementIp:3000';
    }
  }

  static Future<List<dynamic>> getCleanReports({String? search}) async {
    await initializeBaseUrl();
    try {
      final response = await http.get(
        Uri.parse(
          '$apiUrl/clean-reports${search != null ? '?search=$search' : ''}',
        ),
        headers: getHeaders(),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load clean reports: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load clean reports: $e');
    }
  }

  static Future<Map<String, dynamic>> createCleanReport({
    required Map<String, dynamic> data,
    required List<XFile> photos,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiUrl/clean-reports'),
      );

      request.fields['ot_name'] = data['ot_name'];
      request.fields['report_date'] = data['report_date'];
      request.fields['report_time'] = data['report_time'];
      request.fields['verified_by'] = data['verified_by'];
      request.fields['status'] = data['status'];
      request.fields['currentUser'] = data['currentUser'];

      if (data['notes'] != null && data['notes'].isNotEmpty) {
        request.fields['notes'] = data['notes'];
      }

      if (data['next_check_date'] != null &&
          data['next_check_date'].isNotEmpty) {
        request.fields['next_check_date'] = data['next_check_date'];
      }

      int photoCount = 0;
      for (var photo in photos) {
        if (photoCount >= 10) break;

        var file = await http.MultipartFile.fromPath(
          'photos',
          photo.path,
          filename: path.basename(photo.path),
          contentType: MediaType('image', 'jpeg'),
        );
        request.files.add(file);
        photoCount++;
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception(
          'Failed to create clean report: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Failed to create clean report: $e');
    }
  }

  static Future<bool> deleteCleanReport(String id, String currentUser) async {
    try {
      final response = await http.delete(
        Uri.parse('$apiUrl/clean-reports/$id?currentUser=$currentUser'),
        headers: getHeaders(),
      );

      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Failed to delete clean report: $e');
    }
  }
}

// =============================================================================
// 3. CAMERA MANAGER
// =============================================================================
class CameraManager {
  static List<CameraDescription>? _cameras;
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isTakingPhoto = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isTakingPhoto => _isTakingPhoto;

  Future<void> initialize() async {
    try {
      if (_cameras == null) {
        _cameras = await availableCameras();
      }

      if (_cameras!.isEmpty) {
        throw Exception('No cameras found');
      }

      if (_controller != null) {
        await _controller!.dispose();
      }

      _controller = CameraController(
        _cameras![0],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;
    } catch (e) {
      print("Camera initialization error: $e");
      _isInitialized = false;
    }
  }

  Future<XFile?> takePhoto() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isTakingPhoto) {
      return null;
    }

    _isTakingPhoto = true;
    try {
      final photo = await _controller!.takePicture();
      return photo;
    } catch (e) {
      print("Error taking photo: $e");
      return null;
    } finally {
      _isTakingPhoto = false;
    }
  }

  Future<void> dispose() async {
    _isInitialized = false;
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
  }
}

// =============================================================================
// 4. MAIN WIDGET - OPTIMIZED
// =============================================================================
class CleanControlApp extends StatefulWidget {
  @override
  _CleanControlAppState createState() => _CleanControlAppState();
}

class _CleanControlAppState extends State<CleanControlApp>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  static const Color _primaryColor = Color.fromARGB(255, 44, 16, 90);
  static const Color _accentColor = Color.fromARGB(255, 68, 49, 127);
  // Form controllers
  final TextEditingController _otNameController = TextEditingController();
  final TextEditingController _verifiedByController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  String _selectedStatus = 'satisfactory';

  final List<String> _statusOptions = [
    'excellent',
    'good',
    'satisfactory',
    'needs_improvement',
  ];

  final List<String> _disinfectantOptions = [
    '--',
    'Hospital-grade',
    'Chlorine/Quaternary',
    'As per manual',
    'Alcohol/EPA approved',
    'Soap/Alcohol rub',
  ];

  late List<CleaningProtocolItem> _protocolItems;

  final CameraManager _cameraManager = CameraManager();
  final ImagePicker _imagePicker = ImagePicker();

  List<XFile> _selectedPhotos = [];
  XFile? _currentCapturedImage;
  bool _showCameraPreview = false;
  String? _usbPath;
  bool _usbConnected = false;
  String _cleanSnapshotPath = '';

  List<CleanReport> _reports = [];
  bool _isLoading = false;
  String _error = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;

  bool _showReports = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initProtocolItems();
    _initializeApp();
  }

  void _initProtocolItems() {
    _protocolItems = [
      CleaningProtocolItem(
        serialNo: 1,
        activity: 'Remove soiled linen/waste',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 2,
        activity: 'Clean & disinfect high-touch surfaces',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 3,
        activity: 'Clean & disinfect door knobs, switches',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 4,
        activity: 'Sweep & mop floor',
        areaEquipment: 'Floor (1.5 m from table)',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 5,
        activity: 'Clean & disinfect anesthesia machine/carts',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 6,
        activity: 'Clean & disinfect patient monitors/IV poles',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 7,
        activity: 'Clean positioners, arm boards, stirrups',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 8,
        activity: 'Change bin liners',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 9,
        activity: 'Perform hand hygiene after cleaning',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 10,
        activity: 'Ventilate room',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
      CleaningProtocolItem(
        serialNo: 11,
        activity: 'Final walkthrough & checklist completion',
        areaEquipment: '--',
        selectedDisinfectant: '--',
      ),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _otNameController.dispose();
    _verifiedByController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    _searchTimer?.cancel();
    _cameraManager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraManager.controller == null ||
        !_cameraManager.controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraManager.dispose();
    } else if (state == AppLifecycleState.resumed && _showCameraPreview) {
      _initializeCamera();
    }
  }

  Future<void> _initializeApp() async {
    await _requestPermissions();
    await _loadUSBPath();
    if (_showReports) {
      _fetchCleanReports();
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.storage, Permission.camera].request();
  }

  Future<void> _loadUSBPath() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString("usbPath");
    if (savedPath != null && Directory(savedPath).existsSync()) {
      setState(() {
        _usbPath = savedPath;
        _usbConnected = true;
        _cleanSnapshotPath = path.join(_usbPath!, 'Clean', 'Snapshot');
      });
      await _createCleanSnapshotFolder();
    }
  }

  Future<void> _createCleanSnapshotFolder() async {
    try {
      if (_cleanSnapshotPath.isNotEmpty) {
        Directory cleanSnapshotDir = Directory(_cleanSnapshotPath);
        if (!await cleanSnapshotDir.exists()) {
          await cleanSnapshotDir.create(recursive: true);
        }
      }
    } catch (e) {
      print('Error creating folder: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraManager.initialize();
      if (mounted && _cameraManager.isInitialized) {
        setState(() {});
      }
    } catch (e) {
      print("Camera init error: $e");
    }
  }

  Future<void> _startCamera() async {
    if (_showCameraPreview) return;

    setState(() {
      _showCameraPreview = true;
      _currentCapturedImage = null;
    });

    await _initializeCamera();
  }

  Future<void> _takePhoto() async {
    if (!_usbConnected) {
      _showSnackBar('Please select USB storage first', Colors.orange);
      return;
    }

    final photo = await _cameraManager.takePhoto();
    if (photo != null) {
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String fileName = 'Room_Cleanliness_$timestamp.jpg';
      String newPath = path.join(_cleanSnapshotPath, fileName);

      await File(photo.path).copy(newPath);

      try {
        await File(photo.path).delete();
      } catch (e) {
        print('Could not delete temp file: ${photo.path}');
      }

      final savedImage = XFile(newPath);
      setState(() {
        _currentCapturedImage = savedImage;
        _selectedPhotos.add(savedImage);
        _showCameraPreview = false;
      });

      _showSnackBar('Photo saved to USB', Colors.green);
    }
  }

  void _retakePhoto() {
    setState(() {
      _currentCapturedImage = null;
      _showCameraPreview = true;
    });
  }

  void _cancelCamera() {
    setState(() {
      _showCameraPreview = false;
    });
  }

  Future<void> selectUSBDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        setState(() {
          _usbPath = selectedDirectory;
          _usbConnected = true;
          _cleanSnapshotPath = path.join(_usbPath!, 'Clean', 'Snapshot');
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("usbPath", selectedDirectory);

        await _createCleanSnapshotFolder();

        _showSnackBar(
          'USB Storage Selected: ${path.basename(selectedDirectory)}',
          Colors.green,
        );
      }
    } catch (e) {
      _showSnackBar('Failed to select USB storage', Colors.red);
    }
  }

  Future<void> _fetchCleanReports({String? search}) async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final data = await ApiService.getCleanReports(search: search);
      setState(() {
        _reports = data.map((json) => CleanReport.fromJson(json)).toList();
        _reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 500), () {
      _fetchCleanReports(search: value);
    });
  }

  Future<void> _submitCompleteReport() async {
    if (_otNameController.text.isEmpty) {
      _showSnackBar('Please enter OT name', Colors.red);
      return;
    }

    if (_verifiedByController.text.isEmpty) {
      _showSnackBar('Please enter verifier name', Colors.red);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final report = _generateReportFromProtocol();
      final result = await ApiService.createCleanReport(
        data: report.toFormData(),
        photos: _selectedPhotos,
      );

      // Clear form
      _otNameController.clear();
      _verifiedByController.clear();
      _notesController.clear();
      _selectedPhotos.clear();

      // Reset protocol
      for (var item in _protocolItems) {
        item.isSignedOff = false;
        item.areaEquipment = '--';
        item.selectedDisinfectant = '--';
      }

      _showSnackBar('Clean report submitted successfully!', Colors.green);
      _showReportsView();
    } catch (e) {
      _showSnackBar('Failed to submit report: $e', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  CleanReport _generateReportFromProtocol() {
    int completed = _protocolItems.where((item) => item.isSignedOff).length;
    int total = _protocolItems.length;

    String calculatedStatus = _selectedStatus;
    if (completed == total) {
      calculatedStatus = 'excellent';
    } else if (completed >= total * 0.8) {
      calculatedStatus = 'good';
    } else if (completed >= total * 0.6) {
      calculatedStatus = 'satisfactory';
    } else {
      calculatedStatus = 'needs_improvement';
    }

    String protocolNotes = _notesController.text;
    protocolNotes += '\n\nCOMPLETION: $completed/$total activities';

    return CleanReport(
      reportId: '',
      otName: _otNameController.text,
      reportDate: DateTime.now().toIso8601String().split('T')[0],
      reportTime:
          '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      verifiedBy: _verifiedByController.text,
      status: calculatedStatus,
      notes: protocolNotes.trim(),
      nextCheckDate: DateTime.now()
          .add(Duration(days: 7))
          .toIso8601String()
          .split('T')[0],
      createdAt: DateTime.now(),
      photoCount: _selectedPhotos.length,
      photos: [],
    );
  }

  Future<bool> _deleteCleanReport(String reportId) async {
    try {
      final success = await ApiService.deleteCleanReport(
        reportId,
        'FlutterApp',
      );
      if (success) {
        setState(() {
          _reports.removeWhere((report) => report.reportId == reportId);
        });
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  void _showReportsView() {
    setState(() {
      _showReports = true;
    });
    _fetchCleanReports();
  }

  void _showAssessmentView() {
    setState(() {
      _showReports = false;
    });
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: _primaryColor,
      appBar: AppBar(
        backgroundColor: _accentColor,
        title: Text(
          _showReports ? "Clean Reports" : "Room Cleanliness",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          if (!_showReports)
            IconButton(
              icon: Icon(Icons.list, color: Colors.white),
              onPressed: _showReportsView,
              tooltip: 'View Reports',
            ),
          if (_showReports)
            IconButton(
              icon: Icon(Icons.add),
              onPressed: _showAssessmentView,
              tooltip: 'New Assessment',
            ),
          IconButton(
            icon: Icon(
              _usbConnected ? Icons.usb : Icons.usb_off,
              color: _usbConnected ? Colors.greenAccent : Colors.orangeAccent,
            ),
            onPressed: selectUSBDirectory,
            tooltip: 'USB Storage',
          ),
        ],
      ),
      body: _showReports ? _buildReportsView() : _buildAssessmentView(),
    );
  }

  Widget _buildAssessmentView() {
    return Row(
      children: [
        // Left Panel - Form and Camera
        Expanded(
          flex: 1,
          child: Container(color: Colors.white, child: _buildFormPanel()),
        ),

        // Right Panel - Protocol Table
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[100],
            child: _buildProtocolPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildFormPanel() {
    return Container(
      color: Color.fromARGB(255, 44, 16, 90),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),

            TextField(
              controller: _otNameController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'OT Name *',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white70),
                ),
                prefixIcon: Icon(Icons.business, color: Colors.white70),
              ),
            ),
            SizedBox(height: 12),

            TextField(
              controller: _verifiedByController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Verified By *',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white70),
                ),
                prefixIcon: Icon(Icons.person, color: Colors.white70),
              ),
            ),
            SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _selectedStatus,
              dropdownColor: _accentColor,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Overall Status *',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white70),
                ),
                prefixIcon: Icon(Icons.star, color: Colors.white70),
              ),
              items: _statusOptions.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(
                    value.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() => _selectedStatus = newValue ?? 'satisfactory');
              },
            ),
            SizedBox(height: 12),

            TextField(
              controller: _notesController,
              maxLines: 3,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Additional Notes',
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white70),
                ),
                alignLabelWithHint: true,
              ),
            ),
            SizedBox(height: 24),

            Text(
              'Camera (${_selectedPhotos.length} photos)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 12),

            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: _buildCameraArea(),
            ),
            SizedBox(height: 16),

            if (!_showCameraPreview && _usbConnected)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startCamera,
                  icon: Icon(Icons.camera_alt),
                  label: Text('Start Camera'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _primaryColor,
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

            if (_showCameraPreview)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _cancelCamera,
                  icon: Icon(Icons.cancel),
                  label: Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

            SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitCompleteReport,
                icon: Icon(Icons.cloud_upload),
                label: Text(_isLoading ? 'Submitting...' : 'Submit Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _primaryColor,
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraArea() {
    if (_showCameraPreview) {
      if (_cameraManager.isInitialized && _cameraManager.controller != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned.fill(child: CameraPreview(_cameraManager.controller!)),
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: FloatingActionButton(
                    onPressed: _takePhoto,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    child: Icon(Icons.camera, size: 32),
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        return Center(child: CircularProgressIndicator(color: Colors.white));
      }
    } else if (_currentCapturedImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.file(
                File(_currentCapturedImage!.path),
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  FloatingActionButton.small(
                    onPressed: () {
                      _showSnackBar('Photo added', Colors.green);
                      setState(() {
                        _currentCapturedImage = null;
                      });
                    },
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.green,
                    child: Icon(Icons.check),
                  ),
                  SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed: _retakePhoto,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.orange,
                    child: Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera, size: 64, color: Colors.white60),
            SizedBox(height: 16),
            Text('Ready for Photos', style: TextStyle(color: Colors.white70)),
            if (!_usbConnected) ...[
              SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: selectUSBDirectory,
                icon: Icon(Icons.usb),
                label: Text('Select USB Storage'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.orange,
                ),
              ),
            ],
          ],
        ),
      );
    }
  }

  Widget _buildProtocolPanel() {
    int completed = _protocolItems.where((item) => item.isSignedOff).length;
    int total = _protocolItems.length;

    return Container(
      color: Color.fromARGB(255, 44, 16, 90),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            color: _primaryColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cleaning Protocol Checklist',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Chip(
                  label: Text(
                    '$completed/$total completed',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: completed == total
                      ? Colors.green
                      : Colors.blue,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(8),
              itemCount: _protocolItems.length,
              itemBuilder: (context, index) {
                return _ProtocolItemCard(
                  item: _protocolItems[index],
                  disinfectantOptions: _disinfectantOptions,
                  onChanged: () => setState(() {}),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Search reports...',
              labelStyle: TextStyle(color: Colors.white70),
              prefixIcon: Icon(Icons.search, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white70),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: Colors.white70),
                      onPressed: () {
                        _searchController.clear();
                        _fetchCleanReports();
                      },
                    )
                  : null,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        Expanded(
          child: _isLoading && _reports.isEmpty
              ? Center(child: CircularProgressIndicator(color: Colors.white))
              : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, color: Colors.white, size: 48),
                      SizedBox(height: 16),
                      Text(
                        'Error: $_error',
                        style: TextStyle(color: Colors.white),
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _fetchCleanReports(),
                        child: Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _primaryColor,
                        ),
                      ),
                    ],
                  ),
                )
              : _reports.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description, size: 64, color: Colors.white70),
                      SizedBox(height: 16),
                      Text(
                        'No clean reports found',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _reports.length,
                  itemBuilder: (context, index) {
                    return _ReportCard(
                      report: _reports[index],
                      onDelete: () => _showDeleteDialog(_reports[index]),
                      onView: () => _showReportDetails(_reports[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showReportDetails(CleanReport report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clean Report Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow('OT Name', report.otName),
              _DetailRow('Report ID', report.reportId),
              _DetailRow('Date', report.formattedDate),
              _DetailRow('Time', report.reportTime),
              _DetailRow('Verified By', report.verifiedBy),
              _DetailRow('Status', report.statusDisplay),
              if (report.nextCheckDate != null)
                _DetailRow('Next Check', report.nextCheckDate!),
              if (report.notes != null && report.notes!.isNotEmpty) ...[
                SizedBox(height: 16),
                Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(report.notes!),
                ),
              ],
              SizedBox(height: 16),
              Text(
                'Photos: ${report.photoCount}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(CleanReport report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Report'),
        content: Text('Delete report for ${report.otName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final success = await _deleteCleanReport(report.reportId);
              if (success) {
                _showSnackBar('Report deleted', Colors.green);
              } else {
                _showSnackBar('Failed to delete', Colors.red);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// OPTIMIZED WIDGETS
// =============================================================================
class _ProtocolItemCard extends StatelessWidget {
  final CleaningProtocolItem item;
  final List<String> disinfectantOptions;
  final VoidCallback onChanged;

  const _ProtocolItemCard({
    required this.item,
    required this.disinfectantOptions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      elevation: 0, // No shadow for a smooth glass effect
      color: Colors.white.withOpacity(0.1), // 🔥 Same style as your TextField
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white70), // Light border like example
      ),
      child: ExpansionTile(
        collapsedIconColor: Colors.white,
        iconColor: Colors.white,
        leading: Checkbox(
          value: item.isSignedOff,
          activeColor: Colors.white,
          checkColor: Colors.black,
          side: BorderSide(color: Colors.white70),
          onChanged: (bool? value) {
            item.isSignedOff = value ?? false;
            onChanged();
          },
        ),
        title: Text(
          '${item.serialNo}. ${item.activity}',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.white, // White text for dark backgrounds
          ),
        ),
        subtitle: Text(
          item.isSignedOff ? '✓ Completed' : 'Pending',
          style: TextStyle(
            color: item.isSignedOff ? Colors.greenAccent : Colors.orangeAccent,
            fontSize: 12,
          ),
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: TextEditingController(text: item.areaEquipment),
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Area/Equipment',
                    labelStyle: TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white70),
                    ),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    item.areaEquipment = value;
                    onChanged();
                  },
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: item.selectedDisinfectant,
                  dropdownColor: Colors.black87,
                  decoration: InputDecoration(
                    labelText: 'Disinfectant',
                    labelStyle: TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white70),
                    ),
                    isDense: true,
                  ),
                  items: disinfectantOptions.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value, style: TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    item.selectedDisinfectant = newValue ?? '--';
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final CleanReport report;
  final VoidCallback onDelete;
  final VoidCallback onView;

  const _ReportCard({
    required this.report,
    required this.onDelete,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: report.statusColor,
          child: Text(
            report.otName.substring(0, 1).toUpperCase(),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          report.otName,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text('Date: ${report.formattedDate}'),
            Text('Time: ${report.reportTime}'),
            Text('Verified: ${report.verifiedBy}'),
            SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  label: Text(
                    report.statusDisplay,
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                  backgroundColor: report.statusColor,
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (report.photoCount > 0) ...[
                  SizedBox(width: 8),
                  Icon(Icons.photo_library, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Text('${report.photoCount}', style: TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'view') {
              onView();
            } else if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 20),
                  SizedBox(width: 8),
                  Text('View'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: onView,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
