import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:http/http.dart' as http;

const _svcChannel = MethodChannel(
  'com.example.wiespl_contrl_panel/recording_service',
);
const _fileChannel = MethodChannel('com.example.wiespl_contrl_panel/file_open');

Future<void> _startForegroundService() async {
  try {
    await _svcChannel.invokeMethod('startService');
  } catch (e) {
    debugPrint('FG start: $e');
  }
}

Future<void> _stopForegroundService() async {
  try {
    await _svcChannel.invokeMethod('stopService');
  } catch (e) {
    debugPrint('FG stop: $e');
  }
}

Future<void> _openInExternalPlayer(
  BuildContext context,
  String filePath,
) async {
  try {
    await _fileChannel.invokeMethod('openVideo', {'path': filePath});
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cannot open file: $e')));
    }
    debugPrint('openVideo error: $e');
  }
}

class _Msg {
  final String type;
  final dynamic data;
  const _Msg(this.type, this.data);
}

class _Config {
  final String streamUrl;
  final int tcpPort;
  final SendPort tx;
  final bool is4K;
  const _Config(this.streamUrl, this.tcpPort, this.tx, this.is4K);
}

enum _ParseState { header, body, crlf }

class _MjpegParser {
  _ParseState _state = _ParseState.header;
  final _headerBuf = <int>[];
  int _contentLength = 0;
  final _bodyBuf = <int>[];
  int _crlfCount = 0;

  List<List<int>> feed(List<int> bytes) {
    final frames = <List<int>>[];
    int i = 0;
    while (i < bytes.length) {
      switch (_state) {
        case _ParseState.header:
          _headerBuf.add(bytes[i++]);
          final len = _headerBuf.length;
          if (len >= 4 &&
              _headerBuf[len - 4] == 0x0D &&
              _headerBuf[len - 3] == 0x0A &&
              _headerBuf[len - 2] == 0x0D &&
              _headerBuf[len - 1] == 0x0A) {
            _contentLength = _parseContentLength(
              String.fromCharCodes(_headerBuf),
            );
            _headerBuf.clear();
            _bodyBuf.clear();
            if (_contentLength > 0) _state = _ParseState.body;
          }
          break;
        case _ParseState.body:
          final needed = _contentLength - _bodyBuf.length;
          final available = bytes.length - i;
          final take = needed < available ? needed : available;
          _bodyBuf.addAll(bytes.sublist(i, i + take));
          i += take;
          if (_bodyBuf.length >= _contentLength) {
            frames.add(List<int>.from(_bodyBuf));
            _bodyBuf.clear();
            _contentLength = 0;
            _crlfCount = 0;
            _state = _ParseState.crlf;
          }
          break;
        case _ParseState.crlf:
          final b = bytes[i++];
          if (b == 0x0D || b == 0x0A) {
            _crlfCount++;
            if (_crlfCount >= 2) _state = _ParseState.header;
          } else {
            _state = _ParseState.header;
            _headerBuf.add(b);
          }
          break;
      }
    }
    return frames;
  }

  int _parseContentLength(String headers) {
    for (final line in headers.split('\r\n')) {
      if (line.toLowerCase().startsWith('content-length:'))
        return int.tryParse(line.substring(15).trim()) ?? 0;
    }
    return 0;
  }

  void reset() {
    _state = _ParseState.header;
    _headerBuf.clear();
    _bodyBuf.clear();
    _contentLength = 0;
    _crlfCount = 0;
  }
}

