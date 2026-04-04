// // recorder_controller.dart
// import 'dart:async';
// import 'dart:io';
// import 'dart:typed_data';
// import 'dart:ui' as ui;

// import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
// import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
// import 'package:ffmpeg_kit_flutter_new/return_code.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/services.dart';
// import 'package:get/get.dart';
// import 'package:http/http.dart' as http;
// import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart';

// // ─── Platform Channels ────────────────────────────────────────────────────────
// const _svcCh = MethodChannel(
//   'com.example.wiespl_contrl_panel/recording_service',
// );
// const _fileCh = MethodChannel('com.example.wiespl_contrl_panel/file_open');

// Future<void> _svcStart() async {
//   try {
//     await _svcCh.invokeMethod('startService');
//   } catch (e) {
//     debugPrint('svc start: $e');
//   }
// }

// Future<void> _svcStop() async {
//   try {
//     await _svcCh.invokeMethod('stopService');
//   } catch (e) {
//     debugPrint('svc stop: $e');
//   }
// }

// Future<void> _svcUpdate(String text) async {
//   try {
//     await _svcCh.invokeMethod('updateNotification', {'text': text});
//   } catch (_) {}
// }

// Future<void> openVideo(String path) async {
//   try {
//     await _fileCh.invokeMethod('openVideo', {'path': path});
//   } catch (e) {
//     debugPrint('openVideo: $e');
//   }
// }

// // ─── Models ───────────────────────────────────────────────────────────────────
// class AppSource {
//   final int id;
//   final String name;
//   final String baseUrl;
//   const AppSource({
//     required this.id,
//     required this.name,
//     required this.baseUrl,
//   });
//   String urlWithRes(int w, int h) =>
//       '$baseUrl?action=stream&width=$w&height=$h';
// }

// // ─── MJPEG Parser ─────────────────────────────────────────────────────────────
// enum _PS { header, body, crlf }

// class _MjpegParser {
//   _PS _s = _PS.header;
//   final _hb = <int>[];
//   int _cl = 0;
//   final _bb = <int>[];
//   int _cr = 0;

//   List<List<int>> feed(List<int> bytes) {
//     final frames = <List<int>>[];
//     int i = 0;
//     while (i < bytes.length) {
//       switch (_s) {
//         case _PS.header:
//           _hb.add(bytes[i++]);
//           final l = _hb.length;
//           if (l >= 4 &&
//               _hb[l - 4] == 0x0D &&
//               _hb[l - 3] == 0x0A &&
//               _hb[l - 2] == 0x0D &&
//               _hb[l - 1] == 0x0A) {
//             _cl = _parseCL(String.fromCharCodes(_hb));
//             _hb.clear();
//             _bb.clear();
//             if (_cl > 0) _s = _PS.body;
//           }
//           break;
//         case _PS.body:
//           final need = _cl - _bb.length;
//           final avail = bytes.length - i;
//           final take = need < avail ? need : avail;
//           _bb.addAll(bytes.sublist(i, i + take));
//           i += take;
//           if (_bb.length >= _cl) {
//             frames.add(List<int>.from(_bb));
//             _bb.clear();
//             _cl = 0;
//             _cr = 0;
//             _s = _PS.crlf;
//           }
//           break;
//         case _PS.crlf:
//           final b = bytes[i++];
//           if (b == 0x0D || b == 0x0A) {
//             if (++_cr >= 2) _s = _PS.header;
//           } else {
//             _s = _PS.header;
//             _hb.add(b);
//           }
//           break;
//       }
//     }
//     return frames;
//   }

//   int _parseCL(String h) {
//     for (final l in h.split('\r\n'))
//       if (l.toLowerCase().startsWith('content-length:'))
//         return int.tryParse(l.substring(15).trim()) ?? 0;
//     return 0;
//   }

//   void reset() {
//     _s = _PS.header;
//     _hb.clear();
//     _bb.clear();
//     _cl = 0;
//     _cr = 0;
//   }
// }

