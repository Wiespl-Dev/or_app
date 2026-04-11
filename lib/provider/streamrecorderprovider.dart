// streamrecorderprovider.dart
import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// ─── Platform Channels ─────────────────────────────────────────────────────────
const _svcCh = MethodChannel(
  'com.example.wiespl_contrl_panel/recording_service',
);
const _fileCh = MethodChannel('com.example.wiespl_contrl_panel/file_open');

Future<void> _svcStart() async {
  try {
    await _svcCh.invokeMethod('startService');
  } catch (e) {
    debugPrint('svcStart: $e');
  }
}

Future<void> _svcStop() async {
  try {
    await _svcCh.invokeMethod('stopService');
  } catch (e) {
    debugPrint('svcStop: $e');
  }
}

Future<void> _svcUpdate(String txt) async {
  try {
    await _svcCh.invokeMethod('updateNotification', {'text': txt});
  } catch (_) {}
}

Future<void> openVideo(String path) async {
  try {
    await _fileCh.invokeMethod('openVideo', {'path': path});
  } catch (e) {
    debugPrint('openVideo: $e');
  }
}

// ─── StorageOption ─────────────────────────────────────────────────────────────
/// Represents one writable storage volume (internal app dir or USB / HDD).
///
/// [path]     – app-specific path from path_provider (Android/data/...)
/// [rootPath] – the real volume root (e.g. /storage/emulated/0 or /storage/XXXX-XXXX)
///              Use this to write to Documents, Downloads, etc.
class StorageOption {
  final String label;
  final String path; // app-specific (kept for backwards-compat)
  final String rootPath; // actual volume root → use for Documents folder
  final bool isRemovable;

  const StorageOption({
    required this.label,
    required this.path,
    required this.rootPath,
    required this.isRemovable,
  });

  /// Absolute path to the Documents folder on this volume.
  String get documentsPath => '$rootPath/Documents';

  @override
  String toString() => '$label ($rootPath)';
}

// ─── Models ───────────────────────────────────────────────────────────────────
class AppSource {
  final int id;
  final String name;
  final String baseUrl;

  const AppSource({
    required this.id,
    required this.name,
    required this.baseUrl,
  });

  String urlWithRes(int w, int h) =>
      '$baseUrl?action=stream&width=$w&height=$h';
}

// ─── Per-source slot ──────────────────────────────────────────────────────────
class SourceSlot {
  final AppSource source;

  final recording = false.obs;
  final finalising = false.obs;
  final bytes = 0.obs;
  final status = ''.obs;
  final startTime = Rxn<DateTime>();

  FFmpegSession? ffSession;
  Completer<void>? ffDone;
  String? outputPath;
  Timer? uiTimer;
  Timer? bytesTimer;

  SourceSlot(this.source);

  bool get isActive => recording.value || finalising.value;
}

// ─── GetX Controller ──────────────────────────────────────────────────────────
class RecorderController extends GetxController {
  static const sources = [
    AppSource(id: 1, name: 'Source 1', baseUrl: 'http://192.168.1.131:9081/'),
    AppSource(id: 2, name: 'Source 2', baseUrl: 'http://192.168.1.131:9082/'),
    AppSource(id: 3, name: 'Source 3', baseUrl: 'http://192.168.1.131:9083/'),
    AppSource(id: 4, name: 'Source 4', baseUrl: 'http://192.168.1.131:9084/'),
  ];

  static const resolutions = <String, (int, int)>{
    '4K (3840x2160)': (3840, 2160),
    'QHD (2560x1440)': (2560, 1440),
    'FHD (1920x1080)': (1920, 1080),
    'HD (1280x720)': (1280, 720),
  };

  static const hdmi1Cameras = <String, String>{
    'Camera 1': 'http://192.168.1.131:9090/hdmi1?url=http://192.168.1.131:9081',
    'Camera 2': 'http://192.168.1.131:9090/hdmi1?url=http://192.168.1.131:9082',
    'Camera 3': 'http://192.168.1.131:9090/hdmi1?url=http://192.168.1.131:9083',
    'Camera 4': 'http://192.168.1.131:9090/hdmi1?url=http://192.168.1.131:9084',
  };
  static const hdmi2Cameras = <String, String>{
    'Camera 1': 'http://192.168.1.131:9090/hdmi2?url=http://192.168.1.131:9081',
    'Camera 2': 'http://192.168.1.131:9090/hdmi2?url=http://192.168.1.131:9082',
    'Camera 3': 'http://192.168.1.131:9090/hdmi2?url=http://192.168.1.131:9083',
    'Camera 4': 'http://192.168.1.131:9090/hdmi2?url=http://192.168.1.131:9084',
  };

