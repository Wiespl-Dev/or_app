import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wiespl_contrl_panel/main.dart';
import 'package:http_parser/http_parser.dart'; // ADD
// REMOVE THIS - it's already defined in main.dart
// enum ORViewMode { dashboard, orMode }

class ORSystemProvider extends ChangeNotifier {
  bool _isSystemOn = true;
  double _temp = 22.5;
  double _rh = 45.0;
  DateTime _now = DateTime.now();

  ORViewMode _viewMode = ORViewMode.dashboard;

  bool _showMusic = false;
  bool _showTempSettings = false;
  bool _showHumiditySettings = false;
  bool _showRightPanelFlip = false;
  bool _showMGPSFlip = false;

  final List<bool> _lights = [true, false, false, true];
  int _seconds = 0;
  Timer? _stopwatchTimer;
  bool _timerRunning = false;

  // Music Player State
  bool _isMusicPlaying = false;
  int _currentTrackIndex = 0;
  Duration _currentPosition = Duration.zero;

  // Tab selection: 0 = Server Music, 1 = Asset Music
  int _musicTabIndex = 0;

  // Server configuration
  String _serverUrl = 'http://192.168.0.137:3000';

  // Server music list
  List<Map<String, dynamic>> _serverMusicList = [];
  bool _isLoadingServerMusic = false;

  final AudioPlayer _audioPlayer = AudioPlayer();

  // Asset playlist (built-in music)
  final List<Map<String, dynamic>> _assetPlaylist = [
    {
      "title": "He Ram He Ram",
      "asset": "music/He Ram He Ram-320kbps.mp3",
      "type": "asset",
    },
    {
      "title": "Mahamrityunjay Mantra",
      "asset":
          "music/Mahamrityunjay Mantra महमतयजय मतर Om Trayambakam Yajamahe.mp3",
      "type": "asset",
    },
    {
      "title": "Shiv Namaskarartha Mantra",
      "asset":
          "music/Shiv Namaskarartha Mantra  Monday Special  LoFi Version.mp3",
      "type": "asset",
    },
    {
      "title": "Sri Venkatesha Stotram",
      "asset":
          "music/Sri Venkatesha Stotram - Invoking the Lord's Mercy _ New Year 2025.mp3",
      "type": "asset",
    },
    {
      "title": "Sri Venkateshwara Suprabhatham",
      "asset": "music/Sri Venkateshwara Suprabhatham-320kbps.mp3",
      "type": "asset",
    },
    {
      "title": "Hanuman Chalisa",
      "asset":
          "music/शर हनमन चलस  Shree Hanuman Chalisa Original Video  GULSHAN KUMAR  HARIHARAN Full HD.mp3",
      "type": "asset",
    },
  ];

  ORSystemProvider() {
    _initProvider();
  }

  Future<void> _initProvider() async {
    await _loadServerUrl();
    Timer.periodic(const Duration(seconds: 1), (t) {
      _now = DateTime.now();
      notifyListeners();
    });

    _audioPlayer.onPositionChanged.listen((position) {
      _currentPosition = position;
      notifyListeners();
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      _isMusicPlaying = state == PlayerState.playing;
      notifyListeners();
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      _isMusicPlaying = false;
      _currentPosition = Duration.zero;
      nextTrack();
    });
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('storeManagementIp');
    if (ip != null && ip.isNotEmpty) {
      _serverUrl = 'http://$ip:3000';
    }
  }

  // ==================== GETTERS ====================
  bool get isSystemOn => _isSystemOn;
  double get temp => _temp;
  double get rh => _rh;
  DateTime get now => _now;
  bool get timerRunning => _timerRunning;
  List<bool> get lights => _lights;
  bool get showMusic => _showMusic;
  bool get showTempSettings => _showTempSettings;
  bool get showHumiditySettings => _showHumiditySettings;
  bool get showRightPanelFlip => _showRightPanelFlip;
  bool get showMGPSFlip => _showMGPSFlip;
  bool get isMusicPlaying => _isMusicPlaying;
  ORViewMode get viewMode => _viewMode;
  int get musicTabIndex => _musicTabIndex;
  int get currentTrackIndex => _currentTrackIndex;
  Duration get currentPosition => _currentPosition;
  String get serverUrl => _serverUrl;
  List<Map<String, dynamic>> get serverMusicList => _serverMusicList;
  bool get isLoadingServerMusic => _isLoadingServerMusic;