// // ─── MJPEG Stream ─────────────────────────────────────────────────────────────
// // The image is a plain ValueNotifier so only _MjpegView repaints on new frames.
// // No GetX reactive overhead on the hot path.
// class MjpegStream {
//   String _url;
//   int _gen = 0;
//   bool _disposed = false;
//   http.Client? _client;
//   final image = ValueNotifier<ui.Image?>(null);

//   MjpegStream(String url) : _url = url;
//   String get currentUrl => _url;

//   void start() {
//     if (!_disposed) {
//       _gen++;
//       _loop(_gen);
//     }
//   }

//   void stop() {
//     _gen++;
//     _client?.close();
//     _client = null;
//   }

//   void restart(String newUrl) {
//     if (_disposed) return;
//     _gen++;
//     _client?.close();
//     _client = null;
//     _url = newUrl;
//     final old = image.value;
//     image.value = null;
//     old?.dispose();
//     _loop(_gen);
//   }

//   void dispose() {
//     _disposed = true;
//     _gen++;
//     _client?.close();
//     _client = null;
//     final old = image.value;
//     image.value = null;
//     old?.dispose();
//     image.dispose();
//   }

//   Future<void> _loop(int myGen) async {
//     final parser = _MjpegParser();
//     bool decoding = false;

//     while (!_disposed && _gen == myGen) {
//       _client = http.Client();
//       final client = _client!;
//       try {
//         final req = http.Request('GET', Uri.parse(_url))
//           ..headers['Connection'] = 'keep-alive'
//           ..headers['Cache-Control'] = 'no-cache';
//         final resp = await client.send(req).timeout(const Duration(seconds: 8));

//         await for (final chunk in resp.stream.timeout(
//           const Duration(seconds: 5),
//         )) {
//           if (_disposed || _gen != myGen) break;
//           for (final fb in parser.feed(chunk)) {
//             if (_disposed || _gen != myGen) break;
//             if (decoding) continue;
//             decoding = true;
//             final cg = myGen;
//             ui.decodeImageFromList(Uint8List.fromList(fb), (decoded) {
//               decoding = false;
//               if (_disposed || _gen != cg) {
//                 decoded.dispose();
//                 return;
//               }
//               final old = image.value;
//               image.value = decoded;
//               old?.dispose();
//             });
//           }
//         }
//       } catch (_) {
//         // retry on any error
//       } finally {
//         try {
//           client.close();
//         } catch (_) {}
//         if (_client == client) _client = null;
//         parser.reset();
//         decoding = false;
//       }
//       if (!_disposed && _gen == myGen)
//         await Future.delayed(const Duration(milliseconds: 300));
//     }
//   }
// }

// // ─── Per-source recorder data ─────────────────────────────────────────────────
// class SourceSlot {
//   final AppSource source;
//   late final MjpegStream mjpeg;

//   // GetX observables — only changed from within the controller
//   final recording = false.obs;
//   final finalising = false.obs;
//   final bytes = 0.obs;
//   final status = ''.obs;
//   final startTime = Rxn<DateTime>();

//   FFmpegSession? ffSession;
//   Completer<void>? ffDone;
//   String? outputPath;
//   Timer? uiTimer;
//   Timer? bytesTimer;

//   SourceSlot(this.source, String url) {
//     mjpeg = MjpegStream(url);
//   }

//   bool get isActive => recording.value || finalising.value;

//   void disposeAll() {
//     uiTimer?.cancel();
//     bytesTimer?.cancel();
//     mjpeg.dispose();
//   }
// }

// // ─── GetX Controller ──────────────────────────────────────────────────────────
// class RecorderController extends GetxController {
//   // ── Static config ──────────────────────────────────────────────────────
//   static const sources = [
//     AppSource(id: 1, name: 'Source 1', baseUrl: 'http://192.168.1.131:9081/'),
//     AppSource(id: 2, name: 'Source 2', baseUrl: 'http://192.168.1.131:9082/'),
//     AppSource(id: 3, name: 'Source 3', baseUrl: 'http://192.168.1.131:9083/'),
//     AppSource(id: 4, name: 'Source 4', baseUrl: 'http://192.168.1.131:9084/'),
//   ];

