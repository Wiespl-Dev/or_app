import 'package:flutter/material.dart';

import 'dart:async';

import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart'; // FIX: switched from just_audio to audioplayers
import 'package:wiespl_contrl_panel/main.dart';

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

  bool _isMusicPlaying = false;
  int _currentTrackIndex = 0;
  Duration _currentPosition = Duration.zero;

  // FIX: use AudioPlayer from audioplayers package
  final AudioPlayer _audioPlayer = AudioPlayer();

  // FIX: use AssetSource paths — same format as the working example
  final List<Map<String, dynamic>> _playlist = [
    {"title": "He Ram He Ram", "asset": "music/He Ram He Ram-320kbps.mp3"},
    {
      "title": "Mahamrityunjay Mantra",
      "asset":
          "music/Mahamrityunjay Mantra महमतयजय मतर Om Trayambakam Yajamahe.mp3",
    },
    {
      "title": "Shiv Namaskarartha Mantra",
      "asset":
          "music/Shiv Namaskarartha Mantra  Monday Special  LoFi Version.mp3",
    },
    {
      "title": "Sri Venkatesha Stotram",
      "asset":
          "music/Sri Venkatesha Stotram - Invoking the Lord's Mercy _ New Year 2025.mp3",
    },
    {
      "title": "Sri Venkateshwara Suprabhatham",
      "asset": "music/Sri Venkateshwara Suprabhatham-320kbps.mp3",
    },
    {
      "title": "Hanuman Chalisa",
      "asset":
          "music/शर हनमन चलस  Shree Hanuman Chalisa Original Video  GULSHAN KUMAR  HARIHARAN Full HD.mp3",
    },
  ];

  ORSystemProvider() {
    Timer.periodic(const Duration(seconds: 1), (t) {
      _now = DateTime.now();
      notifyListeners();
    });

    // FIX: audioplayers event listeners (different API from just_audio)
    _audioPlayer.onPositionChanged.listen((position) {
      _currentPosition = position;
      notifyListeners();
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      _isMusicPlaying = state == PlayerState.playing;
      notifyListeners();
    });

    // Auto-advance to next track when current one finishes
    _audioPlayer.onPlayerComplete.listen((event) {
      _isMusicPlaying = false;
      _currentPosition = Duration.zero;
      nextTrack();
    });
  }

  // Getters
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
  String get currentTrack => _playlist[_currentTrackIndex]["title"];
  String get formattedFullDate =>
      DateFormat('EEEE, dd/MM/yyyy').format(_now).toUpperCase();

  String get stopwatchDisplay {
    Duration d = Duration(seconds: _seconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds % 60)}";
  }

  void setViewMode(ORViewMode mode) {
    _viewMode = mode;
    notifyListeners();
  }

  void toggleMusicFlip() {
    _showMusic = !_showMusic;
    notifyListeners();
  }

  void toggleTempFlip() {
    _showTempSettings = !_showTempSettings;
    notifyListeners();
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

  // FIX: togglePlayPause using audioplayers API (resume/pause/play)
  Future<void> togglePlayPause() async {
    if (_isMusicPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_currentPosition.inSeconds > 0) {
        await _audioPlayer.resume(); // resume from paused position
      } else {
        await _playCurrentTrack(); // start fresh
      }
    }
  }

  // FIX: plays using AssetSource — exactly like the working example
  Future<void> _playCurrentTrack() async {
    try {
      final assetPath = _playlist[_currentTrackIndex]["asset"] as String;
      debugPrint("▶ Playing: $assetPath");
      await _audioPlayer.stop();
      _currentPosition = Duration.zero;
      await _audioPlayer.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  void nextTrack() {
    _currentTrackIndex = (_currentTrackIndex + 1) % _playlist.length;
    _playCurrentTrack();
  }

  void prevTrack() {
    _currentTrackIndex = (_currentTrackIndex - 1 < 0)
        ? _playlist.length - 1
        : _currentTrackIndex - 1;
    _playCurrentTrack();
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

  @override
  void dispose() {
    _audioPlayer.dispose();
    _stopwatchTimer?.cancel();
    super.dispose();
  }
}