  List<Map<String, dynamic>> get currentPlaylist {
    return _musicTabIndex == 0 ? _serverMusicList : _assetPlaylist;
  }

  String get currentTrack {
    final playlist = currentPlaylist;
    if (playlist.isEmpty || _currentTrackIndex >= playlist.length) {
      return 'No track selected';
    }
    return playlist[_currentTrackIndex]['title'] ??
        playlist[_currentTrackIndex]['name'] ??
        'Unknown';
  }

  bool get isCurrentTrackServer => _musicTabIndex == 0;

  String get formattedFullDate =>
      DateFormat('EEEE, dd/MM/yyyy').format(_now).toUpperCase();

  String get stopwatchDisplay {
    Duration d = Duration(seconds: _seconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds % 60)}";
  }

  // ==================== SERVER MUSIC METHODS ====================

  Future<void> fetchServerMusic() async {
    _isLoadingServerMusic = true;
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse('$_serverUrl/api/music'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          _serverMusicList = data.map((item) {
            return {
              'id': item['id'] ?? 0,
              'title': item['name'] ?? 'Unknown',
              'name': item['name'] ?? 'Unknown',
              'filename': item['filename'] ?? '',
              'url': '$_serverUrl/uploads/music/${item['filename']}',
              'file_size': item['file_size'] ?? 0,
              'type': 'server',
            };
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching server music: $e');
    }

    _isLoadingServerMusic = false;
    notifyListeners();
  }

  Future<void> deleteServerMusic(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$_serverUrl/api/music/$id'),
      );

      if (response.statusCode == 200) {
        _serverMusicList.removeWhere((m) => m['id'] == id);

        if (_musicTabIndex == 0 &&
            _currentTrackIndex < _serverMusicList.length &&
            _serverMusicList.isNotEmpty &&
            _serverMusicList[_currentTrackIndex]['id'] == id) {
          await _audioPlayer.stop();
          _isMusicPlaying = false;
          _currentPosition = Duration.zero;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error deleting music: $e');
    }
  }

  // ==================== MUSIC CONTROLS ====================

  void setMusicTab(int index) {
    _musicTabIndex = index;
    if (index == 0 && _serverMusicList.isEmpty) {
      fetchServerMusic();
    }
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    final playlist = currentPlaylist;
    if (playlist.isEmpty) return;

    if (_isMusicPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_currentPosition.inSeconds > 0) {
        await _audioPlayer.resume();
      } else {
        await _playCurrentTrack();
      }
    }
  }

  Future<void> _playCurrentTrack() async {
    try {
      final playlist = currentPlaylist;
      if (playlist.isEmpty || _currentTrackIndex >= playlist.length) return;

      final track = playlist[_currentTrackIndex];
      await _audioPlayer.stop();
      _currentPosition = Duration.zero;

      if (track['type'] == 'server') {
        debugPrint("▶ Playing server: ${track['url']}");
        await _audioPlayer.play(UrlSource(track['url']));
      } else {
        debugPrint("▶ Playing asset: ${track['asset']}");
        await _audioPlayer.play(AssetSource(track['asset']));
      }
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  void playTrackAtIndex(int index) {
    final playlist = currentPlaylist;
    if (index >= 0 && index < playlist.length) {
      _currentTrackIndex = index;
      _playCurrentTrack();
    }
  }

  void nextTrack() {
    final playlist = currentPlaylist;
    if (playlist.isEmpty) return;

    _currentTrackIndex = (_currentTrackIndex + 1) % playlist.length;
    _playCurrentTrack();
  }

  void prevTrack() {
    final playlist = currentPlaylist;
    if (playlist.isEmpty) return;

    _currentTrackIndex = (_currentTrackIndex - 1 < 0)
        ? playlist.length - 1
        : _currentTrackIndex - 1;
    _playCurrentTrack();
  }

  Future<void> stopMusic() async {
    await _audioPlayer.stop();
    _isMusicPlaying = false;
    _currentPosition = Duration.zero;
    notifyListeners();
  }

  // ==================== UI TOGGLES ====================

  void setViewMode(ORViewMode mode) {
    _viewMode = mode;
    notifyListeners();
  }

  void toggleMusicFlip() {
    _showMusic = !_showMusic;
    if (_showMusic && _serverMusicList.isEmpty) {
      fetchServerMusic();
    }
    notifyListeners();
  }

  void toggleTempFlip() {
    _showTempSettings = !_showTempSettings;
    notifyListeners();
  }
  // ==================== UPLOAD MUSIC ====================

  Future<void> uploadMusic() async {
    try {
      // Use image_picker to pick media files
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickMedia();

      if (file == null) return;

      final bytes = await file.readAsBytes();
      String fileName = file.name;

      // Force .mp3 extension
      if (!fileName.toLowerCase().endsWith('.mp3')) {
        fileName = '${fileName.split('.').first}.mp3';
      }

      if (bytes.length > 60 * 1024 * 1024) {
        debugPrint('File too large (max 60MB)');
        return;
      }

      // Show name dialog
      String? musicName = await _showMusicNameDialog(fileName);

      if (musicName == null || musicName.isEmpty) return;

      // Upload to server
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_serverUrl/api/music'),
      );
      request.fields['name'] = musicName;
      request.files.add(
        http.MultipartFile.fromBytes(
          'music',
          bytes,
          filename: fileName,
          contentType: MediaType('audio', 'mpeg'),
        ),
      );

      final response = await request.send();

      if (response.statusCode == 200) {
        debugPrint('Upload successful');
        // Refresh the music list
        await fetchServerMusic();
      } else {
        debugPrint('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    }
  }

  Future<String?> _showMusicNameDialog(String defaultName) async {
    // Since this is in provider, we need a BuildContext
    // You can pass context from the widget or use a global navigator key
    // For simplicity, return default name without extension
    return defaultName.split('.').first;
  }

  void toggleHumidityFlip() {
    _showHumiditySettings = !_showHumiditySettings;
    notifyListeners();
  }

  void toggleRightPanelFlip() {
    _showRightPanelFlip = !_showRightPanelFlip;
    notifyListeners();
  }

  void toggleMGPSFlip() {
    _showMGPSFlip = !_showMGPSFlip;
    notifyListeners();
  }

  void adjustTemp(double delta) {
    _temp += delta;
    notifyListeners();
  }

  void adjustHumidity(double delta) {
    _rh = (_rh + delta).clamp(0, 100);
    notifyListeners();
  }

  void toggleSystem() {
    _isSystemOn = !_isSystemOn;
    if (!_isSystemOn) {
      _audioPlayer.stop();
      resetStopwatch();
    }
    notifyListeners();
  }

  void toggleLight(int index) {
    _lights[index] = !_lights[index];
    notifyListeners();
  }

  // ==================== STOPWATCH ====================

  void toggleStopwatch() {
    _timerRunning = !_timerRunning;
    if (_timerRunning) {
      _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        _seconds++;
        notifyListeners();
      });
    } else {
      _stopwatchTimer?.cancel();
    }
    notifyListeners();
  }

  void resetStopwatch() {
    _seconds = 0;
    _timerRunning = false;
    _stopwatchTimer?.cancel();
    notifyListeners();
  }

  // ==================== DISPOSE ====================

  @override
  void dispose() {
    _audioPlayer.dispose();
    _stopwatchTimer?.cancel();
    super.dispose();
  }
}