//   static const resolutions = <String, (int, int)>{
//     '4K (3840x2160)': (3840, 2160),
//     'QHD (2560x1440)': (2560, 1440),
//     'FHD (1920x1080)': (1920, 1080),
//     'HD (1280x720)': (1280, 720),
//   };

//   static const hdmi1Cameras = <String, String>{
//     'Camera 1': 'http://192.168.1.131:8080/hdmi1?url=http://192.168.1.131:9081',
//     'Camera 2': 'http://192.168.1.131:8080/hdmi1?url=http://192.168.1.131:9082',
//     'Camera 3': 'http://192.168.1.131:8080/hdmi1?url=http://192.168.1.131:9083',
//     'Camera 4': 'http://192.168.1.131:8080/hdmi1?url=http://192.168.1.131:9084',
//   };
//   static const hdmi2Cameras = <String, String>{
//     'Camera 1': 'http://192.168.1.131:8080/hdmi2?url=http://192.168.1.131:9081',
//     'Camera 2': 'http://192.168.1.131:8080/hdmi2?url=http://192.168.1.131:9082',
//     'Camera 3': 'http://192.168.1.131:8080/hdmi2?url=http://192.168.1.131:9083',
//     'Camera 4': 'http://192.168.1.131:8080/hdmi2?url=http://192.168.1.131:9084',
//   };

//   // ── Observable state ───────────────────────────────────────────────────
//   final activeIdx = 0.obs;
//   final selectedRes = 'HD (1280x720)'.obs;
//   final selectedHDMI = 'hdmi1'.obs;
//   final selectedCam = 'Camera 1'.obs;

//   // ── Slots ──────────────────────────────────────────────────────────────
//   late final List<SourceSlot> slots;

//   // ── Computed helpers ───────────────────────────────────────────────────
//   int get resW => resolutions[selectedRes.value]!.$1;
//   int get resH => resolutions[selectedRes.value]!.$2;
//   SourceSlot get activeSlot => slots[activeIdx.value];
//   bool get anyRecording => slots.any((s) => s.recording.value);

//   // ── Lifecycle ──────────────────────────────────────────────────────────
//   // onInit runs on the background microtask queue — it does NOT block the
//   // first frame. GetX guarantees the widget tree is built before onInit runs.
//   @override
//   void onInit() {
//     super.onInit();

//     // Build slots synchronously — pure Dart, zero I/O, instant.
//     slots = List.generate(sources.length, (i) {
//       final src = sources[i];
//       return SourceSlot(src, src.urlWithRes(resW, resH));
//     });

//     // Defer everything that touches I/O until after the first frame paints.
//     // Using Future.delayed(Duration.zero) puts work AFTER the current frame
//     // commit, so the Scaffold is already on screen.
//     Future.delayed(Duration.zero, _afterFirstFrame);
//   }

//   Future<void> _afterFirstFrame() async {
//     // Start only the active stream — the rest stay idle until selected.
//     slots[activeIdx.value].mjpeg.start();

//     // Request permissions one-at-a-time with micro-yields between each,
//     // so the engine never starves.  The two dangerous ones (battery opt +
//     // manageExternalStorage) are fired without await to prevent ANR.
//     await _reqPerms();
//   }

//   Future<void> _reqPerms() async {
//     // Safe permissions — await each one individually.
//     for (final p in [Permission.storage, Permission.notification]) {
//       try {
//         if (!(await p.status).isGranted) await p.request();
//       } catch (e) {
//         debugPrint('perm $p: $e');
//       }
//       // Tiny yield so the engine can process events between dialogs.
//       await Future.delayed(const Duration(milliseconds: 50));
//     }

//     // DANGEROUS: these open a full Settings activity.
//     // Awaiting them blocks the Dart isolate until the user closes
//     // the Settings screen => instant ANR after 5 s.
//     // Fire-and-forget only.
//     _fireAndForgetPerm(Permission.manageExternalStorage);
//     _fireAndForgetPerm(Permission.ignoreBatteryOptimizations);
//   }

//   void _fireAndForgetPerm(Permission p) {
//     p.status
//         .then((status) {
//           if (!status.isGranted) p.request().catchError((_) {});
//         })
//         .catchError((_) {});
//   }

