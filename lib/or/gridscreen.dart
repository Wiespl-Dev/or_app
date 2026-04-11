import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DraggableGridScreen extends StatefulWidget {
  @override
  State<DraggableGridScreen> createState() => _DraggableGridScreenState();
}

class _DraggableGridScreenState extends State<DraggableGridScreen> {
  List<_BoxData> boxes = [];
  final int columns = 2;
  final double spacing = 20;

  // Sidebar control variables
  bool _showSidebar = true;
  double _sidebarWidth = 250.0;

  // Video Player controllers for boxes 2, 3, 4
  late VideoPlayerController _videoController2;
  late VideoPlayerController _videoController3;
  late VideoPlayerController _videoController4;

  // WebView controller for box 1
  late WebViewController _webViewController1;

  // Camera IP
  String cameraIp = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Load camera IP
    await loadCameraIp();

    // Initialize controllers
    _initializeControllers();

    // Grid layout setup (4 boxes now)
    for (int i = 0; i < 4; i++) {
      int row = i ~/ columns;
      int col = i % columns;
      double startX = col * (300 + spacing) + spacing;
      double startY = row * (200 + spacing) + spacing;

      boxes.add(
        _BoxData(
          position: Offset(startX, startY),
          size: Size(300, 200),
          controller: _getController(i),
          index: i,
          isWebView: i == 0,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> loadCameraIp() async {
    final prefs = await SharedPreferences.getInstance();
    cameraIp = prefs.getString('cameraIp') ?? "192.168.1.100";
  }

  void _initializeControllers() {
    // Initialize WebView for Box 1
    _webViewController1 = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('http://$cameraIp:9081'));

    // Initialize video player for Box 2
    _videoController2 =
        VideoPlayerController.asset('assets/videos/surgery2.mp4')
          ..initialize().then((_) {
            setState(() {});
            _videoController2.setLooping(true);
            _videoController2.play();
          });

    // Initialize video player for Box 3
    _videoController3 =
        VideoPlayerController.asset('assets/videos/surgery3.mp4')
          ..initialize().then((_) {
            setState(() {});
            _videoController3.setLooping(true);
            _videoController3.play();
          });

    // Initialize video player for Box 4
    _videoController4 =
        VideoPlayerController.asset('assets/videos/surgery4.mp4')
          ..initialize().then((_) {
            setState(() {});
            _videoController4.setLooping(true);
            _videoController4.play();
          });
  }

  // Get controller based on index
  dynamic _getController(int index) {
    switch (index) {
      case 0:
        return _webViewController1;
      case 1:
        return _videoController2;
      case 2:
        return _videoController3;
      case 3:
        return _videoController4;
      default:
        return _webViewController1;
    }
  }

  @override
  void dispose() {
    _videoController2.dispose();
    _videoController3.dispose();
    _videoController4.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Color.fromARGB(255, 40, 123, 131),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                "Loading Video Grid...",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Surgery Video Grid",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Color.fromARGB(255, 44, 16, 90),
        elevation: 0,
        iconTheme: IconThemeData(
          color: Colors.white,
        ), // This makes the back arrow white
        actions: [],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 44, 16, 90),
              Color.fromARGB(255, 68, 49, 127),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            // Main content area
            Expanded(
              child: Stack(
                children: List.generate(boxes.length, (index) {
                  return _buildDraggableBox(index);
                }),
              ),
            ),

            // Sidebar is removed since EnvironmentState is removed
            // You can either keep it empty or remove it entirely
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableBox(int index) {
    final box = boxes[index];

    return Positioned(
      left: box.position.dx,
      top: box.position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            box.position += details.delta;
          });
        },
        child: Stack(
          children: [
            Container(
              width: box.size.width,
              height: box.size.height,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.white),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildBoxContent(box),
            ),
            // Video controls overlay (only for video players, not WebView)
            if (!box.isWebView)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildVideoControls(box),
              ),
            // Resize handle
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    box.size = Size(
                      (box.size.width + details.delta.dx).clamp(150.0, 800.0),
                      (box.size.height + details.delta.dy).clamp(100.0, 800.0),
                    );
                  });
                },
                child: Container(
                  width: 24,
                  height: 24,
                  color: Colors.white,
                  child: Icon(
                    Icons.open_in_full,
                    size: 16,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            // Drag bar
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: box.size.width,
                height: 30,
                color: Colors.black.withOpacity(0.5),
                alignment: Alignment.center,
                child: Text(
                  box.isWebView
                      ? "Live Camera Feed - Drag here"
                      : "Video ${box.index + 1} - Drag here",
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoxContent(_BoxData box) {
    if (box.isWebView) {
      // Box 1 - WebView
      final controller = box.controller as WebViewController?;
      if (controller != null) {
        return WebViewWidget(controller: controller);
      }
    } else {
      // Boxes 2-4 - VideoPlayer
      final controller = box.controller as VideoPlayerController?;
      if (controller == null || !controller.value.isInitialized) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 8),
              Text(
                "Loading Video ${box.index}...",
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ],
          ),
        );
      }

      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 8),
          Text(
            "Loading...",
            style: TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoControls(_BoxData box) {
    if (box.isWebView) return SizedBox();

    final controller = box.controller as VideoPlayerController?;

    if (controller == null || !controller.value.isInitialized) {
      return SizedBox();
    }

    return Container(
      height: 40,
      color: Colors.black.withOpacity(0.7),
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 16,
            ),
            onPressed: () {
              setState(() {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.replay, color: Colors.white, size: 16),
            onPressed: () {
              setState(() {
                controller.seekTo(Duration.zero);
                controller.play();
              });
            },
          ),
          IconButton(
            icon: Icon(
              controller.value.volume > 0 ? Icons.volume_up : Icons.volume_off,
              color: Colors.white,
              size: 16,
            ),
            onPressed: () {
              setState(() {
                controller.setVolume(controller.value.volume > 0 ? 0 : 1);
              });
            },
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Colors.blue,
                  bufferedColor: Colors.blue.shade100,
                  backgroundColor: Colors.grey.shade700,
                ),
              ),
            ),
          ),
          Text(
            "${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}",
            style: TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return "--:--";
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }
}

class _BoxData {
  Offset position;
  Size size;
  dynamic controller;
  int index;
  bool isWebView;

  _BoxData({
    required this.position,
    required this.size,
    required this.controller,
    required this.index,
    required this.isWebView,
  });
}
