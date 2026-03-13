import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:http/http.dart' as http;

// ═══════════════════════════════════════════════════════════════════
// CHANNEL
// ═══════════════════════════════════════════════════════════════════
const _svcChannel = MethodChannel(
  'com.example.wiespl_contrl_panel/recording_service',
);

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

// ═══════════════════════════════════════════════════════════════════
// ISOLATE MESSAGES
// ═══════════════════════════════════════════════════════════════════
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

// ═══════════════════════════════════════════════════════════════════
// MULTIPART MJPEG PARSER
// Uses Content-Length header — reads exact bytes per frame.
// ═══════════════════════════════════════════════════════════════════
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
      if (line.toLowerCase().startsWith('content-length:')) {
        return int.tryParse(line.substring(15).trim()) ?? 0;
      }
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

// ═══════════════════════════════════════════════════════════════════
// ISOLATE
// Sends TCP FIN (not RST) on stop for clean FFmpeg shutdown.
// ═══════════════════════════════════════════════════════════════════
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
      // ── 4K: parse complete frames, send with back-pressure ─────
      final parser = _MjpegParser();
      int sentFrames = 0;

      DateTime lastFrameTime = DateTime.now();
      bool forceReconnect = false;
      final watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (stop) return;
        final age = DateTime.now().difference(lastFrameTime).inSeconds;
        if (age >= 4) {
          forceReconnect = true;
          cfg.tx.send(_Msg('info', 'No frames ${age}s — reconnecting'));
        }
      });

      // sockDead = true when the TCP socket to FFmpeg is broken.
      // This is FATAL — we cannot send more frames, stop everything.
      // It is separate from HTTP stream ending (which is normal and
      // should trigger a reconnect to mjpg_streamer, not a full stop).
      bool sockDead = false;

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
                if (totalBytes % (512 * 1024) < frame.length) {
                  cfg.tx.send(_Msg('bytes', totalBytes));
                }
              } catch (e) {
                // TCP socket to FFmpeg is dead — cannot continue
                sockDead = true;
                cfg.tx.send(_Msg('info', 'TCP error: $e'));
                break;
              }
            }
          }

          if (stop || sockDead) break;
          // HTTP stream ended normally — reconnect to mjpg_streamer
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
          cfg.tx.send(_Msg('info', 'Too many reconnects — stopping'));
          break;
        }
      }

      watchdog.cancel();
      cfg.tx.send(
        _Msg('info', '4K done — sent:$sentFrames reconnects:$reconnects'),
      );
    } else {
      // ── HD/FHD/QHD: raw chunk back-pressure ───────────────────
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
            if (totalBytes % (256 * 1024) < chunk.length) {
              cfg.tx.send(_Msg('bytes', totalBytes));
            }
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
    // GRACEFUL CLOSE: TCP FIN tells FFmpeg "input done, seal the file"
    // close() = FIN = clean EOF. destroy() = RST = broken connection.
    // FFmpeg writes moov atom immediately on FIN, in <1s.
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

// ═══════════════════════════════════════════════════════════════════
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

// ═══════════════════════════════════════════════════════════════════
// OPEN FILE IN EXTERNAL APP
//
// Uses a MethodChannel to fire an Android ACTION_VIEW intent with a
// FileProvider URI. This is the correct way to open local files in
// external apps (MX Player, VLC, etc.) on Android 7+.
// Plain file:// URIs are blocked by Android since API 24.
//
// Requires in AndroidManifest.xml:
//   <provider
//     android:name="androidx.core.content.FileProvider"
//     android:authorities="${applicationId}.fileprovider"
//     android:exported="false"
//     android:grantUriPermissions="true">
//     <meta-data
//       android:name="android.support.FILE_PROVIDER_PATHS"
//       android:resource="@xml/file_paths" />
//   </provider>
//
// Requires res/xml/file_paths.xml:
//   <paths>
//     <external-files-path name="recordings" path="Recordings/" />
//     <cache-path name="cache" path="." />
//   </paths>
// ═══════════════════════════════════════════════════════════════════
const _fileChannel = MethodChannel('com.example.wiespl_contrl_panel/file_open');

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

// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE

// ═══════════════════════════════════════════════════════════════════
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
    if (w >= 3840) {
      return {
        'fps': 10,
        'probeSize': 2000000,
        'analyzeDur': 2000000,
        'preset': 'superfast',
        'crf': 30,
        'threads': 2,
        'is4K': true,
      };
    } else if (w >= 2560) {
      return {
        'fps': 15,
        'probeSize': 5000000,
        'analyzeDur': 5000000,
        'preset': 'superfast',
        'crf': 28,
        'threads': 2,
        'is4K': false,
      };
    } else if (w >= 1920) {
      return {
        'fps': 25,
        'probeSize': 5000000,
        'analyzeDur': 5000000,
        'preset': 'superfast',
        'crf': 28,
        'threads': 2,
        'is4K': false,
      };
    } else {
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
  }

  // ════════════════════════════════════════════════════════════════
  // FFmpeg command
  //
  // WHY +faststart FAILED on Android:
  //   +faststart requires FFmpeg to seek back to position 0 in the
  //   output file to prepend the moov atom after writing all data.
  //   Android external storage (scoped storage / SAF) often does NOT
  //   support seeking on files opened by path — the seek silently
  //   fails, leaving the file with video data but no moov atom.
  //   Result: file exists, has size, but cannot be played.
  //
  // THE CORRECT SOLUTION for Android — two-pass write to app cache:
  //   1. FFmpeg writes the file to app internal cache directory
  //      (getApplicationDocumentsDirectory or getCacheDir).
  //      Internal storage ALWAYS supports seeking — moov write works.
  //   2. After FFmpeg finishes, we copy the file to external storage
  //      using Dart File.copy() which works on all Android versions.
  //
  // WHY NOT fragmented MP4 (+frag_keyframe+empty_moov):
  //   Fragmented MP4 needs keyframes to close fragments. Short 4K
  //   recordings (30s, low fps) may have very few keyframes. If the
  //   last fragment is incomplete at stop time, the file is unplayable.
  //   Standard MP4 with internal-storage write is always reliable.
  //
  // MOVFLAGS used: +faststart (works on internal storage) +write_colr
  //   These produce a standard, widely-compatible MP4.
  // ════════════════════════════════════════════════════════════════
  String _buildFfmpegCmd(int w, int h, String outputPath) {
    final p = _profile(w);
    final fps = p['fps'] as int;
    final threadFlag = (p['threads'] as int) > 0
        ? '-threads ${p['threads']} '
        : '';
    final vf = 'fps=$fps,scale=${w}:${h}';

    // -r before -i sets the INPUT frame rate for MJPEG demuxer.
    // -framerate is NOT valid for ffmpeg-kit — use -r on input side.
    // -vf fps= resamples output to exact fps regardless of input rate.
    // No -movflags tricks needed when writing to internal cache storage.
    return '-y '
        '-analyzeduration ${p['analyzeDur']} '
        '-probesize ${p['probeSize']} '
        '-r $fps '
        '-f mjpeg '
        '-i "tcp://127.0.0.1:$_tcpPort?listen=1&timeout=60000000" '
        '$threadFlag'
        '-vf "$vf" '
        '-c:v libx264 '
        '-preset ${p['preset']} '
        '-tune zerolatency '
        '-crf ${p['crf']} '
        '-pix_fmt yuv420p '
        '-r $fps '
        '-an '
        '-avoid_negative_ts make_zero '
        '"$outputPath"';
  }

  // ════════════════════════════════════════════════════════════════
  // START
  // Write to internal cache first, copy to external after save.
  // ════════════════════════════════════════════════════════════════
  Future<void> _startRecording() async {
    try {
      await _startForegroundService();

      // Internal cache dir — always supports file seeking (needed for
      // +faststart moov write). External storage does NOT support seek.
      final cacheDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final res = _resolutions[_selRes]!;
      final w = res['w']!;
      final h = res['h']!;

      // Temp file in internal cache for FFmpeg to write
      final tempPath = '${cacheDir.path}/rec_tmp_$ts.mp4';

      // Final destination on external storage
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

      final cmd = _buildFfmpegCmd(w, h, tempPath);
      debugPrint('FFmpeg cmd: $cmd');

      _ffSession = await FFmpegKit.executeAsync(cmd, (session) async {
        final rc = await session.getReturnCode();
        // getLogs() collects all FFmpeg stderr output
        final logs = await session.getLogs();
        final logText = logs.map((l) => l.getMessage()).join('\n');
        debugPrint('══ FFmpeg RC: $rc ══');
        debugPrint('══ FFmpeg logs ══\n$logText');

        try {
          if (!(_ffDone?.isCompleted ?? true)) _ffDone!.complete();
        } catch (_) {}

        await _stopForegroundService();
        if (!mounted) return;

        if (ReturnCode.isSuccess(rc)) {
          try {
            final tmpFile = File(tempPath);
            final sz = await tmpFile.length();
            debugPrint('Temp file size: $sz bytes');
            if (sz > 0) {
              await tmpFile.copy(_outputPath!);
              await tmpFile.delete();
              _show('Saved ✓  ${_outputPath!.split('/').last}');
            } else {
              _show('Error: encoded file is empty');
            }
          } catch (e) {
            _show('Save failed: $e');
            debugPrint('Copy error: $e');
          }
        } else {
          try {
            await File(tempPath).delete();
          } catch (_) {}
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

  // ════════════════════════════════════════════════════════════════
  // STOP — clean EOF sequence
  // ════════════════════════════════════════════════════════════════
  Future<void> _stopRecording() async {
    if (!_recording) return;
    _uiTimer?.cancel();
    if (mounted)
      setState(() {
        _recording = false;
        _finalising = true;
        _status = 'Stopping…';
      });

    // Ask isolate to close socket cleanly (TCP FIN → FFmpeg EOF)
    _tx?.send('stop');
    _tx = null;

    // Wait for isolate to confirm socket closed
    _setStatus('Closing stream…');
    try {
      await _isoDone?.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => debugPrint('Isolate done timeout'),
      );
    } catch (_) {}

    // Hard-kill isolate (safety net)
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _rx?.close();
    _rx = null;

    // Wait for FFmpeg to write moov and copy file to external storage
    _setStatus('Saving MP4…');
    try {
      await _ffDone?.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          debugPrint('FFmpeg seal timeout — cancelling');
          _ffSession?.cancel();
        },
      );
    } catch (e) {
      debugPrint('FFmpeg wait error: $e');
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

// ═══════════════════════════════════════════════════════════════════
// BLINKING DOT
// ═══════════════════════════════════════════════════════════════════
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


#   o r _ a p p  
 