//   @override
//   void onClose() {
//     for (final slot in slots) {
//       slot.uiTimer?.cancel();
//       slot.bytesTimer?.cancel();
//       slot.ffSession?.cancel();
//       slot.disposeAll();
//     }
//     _svcStop();
//     super.onClose();
//   }

//   // ── Source switching ───────────────────────────────────────────────────
//   void switchSource(int idx) {
//     if (activeIdx.value == idx) return;
//     slots[activeIdx.value].mjpeg.stop();
//     activeIdx.value = idx;
//     slots[idx].mjpeg.restart(sources[idx].urlWithRes(resW, resH));
//   }

//   // ── Resolution ─────────────────────────────────────────────────────────
//   void setResolution(String r) {
//     if (anyRecording) return;
//     selectedRes.value = r;
//     slots[activeIdx.value].mjpeg.restart(
//       sources[activeIdx.value].urlWithRes(resW, resH),
//     );
//   }

//   // ── Stream refresh ─────────────────────────────────────────────────────
//   void refreshActive() {
//     final s = activeSlot;
//     s.mjpeg.restart(s.mjpeg.currentUrl);
//   }

//   // ── HDMI camera switch ─────────────────────────────────────────────────
//   Future<bool> switchCamera(String hdmi, String camName, String url) async {
//     try {
//       final r = await http
//           .get(Uri.parse(url))
//           .timeout(const Duration(seconds: 5));
//       if (r.statusCode == 200) {
//         selectedHDMI.value = hdmi;
//         selectedCam.value = camName;
//         return true;
//       }
//     } catch (_) {}
//     return false;
//   }

//   // ── FFmpeg ─────────────────────────────────────────────────────────────
//   Map<String, dynamic> _profile(int w) {
//     if (w >= 3840)
//       return {'fps': 5, 'preset': 'ultrafast', 'crf': 35, 'threads': 1};
//     if (w >= 2560)
//       return {'fps': 10, 'preset': 'superfast', 'crf': 30, 'threads': 1};
//     if (w >= 1920)
//       return {'fps': 15, 'preset': 'superfast', 'crf': 28, 'threads': 1};
//     return {'fps': 25, 'preset': 'ultrafast', 'crf': 23, 'threads': 1};
//   }

//   List<String> _ffArgs(int w, int h, String input, String output) {
//     final p = _profile(w);
//     return [
//       '-y',
//       '-reconnect',
//       '1',
//       '-reconnect_streamed',
//       '1',
//       '-reconnect_delay_max',
//       '5',
//       '-f',
//       'mpjpeg',
//       '-r',
//       '${p['fps']}',
//       '-i',
//       input,
//       '-vf',
//       'scale=$w:$h',
//       '-threads',
//       '${p['threads']}',
//       '-c:v',
//       'libx264',
//       '-preset',
//       '${p['preset']}',
//       '-crf',
//       '${p['crf']}',
//       '-x264-params',
//       'ref=1:rc-lookahead=0:weightp=0:weightb=0:no-mbtree:sliced-threads=0:bframes=0',
//       '-pix_fmt',
//       'yuv420p',
//       '-r',
//       '${p['fps']}',
//       '-an',
//       '-movflags',
//       'frag_keyframe+empty_moov+default_base_moof',
//       '-avoid_negative_ts',
//       'make_zero',
//       output,
//     ];
//   }

//   // ── Start recording ────────────────────────────────────────────────────
//   Future<void> startRecording(int idx) async {
//     final slot = slots[idx];
//     if (slot.recording.value || slot.finalising.value) return;

//     if (slot.ffSession != null) {
//       await slot.ffSession!.cancel();
//       slot.ffSession = null;
//     }

//     try {
//       await _svcStart();
//       final ts = DateTime.now().millisecondsSinceEpoch;
//       final w = resW;
//       final h = resH;

//       final extDir = Platform.isAndroid
//           ? await getExternalStorageDirectory()
//           : await getApplicationDocumentsDirectory();
//       if (extDir == null) {
//         await _svcStop();
//         return;
//       }