  // ── Core reactive state ─────────────────────────────────────────────────
  final activeIdx = 0.obs;
  final selectedRes = 'HD (1280x720)'.obs;
  final selectedHDMI = 'hdmi1'.obs;
  final selectedCam = 'Camera 1'.obs;

  // ── Storage state ───────────────────────────────────────────────────────
  final availableStorages = <StorageOption>[].obs;
  final selectedStorage = Rxn<StorageOption>();

  /// Kept in sync with selectedStorage.rootPath/Documents for FFmpeg default
  /// output (when no patient session path is provided).
  final saveDir = '/storage/emulated/0/Documents/WIESPL_Recordings'.obs;

  // ── Internal ────────────────────────────────────────────────────────────
  late final List<SourceSlot> slots;
  bool _frameInitDone = false;

  int get resW => resolutions[selectedRes.value]!.$1;
  int get resH => resolutions[selectedRes.value]!.$2;
  SourceSlot get activeSlot => slots[activeIdx.value];
  bool get anyRecording => slots.any((s) => s.recording.value);

  // ── onInit ──────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    slots = List.generate(sources.length, (i) => SourceSlot(sources[i]));

    ever(selectedStorage, (StorageOption? opt) {
      if (opt != null) {
        saveDir.value = '${opt.documentsPath}/WIESPL_Recordings';
      }
    });
  }

  // ── initAfterFrame ──────────────────────────────────────────────────────
  void initAfterFrame() {
    if (_frameInitDone) return;
    _frameInitDone = true;

    _firePerms([Permission.storage, Permission.notification]);

    Future.delayed(
      const Duration(seconds: 3),
      () => _firePerms([
        Permission.manageExternalStorage,
        Permission.ignoreBatteryOptimizations,
      ]),
    );

    refreshStorages();
  }

  void _firePerms(List<Permission> perms) {
    for (final p in perms) {
      p.status
          .then((s) {
            if (!s.isGranted) p.request().catchError((_) {});
          })
          .catchError((_) {});
    }
  }

  // ── refreshStorages ──────────────────────────────────────────────────────
  /// Scans all Android storage volumes. Computes [StorageOption.rootPath]
  /// by stripping the Android/data/... app-specific suffix so recordings
  /// land in the real Documents folder, not inside the app's sandboxed dir.
  Future<void> refreshStorages() async {
    final found = <StorageOption>[];

    // ── path_provider volumes ────────────────────────────────────────────
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null) {
        for (int i = 0; i < dirs.length; i++) {
          final dir = dirs[i];
          await dir.create(recursive: true);

          final isRemovable = !dir.path.contains('/emulated/');

          // Strip Android/data/... to get the real volume root.
          final rootPath = _volumeRoot(dir.path);

          String label;
          if (!isRemovable) {
            label = 'Internal Storage';
          } else {
            final volId = rootPath
                .split('/')
                .lastWhere((s) => s.isNotEmpty, orElse: () => 'Removable');
            label = i == 1 ? 'USB / HDD ($volId)' : 'Drive $i ($volId)';
          }

          found.add(
            StorageOption(
              label: label,
              path: dir.path,
              rootPath: rootPath,
              isRemovable: isRemovable,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('refreshStorages/path_provider: $e');
    }

    // ── Fallback: scan /storage for OTG drives ────────────────────────────
    try {
      final storageRoot = Directory('/storage');
      if (storageRoot.existsSync()) {
        final candidates = storageRoot
            .listSync()
            .whereType<Directory>()
            .where((d) => !d.path.endsWith('/emulated'))
            .where((d) => !found.any((f) => f.rootPath == d.path));

        for (final vol in candidates) {
          final testFile = File('${vol.path}/.wiespl_write_test');
          try {
            await testFile.writeAsString('ok');
            await testFile.delete();
            final volId = vol.path.split('/').last;
            found.add(
              StorageOption(
                label: 'External Drive ($volId)',
                path: vol.path,
                rootPath: vol.path, // already the root for manual-scan volumes
                isRemovable: true,
              ),
            );
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('refreshStorages/fallback: $e');
    }

    availableStorages.assignAll(found);

    // Auto-select: keep previous if still mounted, else prefer removable.
    final prev = selectedStorage.value;
    final stillMounted =
        prev != null && found.any((s) => s.rootPath == prev.rootPath);

    if (!stillMounted) {
      selectedStorage.value =
          found.firstWhereOrNull((s) => s.isRemovable) ?? found.firstOrNull;
    }

    debugPrint(
      'refreshStorages: ${found.length} volume(s). '
      'Selected → ${selectedStorage.value?.label ?? "none"} '
      '(root: ${selectedStorage.value?.rootPath})',
    );
  }

  /// Strips the Android/data/<package>/files (or similar) suffix to return
  /// the raw volume root (e.g. /storage/emulated/0 or /storage/XXXX-XXXX).
  static String _volumeRoot(String appPath) {
    final idx = appPath.indexOf('/Android/');
    return idx != -1 ? appPath.substring(0, idx) : appPath;
  }

  // ── onClose ─────────────────────────────────────────────────────────────
  @override
  void onClose() {
    for (final slot in slots) {
      slot.uiTimer?.cancel();
      slot.bytesTimer?.cancel();
      slot.ffSession?.cancel();
    }
    _svcStop();
    super.onClose();
  }

  // ── Source switching ─────────────────────────────────────────────────────
  void switchSource(int idx) {
    if (activeIdx.value == idx) return;
    activeIdx.value = idx;
  }

  // ── Resolution ───────────────────────────────────────────────────────────
  void setResolution(String r) {
    if (anyRecording) return;
    selectedRes.value = r;
  }

  // ── Refresh WebView ──────────────────────────────────────────────────────
  void refreshActive() {
    final cur = activeIdx.value;
    activeIdx.value = -1;
    Future.microtask(() => activeIdx.value = cur);
  }

  // ── HDMI camera switch ───────────────────────────────────────────────────
  Future<bool> switchCamera(String hdmi, String camName, String url) async {
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        selectedHDMI.value = hdmi;
        selectedCam.value = camName;
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── FFmpeg helpers ───────────────────────────────────────────────────────
  Map<String, dynamic> _profile(int w) {
    if (w >= 3840)
      return {'fps': 5, 'preset': 'ultrafast', 'crf': 35, 'threads': 1};
    if (w >= 2560)
      return {'fps': 10, 'preset': 'superfast', 'crf': 30, 'threads': 1};
    if (w >= 1920)
      return {'fps': 15, 'preset': 'superfast', 'crf': 28, 'threads': 1};
    return {'fps': 25, 'preset': 'ultrafast', 'crf': 23, 'threads': 1};
  }

  List<String> _ffArgs(int w, int h, String input, String output) {
    final p = _profile(w);
    return [
      '-y',
      '-reconnect',
      '1',
      '-reconnect_streamed',
      '1',
      '-reconnect_delay_max',
      '5',
      '-f',
      'mpjpeg',
      '-r',
      '${p['fps']}',
      '-i',
      input,
      '-vf',
      'scale=$w:$h',
      '-threads',
      '${p['threads']}',
      '-c:v',
      'libx264',
      '-preset',
      '${p['preset']}',
      '-crf',
      '${p['crf']}',
      '-x264-params',
      'ref=1:rc-lookahead=0:weightp=0:weightb=0:no-mbtree:sliced-threads=0:bframes=0',
      '-pix_fmt',
      'yuv420p',
      '-r',
      '${p['fps']}',
      '-an',
      '-movflags',
      'frag_keyframe+empty_moov+default_base_moof',
      '-avoid_negative_ts',
      'make_zero',
      output,
    ];
  }

  // ── Default recordings directory (no patient session) ────────────────────
  /// Falls back to Documents/WIESPL_Recordings on the selected volume, or
  /// the app's external storage directory as last resort.
  Future<Directory> _resolveDefaultRecDir() async {
    final sel = selectedStorage.value;
    if (sel != null) {
      try {
        final dir = Directory('${sel.documentsPath}/WIESPL_Recordings');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        // quick write-test
        final t = File('${dir.path}/.wtest');
        t.writeAsBytesSync([]);
        t.deleteSync();
        saveDir.value = dir.path;
        return dir;
      } catch (e) {
        debugPrint('_resolveDefaultRecDir/${sel.label}: $e');
      }
    }

    // fallback
    final ext = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    final fb = Directory('${ext!.path}/WIESPL_Recordings');
    if (!fb.existsSync()) fb.createSync(recursive: true);
    saveDir.value = fb.path;
    return fb;
  }

  // ── Start recording ──────────────────────────────────────────────────────
  /// [outputDir] – absolute path to the Recordings sub-folder inside the
  ///               patient session (e.g. .../Source_1/Recordings).
  ///               When null the default directory is used.
  Future<void> startRecording(int idx, {String? outputDir}) async {
    final slot = slots[idx];
    if (slot.recording.value || slot.finalising.value) return;

    if (slot.ffSession != null) {
      await slot.ffSession!.cancel();
      slot.ffSession = null;
    }

    try {
      await _svcStart();

      final ts = DateTime.now().millisecondsSinceEpoch;
      final w = resW;
      final h = resH;
      final tag = sources[idx].name.replaceAll(' ', '').toLowerCase();

      // ── Resolve output path ──────────────────────────────────────────────
      final String recDir;
      if (outputDir != null && outputDir.isNotEmpty) {
        // Patient session folder provided by the UI.
        recDir = outputDir;
        final d = Directory(recDir);
        if (!d.existsSync()) d.createSync(recursive: true);
      } else {
        // No session → default Documents/WIESPL_Recordings.
        final d = await _resolveDefaultRecDir();
        recDir = d.path;
      }

      final finalOutputPath = '$recDir/rec_${w}x${h}_${tag}_$ts.mp4';

      slot.outputPath = finalOutputPath;
      slot.ffDone = Completer<void>();

      slot.ffSession = await FFmpegKit.executeWithArgumentsAsync(
        _ffArgs(w, h, sources[idx].urlWithRes(w, h), slot.outputPath!),
        (session) async {
          final rc = await session.getReturnCode();
          if (rc == null || !ReturnCode.isSuccess(rc)) {
            final logs = await session.getLogs();
            for (final l in logs) debugPrint('[FF] ${l.getMessage()}');
          }
          if (!(slot.ffDone?.isCompleted ?? true)) slot.ffDone!.complete();
          slot.bytesTimer?.cancel();
          slot.ffSession = null;
          if (!slots.any((s) => s.recording.value || s.finalising.value)) {
            await _svcStop();
          }
          slot.finalising.value = false;
          slot.status.value = '';
        },
        (log) => debugPrint('[FF] ${log.getMessage()}'),
      );

      slot.recording.value = true;
      slot.bytes.value = 0;
      slot.startTime.value = DateTime.now();
      slot.status.value = '';

      slot.bytesTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        try {
          final f = File(slot.outputPath!);
          if (f.existsSync()) {
            final sz = f.lengthSync();
            if (sz != slot.bytes.value) slot.bytes.value = sz;
          }
        } catch (_) {}
      });

      slot.uiTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => slot.startTime.refresh(),
      );

      _updateNotif();
    } catch (e) {
      await _svcStop();
      debugPrint('startRecording[$idx]: $e');
    }
  }

  // ── Stop recording ───────────────────────────────────────────────────────
  void stopRecording(int idx) {
    final slot = slots[idx];
    if (!slot.recording.value) return;

    slot.uiTimer?.cancel();
    slot.bytesTimer?.cancel();

    slot.recording.value = false;
    slot.finalising.value = true;
    slot.status.value = 'Saving video…';

    _finaliseAsync(idx, slot);
  }

  Future<void> _finaliseAsync(int idx, SourceSlot slot) async {
    try {
      await slot.ffSession?.cancel();
      await slot.ffDone?.future.timeout(const Duration(seconds: 45));
    } catch (_) {
      debugPrint('[${sources[idx].name}] finalise timeout — continuing');
    } finally {
      slot.finalising.value = false;
      slot.status.value = '';
      _updateNotif();
    }
  }

  void _updateNotif() {
    final names = sources
        .asMap()
        .entries
        .where((e) => slots[e.key].recording.value)
        .map((e) => e.value.name)
        .toList();
    if (names.isEmpty) return;
    _svcUpdate(
      names.length == 1
          ? 'Recording: ${names.first}'
          : 'Recording ${names.length} sources simultaneously',
    );
  }

  // ── Recordings list ──────────────────────────────────────────────────────
  Future<List<FileSystemEntity>> getRecordings() async {
    try {
      final chosen = saveDir.value.trim();
      if (chosen.isNotEmpty) {
        final dir = Directory(chosen);
        if (dir.existsSync()) {
          return dir
              .listSync(recursive: true)
              .where((f) => f.path.endsWith('.mp4'))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
        }
      }
      final d = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      if (d == null) return [];
      final fb = Directory('${d.path}/WIESPL_Recordings');
      if (!fb.existsSync()) return [];
      return fb
          .listSync(recursive: true)
          .where((f) => f.path.endsWith('.mp4'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
    } catch (_) {
      return [];
    }
  }

  // ── Format helpers ───────────────────────────────────────────────────────
  String fmtDur(int idx) {
    final st = slots[idx].startTime.value;
    if (st == null) return '00:00';
    final d = DateTime.now().difference(st);
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String fmtBytes(int b) {
    if (b < 1 << 10) return '$b B';
    if (b < 1 << 20) return '${(b / (1 << 10)).toStringAsFixed(1)} KB';
    if (b < 1 << 30) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  }
}
