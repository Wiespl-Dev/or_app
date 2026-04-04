// ==================== PROVIDER MODELS ====================

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wiespl_contrl_panel/provider/orpi/orscreenpi.dart' show Patient;

class VideoSwitcherProvider extends ChangeNotifier {
  // Basic state
  int _selectedVideoIndex = 0;
  bool _isConnected = false;
  bool _isFullScreen = false;
  String? _usbPath;
  bool _usbConnected = false;
  GlobalKey repaintKey = GlobalKey();
  List<String> _capturedFiles = [];
  int _selectedStreamIndex = 0;

  // Recording state
  bool _isRecording = false;
  bool _isLoading = true;
  bool _isConverting = false;
  String? _recordingPath;
  CancelToken? _cancelToken;
  IOSink? _fileSink;
  int _bytesDownloaded = 0;
  DateTime? _recordingStartTime;
  Timer? _uiTimer;
  double _conversionProgress = 0.0;

  // Patient related
  List<Patient> _patientsList = [];
  bool _isLoadingPatients = false;
  String _patientError = '';
  bool _serverOnline = false;
  String _currentIp = '';

  // Camera related
  String _cameraIp = "";
  List<Map<String, dynamic>> _cctvList = [];

  // WebView controller - CHANGED from 'late' to nullable
  WebViewController? _obsController;

  // Text controllers
  final TextEditingController messageController = TextEditingController();
  bool _isSending = false;
  String? _lastStatus;
  String? _lastSid;

  // ==================== GETTER METHODS ====================
  int get selectedVideoIndex => _selectedVideoIndex;
  bool get isConnected => _isConnected;
  bool get isFullScreen => _isFullScreen;
  String? get usbPath => _usbPath;
  bool get usbConnected => _usbConnected;
  List<String> get capturedFiles => List.unmodifiable(_capturedFiles);
  int get selectedStreamIndex => _selectedStreamIndex;
  bool get isRecording => _isRecording;
  bool get isLoading => _isLoading;
  bool get isConverting => _isConverting;
  String? get recordingPath => _recordingPath;
  CancelToken? get cancelToken => _cancelToken;
  IOSink? get fileSink => _fileSink;
  int get bytesDownloaded => _bytesDownloaded;
  DateTime? get recordingStartTime => _recordingStartTime;
  double get conversionProgress => _conversionProgress;
  List<Patient> get patientsList => List.unmodifiable(_patientsList);
  bool get isLoadingPatients => _isLoadingPatients;
  String get patientError => _patientError;
  bool get serverOnline => _serverOnline;
  String get currentIp => _currentIp;
  String get cameraIp => _cameraIp;
  List<Map<String, dynamic>> get cctvList => List.unmodifiable(_cctvList);

  // Updated Getter
  WebViewController? get obsController => _obsController;

  // Safety Helper
  bool get isControllerInitialized => _obsController != null;

  bool get isSending => _isSending;
  String? get lastStatus => _lastStatus;
  String? get lastSid => _lastSid;

  // ==================== SETTER METHODS ====================

  void setSelectedVideoIndex(int index) {
    _selectedVideoIndex = index;
    notifyListeners();
  }

  void setIsRecording(bool value) {
    _isRecording = value;
    notifyListeners();
  }

  void setIsLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void setIsConverting(bool value) {
    _isConverting = value;
    notifyListeners();
  }

  void setRecordingPath(String? path) {
    _recordingPath = path;
    notifyListeners();
  }

  void setCancelToken(CancelToken? token) {
    _cancelToken = token;
  }

  void setFileSink(IOSink? sink) {
    _fileSink = sink;
  }

  void setBytesDownloaded(int bytes) {
    _bytesDownloaded = bytes;
    notifyListeners();
  }

  void setRecordingStartTime(DateTime? time) {
    _recordingStartTime = time;
    notifyListeners();
  }

  void setUiTimer(Timer? timer) {
    _uiTimer?.cancel();
    _uiTimer = timer;
  }

  void setConversionProgress(double progress) {
    _conversionProgress = progress;
    notifyListeners();
  }

  void setIsConnected(bool value) {
    _isConnected = value;
    notifyListeners();
  }

  void setIsFullScreen(bool value) {
    _isFullScreen = value;
    notifyListeners();
  }

  void setUsbPath(String? path) {
    _usbPath = path;
    notifyListeners();
  }

  void setUsbConnected(bool value) {
    _usbConnected = value;
    notifyListeners();
  }

  void setSelectedStreamIndex(int index) {
    _selectedStreamIndex = index;
    notifyListeners();
  }

  void setPatientsList(List<Patient> patients) {
    _patientsList = patients;
    notifyListeners();
  }

  void setIsLoadingPatients(bool value) {
    _isLoadingPatients = value;
    notifyListeners();
  }

  void setPatientError(String error) {
    _patientError = error;
    notifyListeners();
  }

  void setServerOnline(bool value) {
    _serverOnline = value;
    notifyListeners();
  }

  void setCurrentIp(String ip) {
    _currentIp = ip;
    notifyListeners();
  }

  void setCameraIp(String ip) {
    _cameraIp = ip;
    notifyListeners();
  }

  void setCctvList(List<Map<String, dynamic>> list) {
    _cctvList = list;
    notifyListeners();
  }

  // Updated Setter
  void setObsController(WebViewController controller) {
    _obsController = controller;
    notifyListeners();
  }

  void setIsSending(bool value) {
    _isSending = value;
    notifyListeners();
  }

  void setLastStatus(String? status) {
    _lastStatus = status;
    notifyListeners();
  }

  void setLastSid(String? sid) {
    _lastSid = sid;
    notifyListeners();
  }

  void addCapturedFile(String filePath) {
    _capturedFiles.add(filePath);
    notifyListeners();
  }

  void removeCapturedFile(String filePath) {
    _capturedFiles.remove(filePath);
    notifyListeners();
  }

  void clearCapturedFiles() {
    _capturedFiles.clear();
    notifyListeners();
  }

  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    notifyListeners();
  }

  void cancelRecording() {
    _cancelToken?.cancel("Recording stopped by user");
    _cancelToken = null;
  }

  void closeFileSink() async {
    try {
      await _fileSink?.flush();
      await _fileSink?.close();
    } catch (e) {
      debugPrint("Error closing file sink: $e");
    } finally {
      _fileSink = null;
    }
  }

  void clearRecordingState() {
    _isRecording = false;
    _recordingPath = null;
    _bytesDownloaded = 0;
    _recordingStartTime = null;
    _uiTimer?.cancel();
    _uiTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _cancelToken?.cancel();
    closeFileSink();
    messageController.dispose();
    super.dispose();
  }
}