//       final recDir = Directory('${extDir.path}/Recordings');
//       if (!await recDir.exists()) await recDir.create(recursive: true);

//       final tag = sources[idx].name.replaceAll(' ', '').toLowerCase();
//       slot.outputPath = '${recDir.path}/rec_${w}x${h}_${tag}_$ts.mp4';
//       slot.ffDone = Completer<void>();

//       slot.ffSession = await FFmpegKit.executeWithArgumentsAsync(
//         _ffArgs(w, h, sources[idx].urlWithRes(w, h), slot.outputPath!),
//         (session) async {
//           final rc = await session.getReturnCode();
//           if (rc == null || !ReturnCode.isSuccess(rc)) {
//             final logs = await session.getLogs();
//             for (final l in logs) debugPrint('[FF] ${l.getMessage()}');
//           }
//           if (!(slot.ffDone?.isCompleted ?? true)) slot.ffDone!.complete();
//           slot.bytesTimer?.cancel();
//           slot.ffSession = null;
//           if (!slots.any((s) => s.recording.value || s.finalising.value))
//             await _svcStop();
//           slot.finalising.value = false;
//           slot.status.value = '';
//         },
//         (log) => debugPrint('[FF] ${log.getMessage()}'),
//       );

//       slot.recording.value = true;
//       slot.bytes.value = 0;
//       slot.startTime.value = DateTime.now();
//       slot.status.value = '';

//       slot.bytesTimer = Timer.periodic(const Duration(seconds: 1), (_) {
//         try {
//           final f = File(slot.outputPath!);
//           if (f.existsSync()) {
//             final sz = f.lengthSync();
//             if (sz != slot.bytes.value) slot.bytes.value = sz;
//           }
//         } catch (_) {}
//       });

//       // uiTimer keeps the elapsed-time text ticking every second.
//       // We only need to refresh the timer display — observables handle the rest.
//       slot.uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
//         // Nudge startTime to force Obx to re-render the timer string.
//         // (startTime itself doesn't change; we re-assign to the same value
//         //  just to trigger the reactive listener.)
//         slot.startTime.refresh();
//       });

//       _updateNotif();
//     } catch (e) {
//       await _svcStop();
//       debugPrint('startRecording[$idx]: $e');
//     }
//   }

//   // ── Stop recording ─────────────────────────────────────────────────────
//   Future<void> stopRecording(int idx) async {
//     final slot = slots[idx];
//     if (!slot.recording.value) return;

//     slot.uiTimer?.cancel();
//     slot.bytesTimer?.cancel();

//     slot.recording.value = false;
//     slot.finalising.value = true;
//     slot.status.value = 'Saving video…';

//     await slot.ffSession?.cancel();

//     try {
//       await slot.ffDone?.future.timeout(const Duration(seconds: 45));
//     } catch (_) {
//       debugPrint('[${sources[idx].name}] finalize timeout');
//     }

//     slot.finalising.value = false;
//     slot.status.value = '';
//     _updateNotif();
//   }

//   void _updateNotif() {
//     final names = sources
//         .asMap()
//         .entries
//         .where((e) => slots[e.key].recording.value)
//         .map((e) => e.value.name)
//         .toList();
//     if (names.isEmpty) return;
//     _svcUpdate(
//       names.length == 1
//           ? 'Recording: ${names.first}'
//           : 'Recording ${names.length} sources simultaneously',
//     );
//   }

//   // ── Recordings list ────────────────────────────────────────────────────
//   Future<List<FileSystemEntity>> getRecordings() async {
//     try {
//       final d = Platform.isAndroid
//           ? await getExternalStorageDirectory()
//           : await getApplicationDocumentsDirectory();
//       if (d == null) return [];
//       final dir = Directory('${d.path}/Recordings');
//       if (!await dir.exists()) return [];
//       final list = dir
//           .listSync()
//           .where((f) => f.path.endsWith('.mp4'))
//           .toList();
//       list.sort((a, b) => b.path.compareTo(a.path));
//       return list;
//     } catch (_) {
//       return [];
//     }
//   }

