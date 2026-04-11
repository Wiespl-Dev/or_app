// recorder_page.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wiespl_contrl_panel/provider/streamrecorderprovider.dart';

// ─── Navigation helper ────────────────────────────────────────────────────────
void openRecorderPage(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const RecorderPage()));
}

// ─── Page ─────────────────────────────────────────────────────────────────────
class RecorderPage extends StatefulWidget {
  const RecorderPage({Key? key}) : super(key: key);

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage>
    with WidgetsBindingObserver {
  late final RecorderController _c;

  // ── Session state ──────────────────────────────────────────────────────
  // A "session" is the folder created when a patient is selected.
  // Multiple source recordings share the same session folder.
  //
  //  Documents/
  //  └── PatientName_MRD/
  //      └── YYYY-MM-DD_HH-mm-ss/      ← _sessionRoot
  //          ├── Source_1/
  //          │   ├── Recordings/        ← videos land here
  //          │   └── Snapshots/         ← photos land here
  //          ├── Source_2/
  //          │   ├── Recordings/
  //          │   └── Snapshots/
  //          └── … (Source_3, Source_4)
  String? _sessionRoot;
  Map<String, dynamic>? _sessionPatient;

  // Assigned patient per slot (for display in the source tile while recording)
  final Map<int, Map<String, dynamic>> _slotPatients = {};

  @override
  void initState() {
    super.initState();
    _c = Get.find<RecorderController>();
    WidgetsBinding.instance
      ..addObserver(this)
      ..addPostFrameCallback((_) {
        _c.initAfterFrame();
        _c.refreshStorages();
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _c.refreshStorages();
  }

  // ── API base URL ─────────────────────────────────────────────────────────
  Future<String> _apiBase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('patient_system_ip');
      if (saved != null && saved.isNotEmpty) {
        String base = saved.startsWith('http') ? saved : 'http://$saved';
        if (!base.contains(':3000')) base = '$base:3000';
        return base;
      }
      if (RecorderController.sources.isNotEmpty) {
        final uri = Uri.tryParse(RecorderController.sources[0].baseUrl);
        if (uri != null) return '${uri.scheme}://${uri.host}:3000';
      }
      return 'http://localhost:3000';
    } catch (_) {
      return 'http://localhost:3000';
    }
  }

  // ── Fetch today's OT schedule ────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchTodayPatients() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedOT = prefs.getString('selected_ot');
    final base = await _apiBase();

    final response = await http
        .get(Uri.parse('$base/api/ot-schedules'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) throw Exception('Server error');

    final List<dynamic> all = jsonDecode(response.body) as List<dynamic>;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    String normalizeOT(String raw) =>
        raw.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');

    final filtered = all
        .where((s) {
          final raw = (s['schedule_date'] ?? '').toString();
          final dateOnly = raw.length >= 10 ? raw.substring(0, 10) : raw;
          final schedOT = normalizeOT(s['ot_name']?.toString() ?? '');
          final selOT = normalizeOT(selectedOT ?? '');
          return dateOnly == todayStr && (selOT.isEmpty || schedOT == selOT);
        })
        .map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s))
        .toList();

