// recorder_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:wiespl_contrl_panel/provider/streamrecorderprovider.dart';

// ─── Navigation helper ──────────────────────────────────────────────────────────
void openRecorderPage(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const RecorderPage()));
}

// ─── Page ───────────────────────────────────────────────────────────────────────
class RecorderPage extends StatefulWidget {
  const RecorderPage({Key? key}) : super(key: key);

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage>
    with WidgetsBindingObserver {
  late final RecorderController _c;

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
    if (state == AppLifecycleState.resumed) {
      _c.refreshStorages();
    }
  }

  // ── Storage Picker ────────────────────────────────────────────────────────
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
                    final isSelected = selected?.path == s.path;
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
                      subtitle: _StorageSpaceSubtitle(path: s.path),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: _c.anyRecording
                          ? null
                          : () {
                              _c.selectedStorage.value = s;
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Recording to: ${s.label}'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
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

  // ── HDMI dialog ──────────────────────────────────────────────────────────
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

  // ── Resolution picker ────────────────────────────────────────────────────
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

  // ── Files sheet ──────────────────────────────────────────────────────────
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
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
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
                                      if (ctx2.mounted) {
                                        Navigator.of(ctx2).pop();
                                      }
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('Deleted: $name'),
                                          ),
                                        );
                                      }
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

  // ─── Bottom Storage Button ────────────────────────────────────────────────────────
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
            border: Border(
              top: BorderSide(color: Colors.grey.shade800, width: 1),
            ),
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
                          Text(
                            'RECORDING STORAGE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sel?.label ?? 'No storage selected - Tap to select',
                            style: const TextStyle(
                              fontSize: 14,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wiespl OR'),
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
          Expanded(
            child: Row(
              children: [
                _Sidebar(c: _c),
                Expanded(child: _MainContent(c: _c)),
              ],
            ),
          ),
          _buildBottomStorageButton(),
        ],
      ),
    );
  }
}

// ─── Storage space subtitle ────────────────────────────────────────────────────
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
                  ? '${(usedMb / 1024).toStringAsFixed(1)} GB used / ${(freeMb / 1024).toStringAsFixed(1)} GB free'
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

// ─── Storage status chip for sidebar ───────────────────────────────────────────
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

// ─── Sidebar ───────────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final RecorderController c;
  const _Sidebar({required this.c});

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
              itemBuilder: (_, i) => _SourceTile(c: c, idx: i),
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

// ─── Source Tile with separated selection and record button ───────────────────
class _SourceTile extends StatelessWidget {
  final RecorderController c;
  final int idx;
  const _SourceTile({required this.c, required this.idx});

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
            // Source selection area (click to switch source)
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
            // Divider for visual separation
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
            // Record/Stop button area (only for active source)
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
                              : () => c.startRecording(idx),
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

// ─── Main Content ──────────────────────────────────────────────────────────────
class _MainContent extends StatelessWidget {
  final RecorderController c;
  const _MainContent({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Status bar - fixed height
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
        // WebView - takes remaining space
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

// ─── WebView Stream ────────────────────────────────────────────────────────────
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
            if (mounted) {
              setState(() {
                _loading = true;
                _error = false;
              });
            }
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
            if (mounted) {
              setState(() {
                _loading = false;
                _error = true;
              });
            }
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
                  CircularProgressIndicator(color: Colors.white54),
                  SizedBox(height: 10),
                  Text(
                    'Connecting…',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
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

// ─── HDMI Tile ─────────────────────────────────────────────────────────────────
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

// ─── Blink Widgets ─────────────────────────────────────────────────────────────
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