//   // ── Format helpers ─────────────────────────────────────────────────────
//   String fmtDur(int idx) {
//     final st = slots[idx].startTime.value;
//     if (st == null) return '00:00';
//     final d = DateTime.now().difference(st);
//     final h = d.inHours;
//     final m = (d.inMinutes % 60).toString().padLeft(2, '0');
//     final s = (d.inSeconds % 60).toString().padLeft(2, '0');
//     return h > 0 ? '$h:$m:$s' : '$m:$s';
//   }

//   String fmtBytes(int b) {
//     if (b < 1 << 10) return '$b B';
//     if (b < 1 << 20) return '${(b / (1 << 10)).toStringAsFixed(1)} KB';
//     if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
//     return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
//   }
// }
// mjpeg_stream.dart
//
// Architecture:
//   Main isolate  → sends raw HTTP bytes into a SendPort
//   Worker isolate → parses MJPEG, extracts JPEG frames, sends them back
//   Main isolate  → receives Uint8List frames, calls ui.decodeImageFromList
//
// This keeps ALL byte-copying and buffer work off the UI thread.
// ui.decodeImageFromList is a native async call; it does not block the thread.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─── Message types sent to the worker isolate ─────────────────────────────────
class _WorkerInit {
  final SendPort replyTo; // worker sends frames back here
  _WorkerInit(this.replyTo);
}

class _BytesMsg {
  final Uint8List data;
  _BytesMsg(this.data);
}

// Sentinel: worker should clear its parser state and stop sending frames.
class _ResetMsg {
  const _ResetMsg();
}

// ─── MJPEG parser (runs entirely inside the worker isolate) ───────────────────
class _IsoParser {
  // Using Uint8List-backed lists so copies are minimal.
  final _hb = <int>[];
  final _bb = <int>[];
  int _cl = 0;
  int _cr = 0;
  int _state = 0; // 0=header 1=body 2=crlf

  /// Returns completed JPEG frames as Uint8List (zero-copy from the buffer).
  List<Uint8List> feed(Uint8List bytes) {
    final frames = <Uint8List>[];
    int i = 0;
    while (i < bytes.length) {
      switch (_state) {
        case 0: // header
          _hb.add(bytes[i++]);
          final l = _hb.length;
          if (l >= 4 &&
              _hb[l - 4] == 0x0D &&
              _hb[l - 3] == 0x0A &&
              _hb[l - 2] == 0x0D &&
              _hb[l - 1] == 0x0A) {
            _cl = _parseCL();
            _hb.clear();
            _bb.clear();
            if (_cl > 0) _state = 1;
          }
          break;
        case 1: // body
          final need = _cl - _bb.length;
          final avail = bytes.length - i;
          final take = need < avail ? need : avail;
          // addAll with a sublist view avoids an extra allocation.
          _bb.addAll(bytes.sublist(i, i + take));
          i += take;
          if (_bb.length >= _cl) {
            frames.add(Uint8List.fromList(_bb));
            _bb.clear();
            _cl = 0;
            _cr = 0;
            _state = 2;
          }
          break;
        case 2: // crlf
          final b = bytes[i++];
          if (b == 0x0D || b == 0x0A) {
            if (++_cr >= 2) _state = 0;
          } else {
            _state = 0;
            _hb.add(b);
          }
          break;
      }
    }
    return frames;
  }

  int _parseCL() {
    // Scan _hb for "content-length:" without allocating a String.
    final raw = String.fromCharCodes(_hb);
    for (final line in raw.split('\r\n')) {
      final lo = line.toLowerCase();
      if (lo.startsWith('content-length:')) {
        return int.tryParse(line.substring(15).trim()) ?? 0;
      }
    }
    return 0;
  }

  void reset() {
    _hb.clear();
    _bb.clear();
    _cl = 0;
    _cr = 0;
    _state = 0;
  }
}

// ─── Worker isolate entry point ───────────────────────────────────────────────
// Top-level function required by Isolate.spawn.
void _workerEntry(SendPort mainPort) {
  final rp = ReceivePort();
  final parser = _IsoParser();
  mainPort.send(rp.sendPort); // send the worker's input port back to main

  rp.listen((msg) {
    if (msg is _BytesMsg) {
      for (final frame in parser.feed(msg.data)) {
        mainPort.send(frame); // send Uint8List frame back
      }
    } else if (msg is _ResetMsg) {
      parser.reset();
    }
  });
}