    filtered.sort(
      (a, b) => (a['start_time'] ?? '').compareTo(b['start_time'] ?? ''),
    );
    return filtered;
  }

  // ── Sanitise strings for folder names ────────────────────────────────────
  String _sanitize(String raw) =>
      raw.trim().replaceAll(RegExp(r'[^\w\-]'), '_').replaceAll('__', '_');

  // ── Create session folder (called once per patient pick) ─────────────────
  // Layout inside Documents/:
  //   PatientName_MRD/
  //   └── YYYY-MM-DD_HH-mm-ss/
  //       ├── Source_1/{Recordings, Snapshots}
  //       ├── Source_2/{Recordings, Snapshots}
  //       └── …
  Future<String> _createSessionFolder(Map<String, dynamic> patient) async {
    final storage = _c.selectedStorage.value;
    if (storage == null) throw Exception('No storage selected');

    final mrd = _sanitize(patient['mrd_number']?.toString() ?? 'UNKNOWN');
    final name = _sanitize(patient['patient_name']?.toString() ?? 'Patient');
    final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());

    // ── use rootPath so we write to the real Documents folder, not
    //    Android/data/<package>/files
    final sessionRoot = '${storage.documentsPath}/${name}_$mrd/$ts';

    // Pre-create all Source sub-folders so they're visible immediately
    for (int i = 1; i <= RecorderController.sources.length; i++) {
      await Directory(
        '$sessionRoot/Source_$i/Recordings',
      ).create(recursive: true);
      await Directory(
        '$sessionRoot/Source_$i/Snapshots',
      ).create(recursive: true);
    }

    return sessionRoot;
  }

  // ── START RECORDING button handler ───────────────────────────────────────
  Future<void> _onStartRecording(int slotIdx) async {
    // 1. Storage check
    if (_c.selectedStorage.value == null) {
      _snack('⚠ Please select a storage device first', Colors.orange);
      return;
    }

    // 2a. Already have a session → ask Continue / New patient
    if (_sessionRoot != null && _sessionPatient != null) {
      final choice = await _showSessionChoiceDialog();
      if (choice == null) return; // user closed dialog

      if (choice == _SessionChoice.newPatient) {
        // Pick fresh patient and create a new session
        final picked = await _showPatientPicker();
        if (picked == null || !mounted) return;
        await _startNewSession(picked, slotIdx);
      } else {
        // Continue with current patient / session
        await _startRecordingInSession(slotIdx);
      }
      return;
    }

    // 2b. No active session → show patient picker
    final picked = await _showPatientPicker();
    if (picked == null || !mounted) return;
    await _startNewSession(picked, slotIdx);
  }

  // ── Start a brand-new session for a newly picked patient ─────────────────
  Future<void> _startNewSession(
    Map<String, dynamic> patient,
    int slotIdx,
  ) async {
    String sessionRoot;
    try {
      sessionRoot = await _createSessionFolder(patient);
    } catch (e) {
      if (mounted) _snack('Could not create folder: $e', Colors.red);
      return;
    }

    setState(() {
      _sessionRoot = sessionRoot;
      _sessionPatient = patient;
    });

    await _startRecordingInSession(slotIdx, patient: patient);
  }

  // ── Start recording for a specific slot inside the current session ────────
  Future<void> _startRecordingInSession(
    int slotIdx, {
    Map<String, dynamic>? patient,
  }) async {
    final p = patient ?? _sessionPatient!;
    final recordingsDir = '$_sessionRoot/Source_${slotIdx + 1}/Recordings';

    // Ensure directory exists (should already, but be safe)
    await Directory(recordingsDir).create(recursive: true);

    setState(() => _slotPatients[slotIdx] = p);

    _c.startRecording(slotIdx, outputDir: recordingsDir);

    if (mounted) {
      final name = p['patient_name'] ?? 'Patient';
      final mrd = p['mrd_number'] ?? '';
      _snack(
        '● Recording  $name ($mrd)\n📁 $recordingsDir',
        Colors.green.shade700,
        duration: const Duration(seconds: 5),
      );
    }
  }

  // ── Session-choice dialog ────────────────────────────────────────────────
  Future<_SessionChoice?> _showSessionChoiceDialog() async {
    final patName = _sessionPatient?['patient_name'] ?? 'current patient';
    final mrd = _sessionPatient?['mrd_number'] ?? '';

    return showDialog<_SessionChoice>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.folder_special,
                    color: Colors.orangeAccent,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Active Patient Session',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (mrd.isNotEmpty)
                      Text(
                        'MRD: $mrd',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Continue with same patient
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, _SessionChoice.samePatient),
                  icon: const Icon(
                    Icons.fiber_manual_record,
                    color: Colors.red,
                    size: 16,
                  ),
                  label: const Text('Continue — same patient'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // New patient
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, _SessionChoice.newPatient),
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: const Text('New patient'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showPatientPicker() {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PatientPickerDialog(fetchPatients: _fetchTodayPatients),
    );
  }

  void _snack(
    String msg,
    Color bg, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg, duration: duration),
    );
  }

  // ─── Storage Picker ───────────────────────────────────────────────────────
  void _showStoragePicker(BuildContext context) async {
    await _c.refreshStorages();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Obx(() {
        final storages = _c.availableStorages;
        final selected = _c.selectedStorage.value;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storage_rounded, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Select Storage',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Re-scan',
                    onPressed: () => _c.refreshStorages(),
                  ),
                ],
              ),
              const Divider(),
              if (storages.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No storage volumes found.\nConnect a USB drive and tap ↺.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: storages.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) {
                    final s = storages[i];
                    final isSelected = selected?.rootPath == s.rootPath;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: s.isRemovable
                            ? Colors.green.shade700
                            : Colors.blueGrey.shade700,
                        child: Icon(
                          s.isRemovable
                              ? Icons.usb_rounded
                              : Icons.phone_android,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        s.label,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StorageSpaceSubtitle(path: s.rootPath),
                          Text(
                            'Documents: ${s.documentsPath}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white38,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: _c.anyRecording
                          ? null
                          : () {
                              _c.selectedStorage.value = s;
                              // Clear any existing session since storage changed
                              setState(() {
                                _sessionRoot = null;
                                _sessionPatient = null;
                                _slotPatients.clear();
                              });
                              Navigator.of(ctx).pop();
                              _snack('Storage: ${s.label}', Colors.blueGrey);
                            },
                    );
                  },
                ),
              if (_c.anyRecording)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Stop all recordings before changing storage.',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  void _showHDMIDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select HDMI & Camera'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HdmiTile(
                context: context,
                label: 'HDMI 1',
                hdmiKey: 'hdmi1',
                icon: Icons.tv,
                color: Colors.blue,
                cameras: RecorderController.hdmi1Cameras,
              ),
              _HdmiTile(
                context: context,
                label: 'HDMI 2',
                hdmiKey: 'hdmi2',
                icon: Icons.live_tv,
                color: Colors.green,
                cameras: RecorderController.hdmi2Cameras,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showResPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Obx(
        () => ListView(
          shrinkWrap: true,
          children: RecorderController.resolutions.keys.map((r) {
            return ListTile(
              title: Text(r),
              trailing: _c.selectedRes.value == r
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.of(ctx).pop();
                _c.setResolution(r);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showFiles(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, sc) => FutureBuilder<List<FileSystemEntity>>(
          future: _c.getRecordings(),
          builder: (ctx2, snap) {
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());
            final files = snap.data!;
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
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
                          itemBuilder: (_, i) {
                            final name = files[i].path.split('/').last;
                            final size = File(files[i].path).lengthSync();
                            return ListTile(
                              leading: const Icon(
                                Icons.movie,
                                color: Colors.red,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              subtitle: Text(
                                _c.fmtBytes(size),
                                style: const TextStyle(fontSize: 10),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.play_arrow),
                                    onPressed: () {
                                      Navigator.of(ctx2).pop();
                                      openVideo(files[i].path);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () async {
                                      await File(files[i].path).delete();
                                      if (ctx2.mounted)
                                        Navigator.of(ctx2).pop();
                                      if (context.mounted)
                                        _snack('Deleted: $name', Colors.grey);
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomStorageButton() {
    return Obx(() {
      final sel = _c.selectedStorage.value;
      final isUsb = sel?.isRemovable ?? false;

      return SizedBox(
        height: 76,
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            border: Border(top: BorderSide(color: Colors.grey.shade800)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () => _showStoragePicker(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: sel == null
                    ? Colors.red.shade700
                    : isUsb
                    ? Colors.green.shade700
                    : Colors.blueGrey.shade700,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 56),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      sel == null
                          ? Icons.warning_rounded
                          : isUsb
                          ? Icons.usb_rounded
                          : Icons.sd_storage_rounded,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'RECORDING STORAGE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sel == null
                                ? 'No storage selected — Tap to select'
                                : '${sel.label}  •  ${sel.documentsPath}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  // ── Active session banner ────────────────────────────────────────────────
  Widget _buildSessionBanner() {
    if (_sessionPatient == null) return const SizedBox.shrink();
    final name = _sessionPatient!['patient_name'] ?? '';
    final mrd = _sessionPatient!['mrd_number'] ?? '';
    return Container(
      color: const Color(0xFF2D1B69),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.folder_open, color: Colors.orangeAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Session: $name  ·  MRD: $mrd',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Show the session root path in a tooltip
          Tooltip(
            message: _sessionRoot ?? '',
            child: const Icon(
              Icons.info_outline,
              color: Colors.white38,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          // Clear session button (only when nothing is recording)
          Obx(
            () => _c.anyRecording
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: () => setState(() {
                      _sessionRoot = null;
                      _sessionPatient = null;
                      _slotPatients.clear();
                    }),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white38,
                      size: 16,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 68, 49, 127),
        foregroundColor: Colors.white,
        title: const Text('Wiespl OR', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.input, color: Colors.blue),
            tooltip: 'HDMI Camera',
            onPressed: () => _showHDMIDialog(context),
          ),
          Obx(
            () => IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _c.anyRecording ? null : () => _showResPicker(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder),
            onPressed: () => _showFiles(context),
          ),
          Obx(
            () => IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _c.anyRecording ? null : _c.refreshActive,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Session banner (shows current patient + folder)
          _buildSessionBanner(),

          Expanded(
            child: Row(
              children: [
                _Sidebar(
                  c: _c,
                  slotPatients: _slotPatients,
                  onStartRecording: _onStartRecording,
                ),
                Expanded(child: _MainContent(c: _c)),
                const _PatientListSidebar(),
              ],
            ),
          ),
          _buildBottomStorageButton(),
        ],
      ),
    );
  }
}

// ─── Session choice enum ──────────────────────────────────────────────────────
enum _SessionChoice { samePatient, newPatient }

// ─── Patient Picker Dialog ────────────────────────────────────────────────────
class _PatientPickerDialog extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() fetchPatients;
  const _PatientPickerDialog({required this.fetchPatients});

  @override
  State<_PatientPickerDialog> createState() => _PatientPickerDialogState();
}

class _PatientPickerDialogState extends State<_PatientPickerDialog> {
  List<Map<String, dynamic>> _patients = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.fetchPatients();
      if (mounted)
        setState(() {
          _patients = list;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _patients;
    final q = _search.toLowerCase();
    return _patients
        .where(
          (p) =>
              (p['patient_name'] ?? '').toLowerCase().contains(q) ||
              (p['mrd_number'] ?? '').toLowerCase().contains(q) ||
              (p['surgeon'] ?? '').toLowerCase().contains(q) ||
              (p['procedure_type'] ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  Color _statusColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'scheduled':
        return Colors.orange;
      case 'in progress':
        return Colors.red;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blueAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Container(
        width: 520,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.purple.shade800, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF2D1B69),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.purple.shade800),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.fiber_manual_record,
                      color: Colors.red,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Patient to Record',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Folder → Documents / Name_MRD / Date / Source_N / Recordings',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search by name, MRD, surgeon…',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: Colors.grey,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF252540),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),

            // Body
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(height: 12),
                            Text(
                              "Loading today's schedule…",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_off,
                            color: Colors.red.shade300,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Colors.red.shade300,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh, color: Colors.blue),
                            label: const Text(
                              'Retry',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_busy,
                            color: Colors.white24,
                            size: 40,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No patients scheduled today\nfor this OT',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final p = _filtered[i];
                        final status = p['status']?.toString() ?? 'Scheduled';
                        final color = _statusColor(status);
                        final name = p['patient_name'] ?? 'Unknown';
                        final mrd = p['mrd_number'] ?? '—';
                        final surgeon = p['surgeon'] ?? '—';
                        final proc = p['procedure_type'] ?? '—';
                        final t0 = p['start_time'] ?? '';
                        final t1 = p['end_time'] ?? '';
                        final timeLabel = t0.isNotEmpty
                            ? (t1.isNotEmpty ? '$t0 – $t1' : t0)
                            : '—';
                        final otName = p['ot_name'] ?? '—';

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(context).pop(p),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22223A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white12,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: color,
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${i + 1}',
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            _StatusChip(
                                              status: status,
                                              color: color,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        _PickerRow(
                                          icon: Icons.badge_outlined,
                                          v: mrd,
                                          icon2: Icons.schedule,
                                          v2: timeLabel,
                                        ),
                                        const SizedBox(height: 3),
                                        _PickerRow(
                                          icon: Icons.local_hospital_outlined,
                                          v: proc,
                                          icon2: Icons.meeting_room,
                                          v2: otName,
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.person_outline,
                                              size: 11,
                                              color: Colors.grey.shade500,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                surgeon,
                                                style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 11,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 14,
                                    color: Colors.white24,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_special,
                    size: 13,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Documents / PatientName_MRD / Date_Time / Source_N / {Recordings, Snapshots}',
                      style: TextStyle(color: Colors.white30, fontSize: 9),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small shared widgets ─────────────────────────────────────────────────────
class _PickerRow extends StatelessWidget {
  final IconData icon, icon2;
  final String v, v2;
  const _PickerRow({
    required this.icon,
    required this.v,
    required this.icon2,
    required this.v2,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 11, color: Colors.grey.shade500),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          v,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      Icon(icon2, size: 11, color: Colors.grey.shade500),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          v2,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;
  const _StatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color, width: 0.5),
    ),
    child: Text(
      status,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
    ),
  );
}

// ─── Patient List Sidebar (right panel) ──────────────────────────────────────
class _PatientListSidebar extends StatefulWidget {
  const _PatientListSidebar({Key? key}) : super(key: key);

  @override
  State<_PatientListSidebar> createState() => _PatientListSidebarState();
}

class _PatientListSidebarState extends State<_PatientListSidebar> {
  static const List<String> _otNumbers = [
    'OT 1',
    'OT 2',
    'OT 3',
    'OT 4',
    'OT 5',
  ];

  bool _isExpanded = true;
  String _searchQuery = '';
  String? _selectedOT;
  List<Map<String, dynamic>> _patients = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final ot = prefs.getString('selected_ot');
    if (mounted) setState(() => _selectedOT = ot);
    await _fetchTodayPatients();
  }

  Future<String> _getApiBase() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('patient_system_ip');
    if (saved != null && saved.isNotEmpty) {
      String base = saved.startsWith('http') ? saved : 'http://$saved';
      if (!base.contains(':3000')) base = '$base:3000';
      return base;
    }
    if (RecorderController.sources.isNotEmpty) {
      final uri = Uri.tryParse(RecorderController.sources[0].baseUrl);
      if (uri != null) return '${uri.scheme}://${uri.host}:3000';
    }
    return 'http://localhost:3000';
  }

  Future<void> _fetchTodayPatients() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = await _getApiBase();
      final response = await http
          .get(Uri.parse('$base/api/ot-schedules'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> all = jsonDecode(response.body) as List<dynamic>;
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final filtered = all
            .where((s) {
              final raw = (s['schedule_date'] ?? '').toString();
              final dateOnly = raw.length >= 10 ? raw.substring(0, 10) : raw;
              final schedOT = _normalizeOT(s['ot_name']?.toString() ?? '');
              final selOT = _normalizeOT(_selectedOT ?? '');
              return dateOnly == todayStr &&
                  (selOT.isEmpty || schedOT == selOT);
            })
            .map<Map<String, dynamic>>((s) => Map<String, dynamic>.from(s))
            .toList();
        filtered.sort(
          (a, b) => (a['start_time'] ?? '').compareTo(b['start_time'] ?? ''),
        );
        if (mounted)
          setState(() {
            _patients = filtered;
            _loading = false;
          });
      } else {
        if (mounted)
          setState(() {
            _error = 'Server error ${response.statusCode}';
            _loading = false;
          });
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _error = 'Cannot reach server';
          _loading = false;
        });
    }
  }

  String _normalizeOT(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');

  Future<void> _saveOTAndRefresh(String? ot) async {
    final prefs = await SharedPreferences.getInstance();
    if (ot == null) {
      await prefs.remove('selected_ot');
    } else {
      await prefs.setString('selected_ot', ot);
    }
    if (mounted) setState(() => _selectedOT = ot);
    await _fetchTodayPatients();
  }

  List<Map<String, dynamic>> get _filteredPatients {
    if (_searchQuery.isEmpty) return _patients;
    final q = _searchQuery.toLowerCase();
    return _patients
        .where(
          (p) =>
              (p['patient_name'] ?? '').toLowerCase().contains(q) ||
              (p['mrd_number'] ?? '').toLowerCase().contains(q) ||
              (p['surgeon'] ?? '').toLowerCase().contains(q) ||
              (p['procedure_type'] ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'scheduled':
        return Colors.orange;
      case 'in progress':
        return Colors.red;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blueAccent;
    }
  }

  void _showOTPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select OT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text(
                'All OTs',
                style: TextStyle(color: Colors.white),
              ),
              trailing: _selectedOT == null
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _saveOTAndRefresh(null);
              },
            ),
            const Divider(color: Colors.grey),
            ..._otNumbers.map(
              (ot) => ListTile(
                leading: const Icon(
                  Icons.meeting_room,
                  color: Colors.blue,
                  size: 18,
                ),
                title: Text(ot, style: const TextStyle(color: Colors.white)),
                trailing: _selectedOT == ot
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _saveOTAndRefresh(ot);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isExpanded ? 300 : 48,
      color: Colors.grey.shade900,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: _isExpanded
                ? Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _showOTPicker,
                          child: Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.blue.shade700),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.meeting_room,
                                  color: Colors.blue,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _selectedOT ?? 'All OTs',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.blue,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white54,
                                ),
                              )
                            : const Icon(
                                Icons.refresh,
                                color: Colors.white54,
                                size: 18,
                              ),
                        onPressed: _loading ? null : _fetchTodayPatients,
                        tooltip: 'Refresh',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                        ),
                        onPressed: () => setState(() => _isExpanded = false),
                      ),
                    ],
                  )
                : IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: () => setState(() => _isExpanded = true),
                  ),
          ),

          if (_isExpanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people, color: Colors.blue, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        "TODAY'S PATIENTS",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _todayLabel(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search patient, MRD…',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 18,
                        color: Colors.grey,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade800,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _error != null
                  ? Row(
                      children: [
                        Icon(
                          Icons.wifi_off,
                          size: 12,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Colors.red.shade300,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: _fetchTodayPatients,
                          child: Text(
                            'Retry',
                            style: TextStyle(
                              color: Colors.blue.shade300,
                              fontSize: 10,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_filteredPatients.length} patient'
                          '${_filteredPatients.length == 1 ? '' : 's'} scheduled',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 8),

            Expanded(
              child: _loading && _patients.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2),
                          SizedBox(height: 12),
                          Text(
                            'Loading patients…',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _filteredPatients.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_busy,
                            color: Colors.grey.shade600,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No patients scheduled\nfor today',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _filteredPatients.length,
                      itemBuilder: (_, i) {
                        final p = _filteredPatients[i];
                        return _PatientCard(
                          patient: p,
                          statusColor: _statusColor(p['status']?.toString()),
                          index: i + 1,
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${now.day} ${months[now.month]}';
  }
}

// ─── Patient Card (right sidebar) ────────────────────────────────────────────
class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> patient;
  final Color statusColor;
  final int index;
  const _PatientCard({
    required this.patient,
    required this.statusColor,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final name = patient['patient_name'] ?? 'Unknown';
    final mrd = patient['mrd_number'] ?? '—';
    final procedure = patient['procedure_type'] ?? '—';
    final surgeon = patient['surgeon'] ?? '—';
    final status = patient['status'] ?? 'Scheduled';
    final t0 = patient['start_time'] ?? '';
    final t1 = patient['end_time'] ?? '';
    final timeLabel = t0.isNotEmpty ? (t1.isNotEmpty ? '$t0 – $t1' : t0) : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey.shade800,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name · MRD: $mrd'),
            duration: const Duration(seconds: 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        '$index',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 11,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    mrd,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.schedule, size: 11, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    timeLabel,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.local_hospital_outlined,
                    size: 11,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      procedure,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 11,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      surgeon,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor, width: 0.5),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Left Sidebar ─────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final RecorderController c;
  final Map<int, Map<String, dynamic>> slotPatients;
  final Future<void> Function(int) onStartRecording;

  const _Sidebar({
    required this.c,
    required this.slotPatients,
    required this.onStartRecording,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: Colors.grey.shade900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'SOURCES',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: RecorderController.sources.length,
              itemBuilder: (_, i) => _SourceTile(
                c: c,
                idx: i,
                assignedPatient: slotPatients[i],
                onStartRecording: onStartRecording,
              ),
            ),
          ),
          _SidebarFooter(c: c),
        ],
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  final RecorderController c;
  const _SidebarFooter({required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final recCount = c.slots.where((s) => s.recording.value).length;
      final anyRec = recCount > 0;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey.shade800)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ACTIVE SOURCE',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              c.activeIdx.value >= 0
                  ? RecorderController.sources[c.activeIdx.value].name
                  : '…',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              c.selectedRes.value,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
            ),
            const SizedBox(height: 4),
            Text(
              '$recCount recording',
              style: TextStyle(
                color: anyRec ? Colors.red.shade300 : Colors.grey.shade600,
                fontSize: 11,
              ),
            ),
            _StorageStatusChip(c: c),
          ],
        ),
      );
    });
  }
}

// ─── Source Tile ──────────────────────────────────────────────────────────────
class _SourceTile extends StatelessWidget {
  final RecorderController c;
  final int idx;
  final Map<String, dynamic>? assignedPatient;
  final Future<void> Function(int) onStartRecording;

  const _SourceTile({
    required this.c,
    required this.idx,
    required this.assignedPatient,
    required this.onStartRecording,
  });

  @override
  Widget build(BuildContext context) {
    final src = RecorderController.sources[idx];
    final slot = c.slots[idx];

    return Obx(() {
      final isRec = slot.recording.value;
      final isFin = slot.finalising.value;
      final isActive = c.activeIdx.value == idx;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isActive
              ? Colors.blue.withOpacity(0.2)
              : isRec
              ? Colors.red.withOpacity(0.1)
              : Colors.transparent,
          border: Border.all(
            color: isRec
                ? Colors.red.shade700
                : isActive
                ? Colors.blue.shade700
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              onTap: () => c.switchSource(idx),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isRec
                            ? Colors.red
                            : isActive
                            ? Colors.blue
                            : Colors.grey.shade700,
                      ),
                      child: Center(
                        child: isRec
                            ? const _BlinkDot()
                            : Text(
                                '${src.id}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            src.name,
                            style: TextStyle(
                              color: isActive
                                  ? Colors.white
                                  : Colors.grey.shade300,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),

                          // Folder info tag (shown before recording starts and while recording)
                          if (assignedPatient != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.folder,
                                  size: 10,
                                  color: Colors.orangeAccent.withOpacity(0.8),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Source_${idx + 1}/Recordings  •  '
                                    '${assignedPatient!['patient_name'] ?? ''}',
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 9,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          if (isRec) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.timer,
                                  size: 12,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  c.fmtDur(idx),
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.data_usage,
                                  size: 12,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  c.fmtBytes(slot.bytes.value),
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (isFin) ...[
                            const SizedBox(height: 4),
                            Text(
                              slot.status.value,
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isRec)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Colors.red, size: 8),
                            SizedBox(width: 4),
                            Text(
                              'REC',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            if (isActive || isRec || isFin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Divider(
                  height: 1,
                  color: isRec
                      ? Colors.red.shade700
                      : isActive
                      ? Colors.blue.shade700
                      : Colors.grey.shade700,
                ),
              ),

            if (isActive)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: isFin
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: isRec
                              ? () => c.stopRecording(idx)
                              : () => onStartRecording(idx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isRec
                                ? Colors.red.shade800
                                : Colors.green.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isRec ? Icons.stop : Icons.fiber_manual_record,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isRec ? 'STOP RECORDING' : 'START RECORDING',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

// ─── Main Content ─────────────────────────────────────────────────────────────
class _MainContent extends StatelessWidget {
  final RecorderController c;
  const _MainContent({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Obx(() {
          final idx = c.activeIdx.value;
          final slot = idx >= 0 ? c.activeSlot : null;
          final isRec = slot?.recording.value ?? false;
          final isFin = slot?.finalising.value ?? false;
          return SizedBox(
            height: 48,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: isRec
                  ? Colors.red.shade700
                  : isFin
                  ? Colors.orange.shade700
                  : Colors.blue.shade700,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      idx >= 0 ? RecorderController.sources[idx].name : '…',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isRec
                          ? '● REC  ${c.selectedRes.value}  '
                                '${c.fmtDur(idx)}  '
                                '${c.fmtBytes(slot!.bytes.value)}'
                          : isFin
                          ? '⏳ ${slot!.status.value}'
                          : '${c.selectedRes.value}  •  Ready',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        Expanded(
          child: Obx(() {
            final idx = c.activeIdx.value;
            final isRec = idx >= 0 && c.activeSlot.recording.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (idx >= 0)
                  _StreamWebView(
                    key: ValueKey(idx),
                    url: RecorderController.sources[idx].baseUrl,
                  )
                else
                  const Center(child: CircularProgressIndicator()),
                if (isRec)
                  const Positioned(top: 12, right: 12, child: _Blink()),
              ],
            );
          }),
        ),
      ],
    );
  }
}

// ─── WebView Stream ───────────────────────────────────────────────────────────
class _StreamWebView extends StatefulWidget {
  final String url;
  const _StreamWebView({Key? key, required this.url}) : super(key: key);

  @override
  State<_StreamWebView> createState() => _StreamWebViewState();
}

class _StreamWebViewState extends State<_StreamWebView> {
  late final WebViewController _wvc;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _wvc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted)
              setState(() {
                _loading = true;
                _error = false;
              });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _wvc.runJavaScript('''
            document.body.style.margin="0";
            document.body.style.padding="0";
            document.body.style.background="#000";
            document.body.style.overflow="hidden";
            var img=document.querySelector("img");
            if(img){img.style.width="100vw";img.style.height="100vh";
            img.style.objectFit="contain";img.style.display="block";}
          ''');
          },
          onWebResourceError: (_) {
            if (mounted)
              setState(() {
                _loading = false;
                _error = true;
              });
          },
        ),
      );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _wvc.loadRequest(Uri.parse(widget.url));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _wvc),
          if (_loading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // CircularProgressIndicator(color: Colors.white54),
                  // SizedBox(height: 10),
                  // Text(
                  //   'Connecting…',
                  //   style: TextStyle(color: Colors.white54, fontSize: 12),
                  // ),
                ],
              ),
            ),
          if (_error)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white54, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Stream unavailable',
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = false;
                      });
                      _wvc.reload();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── HDMI Tile ────────────────────────────────────────────────────────────────
class _HdmiTile extends StatelessWidget {
  final BuildContext context;
  final String label, hdmiKey;
  final IconData icon;
  final Color color;
  final Map<String, String> cameras;

  const _HdmiTile({
    required this.context,
    required this.label,
    required this.hdmiKey,
    required this.icon,
    required this.color,
    required this.cameras,
  });

  @override
  Widget build(BuildContext _) {
    final c = Get.find<RecorderController>();
    return Obx(
      () => ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        children: cameras.entries.map((e) {
          final selected =
              c.selectedHDMI.value == hdmiKey && c.selectedCam.value == e.key;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.2),
              child: Text(e.key.split(' ').last),
            ),
            title: Text(e.key),
            subtitle: Text(e.value, style: const TextStyle(fontSize: 10)),
            trailing: selected
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () async {
              Navigator.of(context).pop();
              final ok = await c.switchCamera(hdmiKey, e.key, e.value);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? '✓ $label ${e.key} switched' : 'Connection failed',
                    ),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
              }
            },
          );
        }).toList(),
      ),
    );
  }
}

// ─── Storage space subtitle ───────────────────────────────────────────────────
class _StorageSpaceSubtitle extends StatefulWidget {
  final String path;
  const _StorageSpaceSubtitle({required this.path});

  @override
  State<_StorageSpaceSubtitle> createState() => _StorageSpaceSubtitleState();
}

class _StorageSpaceSubtitleState extends State<_StorageSpaceSubtitle> {
  String _label = 'Checking…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Process.run('df', [
        '-k',
        '--output=size,avail',
        widget.path,
      ], runInShell: true);
      final lines = result.stdout
          .toString()
          .trim()
          .split('\n')
          .where((l) => !l.startsWith('1K'))
          .toList();
      if (lines.isNotEmpty) {
        final parts = lines.last
            .trim()
            .split(RegExp(r'\s+'))
            .map(int.tryParse)
            .whereType<int>()
            .toList();
        if (parts.length >= 2) {
          final totalMb = parts[0] ~/ 1024;
          final freeMb = parts[1] ~/ 1024;
          final usedMb = totalMb - freeMb;
          if (mounted) {
            setState(() {
              _label = totalMb > 1024
                  ? '${(usedMb / 1024).toStringAsFixed(1)} GB used / '
                        '${(freeMb / 1024).toStringAsFixed(1)} GB free'
                  : '$usedMb MB used / $freeMb MB free';
            });
          }
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _label = 'Space unavailable');
  }

  @override
  Widget build(BuildContext context) =>
      Text(_label, style: const TextStyle(fontSize: 10, color: Colors.white70));
}

// ─── Storage status chip ──────────────────────────────────────────────────────
class _StorageStatusChip extends StatelessWidget {
  final RecorderController c;
  const _StorageStatusChip({required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final sel = c.selectedStorage.value;
      if (sel == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: sel.isRemovable
              ? Colors.green.withOpacity(0.15)
              : Colors.blueGrey.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: sel.isRemovable
                ? Colors.green.shade700
                : Colors.blueGrey.shade700,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sel.isRemovable ? Icons.usb_rounded : Icons.phone_android,
              size: 12,
              color: sel.isRemovable ? Colors.green : Colors.blueGrey,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                sel.label,
                style: TextStyle(
                  fontSize: 10,
                  color: sel.isRemovable
                      ? Colors.green
                      : Colors.blueGrey.shade300,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ─── Blink Widgets ────────────────────────────────────────────────────────────
class _Blink extends StatefulWidget {
  const _Blink();
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

class _BlinkDot extends StatefulWidget {
  const _BlinkDot();
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: const Icon(Icons.circle, color: Colors.white, size: 10),
  );
}