void _isolateMain(List<dynamic> args) async {
  final cfg = args[0] as _Config;
  final rx = ReceivePort();
  cfg.tx.send(_Msg('ready', rx.sendPort));
  bool stop = false;
  rx.listen((_) {
    stop = true;
    rx.close();
  });

  Socket? sock;
  int totalBytes = 0;
  int reconnects = 0;

  try {
    for (int i = 0; i < 25; i++) {
      try {
        sock = await Socket.connect(
          InternetAddress.loopbackIPv4,
          cfg.tcpPort,
          timeout: const Duration(seconds: 2),
        );
        sock.setOption(SocketOption.tcpNoDelay, true);
        break;
      } catch (_) {
        if (stop) break;
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    if (sock == null || stop) {
      cfg.tx.send(_Msg('done', null));
      return;
    }
    cfg.tx.send(_Msg('info', 'TCP connected to FFmpeg'));

    if (cfg.is4K) {
      final parser = _MjpegParser();
      int sentFrames = 0;
      DateTime lastFrameTime = DateTime.now();
      bool forceReconnect = false;
      bool sockDead = false;

      final watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (stop) return;
        final age = DateTime.now().difference(lastFrameTime).inSeconds;
        if (age >= 4) {
          forceReconnect = true;
          cfg.tx.send(_Msg('info', 'No frames ${age}s — reconnecting'));
        }
      });

      while (!stop && !sockDead) {
        forceReconnect = false;
        http.Client? client;
        try {
          client = http.Client();
          final req = http.Request('GET', Uri.parse(cfg.streamUrl));
          req.headers['Connection'] = 'keep-alive';
          req.headers['Cache-Control'] = 'no-cache';
          final resp = await client
              .send(req)
              .timeout(const Duration(seconds: 8));
          await for (final chunk in resp.stream.timeout(
            const Duration(seconds: 5),
          )) {
            if (stop || forceReconnect || sockDead) break;
            final frames = parser.feed(chunk);
            for (final frame in frames) {
              if (stop || sockDead) break;
              lastFrameTime = DateTime.now();
              try {
                await sock!.addStream(Stream.value(frame));
                sentFrames++;
                totalBytes += frame.length;
                if (totalBytes % (512 * 1024) < frame.length)
                  cfg.tx.send(_Msg('bytes', totalBytes));
              } catch (e) {
                sockDead = true;
                cfg.tx.send(_Msg('info', 'TCP error: $e'));
                break;
              }
            }
          }
          if (stop || sockDead) break;
          parser.reset();
          reconnects++;
          cfg.tx.send(_Msg('info', 'HTTP reconnect #$reconnects'));
          await Future.delayed(const Duration(milliseconds: 500));
        } on TimeoutException {
          if (!stop && !sockDead) {
            parser.reset();
            reconnects++;
            cfg.tx.send(_Msg('info', 'Timeout — reconnect #$reconnects'));
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          if (!stop && !sockDead) {
            parser.reset();
            reconnects++;
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } finally {
          try {
            client?.close();
          } catch (_) {}
        }
        if (stop || sockDead) break;
        if (reconnects > 50) {
          cfg.tx.send(_Msg('info', 'Too many reconnects'));
          break;
        }
      }
      watchdog.cancel();
      cfg.tx.send(
        _Msg('info', '4K done — sent:$sentFrames reconnects:$reconnects'),
      );
    } else {
      while (!stop) {
        http.Client? client;
        try {
          client = http.Client();
          final req = http.Request('GET', Uri.parse(cfg.streamUrl));
          req.headers['Connection'] = 'keep-alive';
          req.headers['Cache-Control'] = 'no-cache';
          final resp = await client
              .send(req)
              .timeout(const Duration(seconds: 15));
          await for (final chunk in resp.stream) {
            if (stop) break;
            try {
              await sock!.addStream(Stream.value(chunk));
            } catch (_) {
              break;
            }
            totalBytes += chunk.length;
            if (totalBytes % (256 * 1024) < chunk.length)
              cfg.tx.send(_Msg('bytes', totalBytes));
          }
          if (stop) break;
          reconnects++;
          cfg.tx.send(_Msg('info', 'Reconnecting… ($reconnects)'));
          await Future.delayed(const Duration(seconds: 2));
        } catch (e) {
          if (!stop) {
            reconnects++;
            await Future.delayed(const Duration(seconds: 2));
          }
        } finally {
          try {
            client?.close();
          } catch (_) {}
        }
        if (reconnects > 20) break;
      }
    }
  } catch (e) {
    debugPrint('Isolate error: $e');
  } finally {
    try {
      await sock?.close();
    } catch (_) {
      try {
        sock?.destroy();
      } catch (_) {}
    }
    cfg.tx.send(_Msg('done', null));
  }
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Stream Recorder',
    theme: ThemeData(primarySwatch: Colors.red, useMaterial3: true),
    home: const StreamRecorderPage(),
    debugShowCheckedModeBanner: false,
  );
}

class StreamRecorderPage extends StatefulWidget {
  const StreamRecorderPage({Key? key}) : super(key: key);
  @override
  State<StreamRecorderPage> createState() => _StreamRecorderPageState();
}

class _StreamRecorderPageState extends State<StreamRecorderPage>
    with WidgetsBindingObserver {
  late WebViewController _wvc;
  bool _loading = true;
  bool _recording = false;
  bool _finalising = false;
  String _status = '';
  String _infoMsg = '';
  Isolate? _iso;
  ReceivePort? _rx;
  SendPort? _tx;
  Completer<void>? _isoDone;
  FFmpegSession? _ffSession;
  Completer<void>? _ffDone;
  String? _outputPath;
  static const _tcpPort = 18888;
  int _bytes = 0;
  DateTime? _startTime;
  Timer? _uiTimer;

  final _baseUrl = 'http://192.168.1.115:9081/';
  String _streamUrl =
      'http://192.168.1.115:9081/?action=stream&width=1280&height=720';
  String _selRes = 'HD (1280x720)';
  final _resolutions = <String, Map<String, int>>{
    '4K (3840x2160)': {'w': 3840, 'h': 2160},
    'QHD (2560x1440)': {'w': 2560, 'h': 1440},
    'FHD (1920x1080)': {'w': 1920, 'h': 1080},
    'HD (1280x720)': {'w': 1280, 'h': 720},
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reqPerms();
    _initWV();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (_recording && s == AppLifecycleState.detached) _stopRecording();
  }

  Future<void> _reqPerms() async {
    await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.ignoreBatteryOptimizations,
      Permission.notification,
    ].request();
  }

  void _initWV() {
    _wvc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(Uri.parse(_streamUrl));
  }

  void _setRes(String r) {
    if (_recording) return;
    setState(() {
      _selRes = r;
      final res = _resolutions[r]!;
      _streamUrl =
          '$_baseUrl?action=stream&width=${res['w']}&height=${res['h']}';
      _wvc.loadRequest(Uri.parse(_streamUrl));
    });
  }

  Map<String, dynamic> _profile(int w) {
    if (w >= 3840)
      return {
        'fps': 10,
        'probeSize': 2000000,
        'analyzeDur': 2000000,
        'preset': 'superfast',
        'crf': 30,
        'threads': 2,
        'is4K': true,
      };
    if (w >= 2560)
      return {
        'fps': 15,
        'probeSize': 5000000,
        'analyzeDur': 5000000,
        'preset': 'superfast',
        'crf': 28,
        'threads': 2,
        'is4K': false,
      };
    if (w >= 1920)
      return {
        'fps': 25,
        'probeSize': 5000000,
        'analyzeDur': 5000000,
        'preset': 'superfast',
        'crf': 28,
        'threads': 2,
        'is4K': false,
      };
    return {
      'fps': 25,
      'probeSize': 20000000,
      'analyzeDur': 20000000,
      'preset': 'ultrafast',
      'crf': 23,
      'threads': 0,
      'is4K': false,
    };
  }

  // Fragmented MP4: no file seek needed → works on external storage.
  // File is sealed instantly on TCP FIN regardless of size.
  // No temp file, no copy → 20-min 4K saves in <1 second.
  String _buildFfmpegCmd(int w, int h, String outputPath) {
    final p = _profile(w);
    final fps = p['fps'] as int;
    final threadFlag = (p['threads'] as int) > 0
        ? '-threads ${p['threads']} '
        : '';
    final vf = 'fps=$fps,scale=${w}:${h}';
    return '-y '
        '-analyzeduration ${p['analyzeDur']} -probesize ${p['probeSize']} '
        '-r $fps -f mjpeg '
        '-i "tcp://127.0.0.1:$_tcpPort?listen=1&timeout=60000000" '
        '$threadFlag'
        '-vf "$vf" -c:v libx264 -preset ${p['preset']} -tune zerolatency '
        '-crf ${p['crf']} -pix_fmt yuv420p -r $fps -an '
        '-movflags +frag_keyframe+default_base_moof '
        '-avoid_negative_ts make_zero '
        '"$outputPath"';
  }

  Future<void> _startRecording() async {
    try {
      await _startForegroundService();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final res = _resolutions[_selRes]!;
      final w = res['w']!;
      final h = res['h']!;

      // Write directly to external storage — no temp file, no copy.
      final extDir = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      if (extDir == null) {
        await _stopForegroundService();
        return;
      }
      final recDir = Directory('${extDir.path}/Recordings');
      if (!await recDir.exists()) await recDir.create(recursive: true);
      _outputPath = '${recDir.path}/rec_${w}x${h}_$ts.mp4';

      _isoDone = Completer<void>();
      _ffDone = Completer<void>();

      final cmd = _buildFfmpegCmd(w, h, _outputPath!);
      debugPrint('FFmpeg cmd: $cmd');

      _ffSession = await FFmpegKit.executeAsync(cmd, (session) async {
        final rc = await session.getReturnCode();
        final logs = await session.getLogs();
        debugPrint('══ FFmpeg RC: $rc ══');
        debugPrint(logs.map((l) => l.getMessage()).join('\n'));
        try {
          if (!(_ffDone?.isCompleted ?? true)) _ffDone!.complete();
        } catch (_) {}
        await _stopForegroundService();
        if (!mounted) return;
        if (ReturnCode.isSuccess(rc)) {
          _show('Saved ✓  ${_outputPath!.split('/').last}');
        } else {
          _show('Encoding failed (RC: $rc) — see logcat');
        }
      });

      await Future.delayed(const Duration(seconds: 2));
      final profile = _profile(w);

      _rx = ReceivePort();
      _rx!.listen((msg) {
        if (msg is! _Msg) return;
        switch (msg.type) {
          case 'ready':
            _tx = msg.data as SendPort;
            break;
          case 'bytes':
            if (mounted) setState(() => _bytes = msg.data as int);
            break;
          case 'info':
            debugPrint('Isolate: ${msg.data}');
            if (mounted) {
              setState(() => _infoMsg = msg.data.toString());
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted) setState(() => _infoMsg = '');
              });
            }
            break;
          case 'done':
            try {
              if (!(_isoDone?.isCompleted ?? true)) _isoDone!.complete();
            } catch (_) {}
            _rx?.close();
            _iso?.kill(priority: Isolate.immediate);
            _iso = null;
            break;
        }
      });

      _iso = await Isolate.spawn(_isolateMain, [
        _Config(_streamUrl, _tcpPort, _rx!.sendPort, profile['is4K'] as bool),
      ]);

      _bytes = 0;
      _startTime = DateTime.now();
      if (mounted) setState(() => _recording = true);
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      await _stopForegroundService();
      _show('Start failed: $e');
      debugPrint('Start: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _uiTimer?.cancel();
    if (mounted)
      setState(() {
        _recording = false;
        _finalising = true;
        _status = 'Stopping…';
      });

    _tx?.send('stop');
    _tx = null;
    _setStatus('Closing stream…');
    try {
      await _isoDone?.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => debugPrint('Isolate done timeout'),
      );
    } catch (_) {}

    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _rx?.close();
    _rx = null;

    // Fragmented MP4 seals in <1s on clean TCP FIN — timeout is just a safety net.
    _setStatus('Saving…');
    try {
      await _ffDone?.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('FFmpeg seal timeout');
          _ffSession?.cancel();
        },
      );
    } catch (e) {
      debugPrint('FFmpeg wait: $e');
    }

    if (mounted) setState(() => _finalising = false);
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  String _dur() {
    if (_startTime == null) return '00:00';
    final d = DateTime.now().difference(_startTime!);
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _fmt(int b) {
    if (b < 1 << 10) return '$b B';
    if (b < 1 << 20) return '${(b / (1 << 10)).toStringAsFixed(1)} KB';
    if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  }

  void _show(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<List<FileSystemEntity>> _getFiles() async {
    final d = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    final dir = Directory('${d!.path}/Recordings');
    if (!await dir.exists()) return [];
    final list = dir.listSync().where((f) => f.path.endsWith('.mp4')).toList();
    list.sort((a, b) => b.path.compareTo(a.path));
    return list;
  }

  void _showFiles() async {
    final files = await _getFiles();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Recordings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: files.isEmpty
                  ? const Center(child: Text('No recordings yet'))
                  : ListView.builder(
                      controller: sc,
                      itemCount: files.length,
                      itemBuilder: (ctx, i) {
                        final name = files[i].path.split('/').last;
                        final size = File(files[i].path).lengthSync();
                        return ListTile(
                          leading: const Icon(Icons.movie, color: Colors.red),
                          title: Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            _fmt(size),
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _openInExternalPlayer(context, files[i].path);
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  await File(files[i].path).delete();
                                  _show('Deleted');
                                  if (mounted) Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showResPicker() {
    if (_recording) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: _resolutions.keys
            .map(
              (r) => ListTile(
                title: Text(r),
                trailing: _selRes == r
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _setRes(r);
                },
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiTimer?.cancel();
    _tx?.send('stop');
    _iso?.kill(priority: Isolate.immediate);
    _rx?.close();
    _stopForegroundService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream Recorder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _recording || _finalising ? null : _showResPicker,
          ),
          IconButton(
            icon: const Icon(Icons.folder),
            onPressed: _recording || _finalising ? null : _showFiles,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _recording ? null : () => _wvc.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: _recording
                ? Colors.red.shade700
                : _finalising
                ? Colors.orange.shade700
                : Colors.blue.shade700,
            child: Column(
              children: [
                Text(
                  _recording
                      ? '● REC  $_selRes  ${_dur()}  ${_fmt(_bytes)}'
                      : _finalising
                      ? '⏳ $_status'
                      : '$_selRes  •  Ready',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_infoMsg.isNotEmpty)
                  Text(
                    '⚡ $_infoMsg',
                    style: const TextStyle(color: Colors.yellow, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _wvc),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_recording) Positioned(top: 12, right: 12, child: _Blink()),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: _finalising
                ? Column(
                    children: [
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        _status,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _recording ? null : _startRecording,
                        icon: const Icon(Icons.circle, color: Colors.red),
                        label: const Text('Start'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _recording ? _stopRecording : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Blink extends StatefulWidget {
  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
    ),
  );
}





























import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HDMI Control',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HDMIControlPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HDMIControlPage extends StatefulWidget {
  const HDMIControlPage({super.key});

  @override
  State<HDMIControlPage> createState() => _HDMIControlPageState();
}

class _HDMIControlPageState extends State<HDMIControlPage> {
  String _statusMessage = '';
  bool _isLoading = false;

  // Camera URLs for HDMI 1
  final Map<String, String> hdmi1Cameras = {
    'Camera 1': 'http://192.168.1.131:8080/hdmi1?url=http://192.168.1.131:9081',
    'Camera 2': 'http://192.168.1.131:8080/hdmi1?url=http://192.168.1.131:9082',
    'Camera 3': 'http://192.168.1.131:8080/hdmi1?url=http://192.168.1.131:9083',
    'Camera 4': 'http://192.168.1.131:8080/hdmi1?url=http://192.168.1.131:9084',
  };

  // Camera URLs for HDMI 2
  final Map<String, String> hdmi2Cameras = {
    'Camera 1': 'http://192.168.1.131:8080/hdmi2?url=http://192.168.1.131:9081',
    'Camera 2': 'http://192.168.1.131:8080/hdmi2?url=http://192.168.1.131:9082',
    'Camera 3': 'http://192.168.1.131:8080/hdmi2?url=http://192.168.1.131:9083',
    'Camera 4': 'http://192.168.1.131:8080/hdmi2?url=http://192.168.1.131:9084',
  };

  Future<void> _switchCamera(String cameraName, String url) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Switching to $cameraName...';
    });

    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      setState(() {
        if (response.statusCode == 200) {
          _statusMessage = '✓ Successfully switched to $cameraName';
          _showSnackBar('$cameraName activated', isSuccess: true);
        } else {
          _statusMessage = '✗ Failed with status: ${response.statusCode}';
          _showSnackBar('Error: ${response.statusCode}', isSuccess: false);
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = '✗ Error: Could not connect';
      });
      _showSnackBar('Connection failed', isSuccess: false);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, {required bool isSuccess}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showHDMIPopup(String hdmiNumber, Map<String, String> cameras) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                hdmiNumber == '1' ? Icons.tv : Icons.live_tv,
                color: hdmiNumber == '1' ? Colors.blue : Colors.green,
              ),
              const SizedBox(width: 10),
              Text('HDMI $hdmiNumber Cameras'),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: cameras.length,
              itemBuilder: (context, index) {
                String cameraName = cameras.keys.elementAt(index);
                String cameraUrl = cameras.values.elementAt(index);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: hdmiNumber == '1'
                          ? Colors.blue
                          : Colors.green,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      cameraName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      cameraUrl,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.pop(context);
                              _switchCamera(cameraName, cameraUrl);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hdmiNumber == '1'
                            ? Colors.blue
                            : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Select'),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _switchCamera(cameraName, cameraUrl);
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HDMI Camera Controller',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status Message
                if (_statusMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 30),
                    decoration: BoxDecoration(
                      color: _statusMessage.startsWith('✓')
                          ? Colors.green.shade100
                          : (_statusMessage.startsWith('✗')
                                ? Colors.red.shade100
                                : Colors.blue.shade100),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _statusMessage.startsWith('✓')
                            ? Colors.green
                            : (_statusMessage.startsWith('✗')
                                  ? Colors.red
                                  : Colors.blue),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _statusMessage.startsWith('✓')
                              ? Icons.check_circle
                              : (_statusMessage.startsWith('✗')
                                    ? Icons.error
                                    : Icons.info),
                          color: _statusMessage.startsWith('✓')
                              ? Colors.green
                              : (_statusMessage.startsWith('✗')
                                    ? Colors.red
                                    : Colors.blue),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        if (_isLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),

                // HDMI Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // HDMI 1 Button
                    Expanded(
                      child: _buildHDMIButton(
                        number: '1',
                        color: Colors.blue,
                        icon: Icons.tv,
                        onTap: () => _showHDMIPopup('1', hdmi1Cameras),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // HDMI 2 Button
                    Expanded(
                      child: _buildHDMIButton(
                        number: '2',
                        color: Colors.green,
                        icon: Icons.live_tv,
                        onTap: () => _showHDMIPopup('2', hdmi2Cameras),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // Info Text
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(height: 8),
                      Text(
                        'Click on HDMI 1 or HDMI 2 to select a camera',
                        style: TextStyle(color: Colors.grey.shade700),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHDMIButton({
    required String number,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withOpacity(0.7)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 80, color: Colors.white),
                const SizedBox(height: 10),
                Text(
                  'HDMI $number',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${number == '1' ? '4' : '4'} Cameras',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

















































//////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TinyCam Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const TinyCamPage(),
    );
  }
}

class TinyCamPage extends StatefulWidget {
  const TinyCamPage({super.key});
  @override
  State<TinyCamPage> createState() => _TinyCamPageState();
}

class _TinyCamPageState extends State<TinyCamPage> {
  // ── Config — change these if needed ─────────────────────
  final String host = '192.168.1.143';
  final int port = 8083;
  final String username = 'admin';
  final String password = ''; // leave empty if no password set

  // ── State ────────────────────────────────────────────────
  String? _token; // auth token from login
  bool _loggedIn = false;
  bool _recording = false;
  bool _loading = false;
  final List<String> _logs = [];

  String get base => 'http://$host:$port';

  // ── Logging ──────────────────────────────────────────────
  void _log(String msg) {
    final now = DateTime.now();
    final t =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.insert(0, '[$t] $msg');
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  // ── Step 1: Login → get token ────────────────────────────
  // Official TinyCam API: POST /api/v1/login  (or GET with Basic Auth)
  Future<bool> _login() async {
    setState(() => _loading = true);
    _log('🔑 Logging in as "$username"...');

    try {
      // TinyCam supports Basic Auth on every request OR token-based login
      // Try token login first
      final uri = Uri.parse('$base/api/v1/login');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 6));

      _log('Login response ${res.statusCode}: ${res.body}');

      if (res.statusCode == 200) {
        try {
          final data = jsonDecode(res.body);
          _token = data['data']?['token'] ?? data['token'];
          if (_token != null) {
            _log('✅ Logged in! Token: ${_token!.substring(0, 8)}...');
            setState(() {
              _loggedIn = true;
              _loading = false;
            });
            return true;
          }
        } catch (_) {}
      }

      // Fallback: use HTTP Basic Auth (no token needed, just attach header each time)
      _log('ℹ️ Using Basic Auth instead of token');
      setState(() {
        _loggedIn = true;
        _loading = false;
      });
      return true;
    } catch (e) {
      _log('❌ Login failed: $e');
      setState(() {
        _loggedIn = false;
        _loading = false;
      });
      return false;
    }
  }

  // ── Build auth headers ───────────────────────────────────
  Map<String, String> get _authHeaders {
    if (_token != null) {
      // Token-based (preferred by TinyCam API)
      return {'token': _token!};
    }
    // HTTP Basic Auth fallback
    if (username.isNotEmpty) {
      final encoded = base64Encode(utf8.encode('$username:$password'));
      return {'Authorization': 'Basic $encoded'};
    }
    return {};
  }

  // ── GET helper ───────────────────────────────────────────
  Future<http.Response?> _get(String path) async {
    try {
      final res = await http
          .get(Uri.parse('$base$path'), headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      _log('→ GET $path  ←  ${res.statusCode}: ${res.body}');
      return res;
    } catch (e) {
      _log('❌ $path failed: $e');
      return null;
    }
  }

  // ── Start Recording ──────────────────────────────────────
  // TinyCam API: param.cgi?action=update&root.BackgroundMode=on
  // This starts background mode which includes recording
  Future<void> _startRecording() async {
    if (!_loggedIn) {
      await _login();
    }
    setState(() => _loading = true);
    _log('▶ Starting recording...');

    // Try official TinyCam API endpoints in order
    final endpoints = [
      '/param.cgi?action=update&root.BackgroundMode=on',
      '/api/v1/set_params?backgroundMode=on',
      '/api/v1/start_record',
    ];

    for (final ep in endpoints) {
      final res = await _get(ep);
      if (res != null && res.statusCode == 200) {
        setState(() {
          _recording = true;
          _loading = false;
        });
        _log('✅ Recording started!');
        return;
      }
    }

    _log('⚠️ Could not start — try tapping "Scan" to find correct endpoint');
    setState(() => _loading = false);
  }

  // ── Stop Recording ───────────────────────────────────────
  Future<void> _stopRecording() async {
    if (!_loggedIn) {
      await _login();
    }
    setState(() => _loading = true);
    _log('⏹ Stopping recording...');

    final endpoints = [
      '/param.cgi?action=update&root.BackgroundMode=off',
      '/api/v1/set_params?backgroundMode=off',
      '/api/v1/stop_record',
    ];

    for (final ep in endpoints) {
      final res = await _get(ep);
      if (res != null && res.statusCode == 200) {
        setState(() {
          _recording = false;
          _loading = false;
        });
        _log('✅ Recording stopped!');
        return;
      }
    }

    _log('⚠️ Could not stop');
    setState(() => _loading = false);
  }

  // ── Get Status ───────────────────────────────────────────
  Future<void> _getStatus() async {
    if (!_loggedIn) {
      await _login();
    }
    _log('🔍 Getting status...');
    final res = await _get('/api/v1/get_status');
    if (res != null && res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body);
        final bg = data['data']?['backgroundMode'] ?? false;
        setState(() => _recording = bg);
        _log('Status OK — backgroundMode: $bg');
      } catch (_) {}
    }
  }

  // ── Scan all known endpoints ─────────────────────────────
  Future<void> _scan() async {
    if (!_loggedIn) {
      await _login();
    }
    _log('🔎 Scanning all endpoints...');

    final endpoints = [
      '/api/v1/get_status',
      '/api/v1/get_cam_list',
      '/param.cgi?action=update&root.BackgroundMode=on',
      '/param.cgi?action=update&root.BackgroundMode=off',
      '/api/v1/login',
      '/',
      '/index.htm',
    ];

    for (final ep in endpoints) {
      final res = await _get(ep);
      if (res != null) {
        _log('${res.statusCode == 200 ? '✅' : '  '} $ep → ${res.statusCode}');
      }
    }
    _log('🔎 Scan done');
  }

  // ── UI ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TinyCam Controller'),
        backgroundColor: Colors.grey[900],
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _loggedIn ? Colors.greenAccent : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _loggedIn ? 'Online' : 'Offline',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.grey[850],
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Server address ──────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$base  (user: $username)',
                style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 14),

            // ── Login button ────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: Text(_loggedIn ? 'Re-Login' : 'Connect & Login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _loggedIn
                      ? Colors.grey[700]
                      : Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _loading ? null : _login,
              ),
            ),

            const SizedBox(height: 20),

            // ── Recording indicator ─────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: _recording
                    ? Colors.red.withOpacity(0.15)
                    : Colors.grey[800],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _recording ? Colors.red : Colors.grey[700]!,
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _recording
                        ? Icons.fiber_manual_record
                        : Icons.videocam_outlined,
                    color: _recording ? Colors.red : Colors.grey,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _recording ? '● RECORDING' : 'STANDBY',
                    style: TextStyle(
                      color: _recording ? Colors.red : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── START / STOP ────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 58,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text(
                        'START',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        disabledBackgroundColor: Colors.red.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _loading || _recording
                          ? null
                          : _startRecording,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 58,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.stop),
                      label: const Text(
                        'STOP',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        disabledBackgroundColor: Colors.blueAccent.withOpacity(
                          0.3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _loading || !_recording
                          ? null
                          : _stopRecording,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Status + Scan ───────────────────────────────
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Get Status'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: BorderSide(color: Colors.grey[700]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _loading ? null : _getStatus,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('Scan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: BorderSide(color: Colors.grey[700]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _loading ? null : _scan,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Log panel ───────────────────────────────────
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'LOG',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _logs.clear()),
                          child: const Text(
                            'CLEAR',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _logs.isEmpty
                          ? const Center(
                              child: Text(
                                'Tap "Connect & Login" to start',
                                style: TextStyle(color: Colors.white24),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _logs.length,
                              itemBuilder: (_, i) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 1,
                                ),
                                child: Text(
                                  _logs[i],
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: _logs[i].contains('❌')
                                        ? Colors.redAccent
                                        : _logs[i].contains('✅')
                                        ? Colors.greenAccent
                                        : _logs[i].contains('⚠️')
                                        ? Colors.orangeAccent
                                        : Colors.white54,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            if (_loading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(color: Colors.blueAccent),
            ],
          ],
        ),
      ),
    );
  }
}
hellooooo