// ─── Public MjpegStream class ─────────────────────────────────────────────────
class MjpegStream {
  String _url;

  // Generation counter: every start/restart increments this.
  // Any in-flight work that sees a stale generation exits immediately.
  int _gen = 0;
  bool _disposed = false;

  http.Client? _client;

  // Worker isolate state
  Isolate? _isolate;
  SendPort? _workerPort; // main → worker
  ReceivePort? _fromWorker; // worker → main

  // Decoded frames land here; only _MjpegView listens to this.
  final image = ValueNotifier<ui.Image?>(null);

  MjpegStream(String url) : _url = url;

  String get currentUrl => _url;

  Future<void> start() async {
    if (_disposed) return;
    _gen++;
    await _ensureWorker();
    _httpLoop(_gen);
  }

  void stop() {
    _gen++;
    _client?.close();
    _client = null;
    _workerPort?.send(const _ResetMsg());
  }

  Future<void> restart(String newUrl) async {
    if (_disposed) return;
    _gen++;
    _client?.close();
    _client = null;
    _url = newUrl;

    final old = image.value;
    image.value = null;
    old?.dispose();

    _workerPort?.send(const _ResetMsg());
    await _ensureWorker();
    _httpLoop(_gen);
  }

  Future<void> dispose() async {
    _disposed = true;
    _gen++;
    _client?.close();
    _client = null;

    _fromWorker?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _fromWorker = null;
    _isolate = null;
    _workerPort = null;

    final old = image.value;
    image.value = null;
    old?.dispose();
    image.dispose();
  }

  // ── Spawn the worker isolate once; reuse across restarts. ────────────────
  Future<void> _ensureWorker() async {
    if (_workerPort != null) return; // already alive

    final rp = ReceivePort();
    _fromWorker = rp;

    _isolate = await Isolate.spawn(_workerEntry, rp.sendPort);

    // First message from the worker is its own SendPort.
    final completer = Completer<SendPort>();
    bool decoding = false;

    rp.listen((msg) {
      if (msg is SendPort) {
        completer.complete(msg);
        return;
      }
      // All subsequent messages are Uint8List JPEG frames.
      if (msg is Uint8List && !_disposed) {
        if (decoding) return; // drop frame while previous decode runs
        decoding = true;
        final capturedGen = _gen;
        ui.decodeImageFromList(msg, (decoded) {
          decoding = false;
          if (_disposed || _gen != capturedGen) {
            decoded.dispose();
            return;
          }
          final old = image.value;
          image.value = decoded;
          old?.dispose();
        });
      }
    });

    _workerPort = await completer.future;
  }

  // ── HTTP loop: reads chunks and forwards raw bytes to the worker. ─────────
  // Nothing here touches bytes except forwarding — no parsing, no copying
  // beyond what the http library already does.
  Future<void> _httpLoop(int myGen) async {
    while (!_disposed && _gen == myGen) {
      _client = http.Client();
      final client = _client!;
      try {
        final req = http.Request('GET', Uri.parse(_url))
          ..headers['Connection'] = 'keep-alive'
          ..headers['Cache-Control'] = 'no-cache';

        final resp = await client.send(req).timeout(const Duration(seconds: 8));

        await for (final chunk in resp.stream.timeout(
          const Duration(seconds: 5),
        )) {
          if (_disposed || _gen != myGen) break;
          // Forward raw bytes to the worker isolate.
          // Uint8List avoids an extra copy vs List<int>.
          _workerPort?.send(
            _BytesMsg(chunk is Uint8List ? chunk : Uint8List.fromList(chunk)),
          );
        }
      } catch (e) {
        debugPrint('[MJPEG] connection error: $e — retrying');
      } finally {
        try {
          client.close();
        } catch (_) {}
        if (_client == client) _client = null;
        // Tell the worker to discard any partial frame from the dead connection.
        _workerPort?.send(const _ResetMsg());
      }

      if (!_disposed && _gen == myGen) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }
}
