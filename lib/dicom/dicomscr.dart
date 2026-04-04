import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:fluttertoast/fluttertoast.dart';

// ── Channel name matches MainActivity.kt DICOM_CHANNEL ────────────────────────
const _channel = MethodChannel('com.example.wiespl_contrl_panel/dicom');

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg = Color(0xFF0A0A0F);
const _surface = Color(0xFF0D0D15);
const _card = Color(0xFF12121A);
const _border = Color(0xFF1E1E2E);
const _dim = Color(0xFF2A2A3C);
const _muted = Color(0xFF3A3A5C);
const _cyan = Color(0xFF00D4FF);
const _violet = Color(0xFF7B61FF);
const _red = Color(0xFFFF6B6B);

// ── Single DICOM image model ───────────────────────────────────────────────────
class DicomImage {
  final String path;
  final String name;
  Uint8List? pngBytes;
  String patientName;
  String modality;
  String studyDate;
  String institution;
  String studyDescription;
  String seriesDescription;
  String windowCenter;
  String windowWidth;
  bool loading;
  String? error;
  DateTime? loadedAt;

  DicomImage({
    required this.path,
    required this.name,
    this.pngBytes,
    this.patientName = '',
    this.modality = '',
    this.studyDate = '',
    this.institution = '',
    this.studyDescription = '',
    this.seriesDescription = '',
    this.windowCenter = '',
    this.windowWidth = '',
    this.loading = false,
    this.error,
    this.loadedAt,
  });
}

// ── Crosshair overlay painter ─────────────────────────────────────────────────
class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.45)
      ..strokeWidth = 1;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
    canvas.drawCircle(
      Offset(cx, cy),
      14,
      Paint()
        ..color = Colors.greenAccent.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => false;
}

// ── Grid overlay painter ──────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

// ── Page ──────────────────────────────────────────────────────────────────────
class DicomViewerPage extends StatefulWidget {
  const DicomViewerPage({Key? key}) : super(key: key);
  @override
  State<DicomViewerPage> createState() => _DicomViewerPageState();
}

class _DicomViewerPageState extends State<DicomViewerPage>
    with SingleTickerProviderStateMixin {
  // Images
  final List<DicomImage> _images = [];
  int _selectedIndex = 0;
  bool _pickingFiles = false;
  bool _isExporting = false;
  int _loadingCount = 0;

  // View transform
  final TransformationController _transform = TransformationController();
  double _currentZoom = 1.0;
  double _rotationAngle = 0;

  // History (undo/redo)
  final List<Matrix4> _history = [];
  int _historyIndex = -1;

  // Filters
  bool _invertColors = false;
  double _brightness = 0.0; // –100 … 100
  double _contrast = 1.0; // 0.2 … 3.0

  // UI state
  bool _showMeta = false;
  bool _showWindowLevel = false;
  bool _showCrosshair = false;
  bool _showGrid = false;
  bool _isFullscreen = false;

  late final AnimationController _panelAnim;
  late final Animation<double> _panelSlide;

  final FocusNode _focusNode = FocusNode();

  // ── Init / dispose ────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _panelAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _panelSlide = CurvedAnimation(
      parent: _panelAnim,
      curve: Curves.easeOutCubic,
    );
    _saveToHistory(_transform.value);
    _transform.addListener(() {
      final scale = _transform.value.getMaxScaleOnAxis();
      if (mounted) setState(() => _currentZoom = scale);
    });
  }

  @override
  void dispose() {
    _panelAnim.dispose();
    _transform.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  DicomImage? get _current => _images.isEmpty ? null : _images[_selectedIndex];

  bool get _hasFilter =>
      _invertColors || _brightness != 0.0 || _contrast != 1.0;

  ColorFilter _buildColorFilter() {
    final c = _contrast;
    final t = (1.0 - c) / 2.0 * 255 + _brightness;
    if (_invertColors) {
      return ColorFilter.matrix([
        -c,
        0,
        0,
        0,
        255 - t,
        0,
        -c,
        0,
        0,
        255 - t,
        0,
        0,
        -c,
        0,
        255 - t,
        0,
        0,
        0,
        1,
        0,
      ]);
    }
    return ColorFilter.matrix([
      c,
      0,
      0,
      0,
      t,
      0,
      c,
      0,
      0,
      t,
      0,
      0,
      c,
      0,
      t,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  void _toast(String msg) => Fluttertoast.showToast(
    msg: msg,
    backgroundColor: _card,
    textColor: Colors.white,
    gravity: ToastGravity.BOTTOM,
    toastLength: Toast.LENGTH_SHORT,
  );

  // ── History ───────────────────────────────────────────────────────────────
  void _saveToHistory(Matrix4 v) {
    _history.removeRange(_historyIndex + 1, _history.length);
    _history.add(v.clone());
    _historyIndex = _history.length - 1;
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() => _transform.value = _history[--_historyIndex]);
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() => _transform.value = _history[++_historyIndex]);
    }
  }

  // ── Keyboard shortcuts ────────────────────────────────────────────────────
  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      if (_selectedIndex < _images.length - 1) _selectImage(_selectedIndex + 1);
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.keyA) {
      if (_selectedIndex > 0) _selectImage(_selectedIndex - 1);
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.numpadAdd) {
      _zoomIn();
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _zoomOut();
    } else if (k == LogicalKeyboardKey.keyF) {
      _fitToScreen();
    } else if (k == LogicalKeyboardKey.keyR) {
      _rotateImage();
    } else if (k == LogicalKeyboardKey.keyI) {
      _toggleInvert();
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMeta();
    } else if (k == LogicalKeyboardKey.keyW) {
      _toggleWindowLevel();
    } else if (k == LogicalKeyboardKey.digit0 ||
        k == LogicalKeyboardKey.numpad0) {
      _resetView();
    }
  }

  // ── Zoom ──────────────────────────────────────────────────────────────────
  void _zoomIn() {
    final m = _transform.value.clone()..scale(1.25, 1.25);
    _transform.value = m;
    _saveToHistory(m);
  }

  void _zoomOut() {
    final m = _transform.value.clone()..scale(0.8, 0.8);
    _transform.value = m;
    _saveToHistory(m);
  }

  void _fitToScreen() {
    setState(() {
      _transform.value = Matrix4.identity();
      _rotationAngle = 0;
      _saveToHistory(_transform.value);
    });
  }

  // ── Transform actions ─────────────────────────────────────────────────────
  void _rotateImage() {
    setState(() {
      _rotationAngle = (_rotationAngle + 90) % 360;
    });
    _toast('Rotated ${_rotationAngle.toInt()}°');
  }

  void _flipH() {
    setState(() {
      _transform.value = Matrix4.diagonal3Values(-1, 1, 1);
      _saveToHistory(_transform.value);
    });
    _toast('Flipped horizontal');
  }

  void _flipV() {
    setState(() {
      _transform.value = Matrix4.diagonal3Values(1, -1, 1);
      _saveToHistory(_transform.value);
    });
    _toast('Flipped vertical');
  }

  void _toggleInvert() {
    setState(() => _invertColors = !_invertColors);
    _toast(_invertColors ? 'Invert ON' : 'Invert OFF');
  }

  void _resetView() {
    setState(() {
      _transform.value = Matrix4.identity();
      _rotationAngle = 0;
      _invertColors = false;
      _brightness = 0;
      _contrast = 1.0;
      _currentZoom = 1.0;
      _saveToHistory(_transform.value);
    });
    _toast('View reset');
  }

  void _resetWindowLevel() => setState(() {
    _brightness = 0;
    _contrast = 1.0;
  });

  // ── UI toggles ────────────────────────────────────────────────────────────
  void _toggleMeta() {
    setState(() => _showMeta = !_showMeta);
    _showMeta ? _panelAnim.forward() : _panelAnim.reverse();
  }

  void _toggleWindowLevel() =>
      setState(() => _showWindowLevel = !_showWindowLevel);

  void _toggleCrosshair() => setState(() {
    _showCrosshair = !_showCrosshair;
    if (_showCrosshair) _showGrid = false;
  });

  void _toggleGrid() => setState(() {
    _showGrid = !_showGrid;
    if (_showGrid) _showCrosshair = false;
  });

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    _isFullscreen
        ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
        : SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ── File picking ──────────────────────────────────────────────────────────
  Future<void> _pickFiles() async {
    setState(() => _pickingFiles = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _pickingFiles = false);
        return;
      }
      final dcmFiles = result.files.where((f) {
        final ext = f.name.split('.').last.toLowerCase();
        return ext == 'dcm' || ext == 'dicom';
      }).toList();

      if (dcmFiles.isEmpty) {
        setState(() => _pickingFiles = false);
        _toast('No .dcm files found');
        return;
      }

      final newImages = <DicomImage>[];
      for (final file in dcmFiles) {
        String? path = file.path;
        if (path == null || !File(path).existsSync()) {
          if (file.bytes != null) {
            final tmp = File('${Directory.systemTemp.path}/${file.name}');
            await tmp.writeAsBytes(file.bytes!);
            path = tmp.path;
          } else {
            continue;
          }
        }
        newImages.add(DicomImage(path: path, name: file.name));
      }

      setState(() {
        _images.addAll(newImages);
        _selectedIndex = _images.length - newImages.length;
        _pickingFiles = false;
        _loadingCount += newImages.length;
      });

      for (final img in newImages) {
        _renderImage(img).then((_) {
          if (mounted)
            setState(() => _loadingCount = (_loadingCount - 1).clamp(0, 999));
        });
      }
      _toast('Loading ${newImages.length} file(s)…');
    } catch (e) {
      setState(() => _pickingFiles = false);
      _toast('Error: $e');
    }
  }

  // ── Render ────────────────────────────────────────────────────────────────
  Future<void> _renderImage(DicomImage img) async {
    setState(() => img.loading = true);
    try {
      final Map result = await _channel.invokeMethod('renderDicom', {
        'path': img.path,
      });
      final Uint8List png = result['pixels'] as Uint8List;
      if (png.isEmpty) throw Exception('Empty image returned');
      setState(() {
        img.pngBytes = png;
        img.patientName = (result['patientName'] as String?) ?? '';
        img.modality = (result['modality'] as String?) ?? '';
        img.studyDate = (result['studyDate'] as String?) ?? '';
        img.institution = (result['institution'] as String?) ?? '';
        img.studyDescription = (result['studyDescription'] as String?) ?? '';
        img.seriesDescription = (result['seriesDescription'] as String?) ?? '';
        img.windowCenter = (result['windowCenter'] as String?) ?? '';
        img.windowWidth = (result['windowWidth'] as String?) ?? '';
        img.loading = false;
        img.error = null;
        img.loadedAt = DateTime.now();
      });
    } on PlatformException catch (e) {
      setState(() {
        img.loading = false;
        img.error = e.message;
      });
    } catch (e) {
      setState(() {
        img.loading = false;
        img.error = e.toString();
      });
    }
  }

  void _selectImage(int i) => setState(() {
    _selectedIndex = i;
    _transform.value = Matrix4.identity();
    _rotationAngle = 0;
    _currentZoom = 1.0;
    _saveToHistory(_transform.value);
  });

  void _removeImage(int i) => setState(() {
    _images.removeAt(i);
    if (_selectedIndex >= _images.length) {
      _selectedIndex = (_images.length - 1).clamp(0, _images.length);
    }
    _toast('Image removed');
  });

  void _clearAll() => setState(() {
    _images.clear();
    _selectedIndex = 0;
    _toast('All images cleared');
  });

  // ── Export actions ────────────────────────────────────────────────────────
  Future<void> _shareImage() async {
    if (_current?.pngBytes == null) return;
    setState(() => _isExporting = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fp =
          '${dir.path}/dicom_export_${_current!.name.replaceAll('.dcm', '')}_$ts.png';
      await File(fp).writeAsBytes(_current!.pngBytes!);
      await Share.shareXFiles(
        [XFile(fp)],
        text:
            'WIESPL DICOM Export\nPatient: ${_current!.patientName}\nModality: ${_current!.modality}\nDate: ${_current!.studyDate}',
      );
      _toast('Image shared');
    } catch (e) {
      _toast('Error: $e');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _saveImage() async {
    if (_current?.pngBytes == null) return;
    setState(() => _isExporting = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final name = 'dicom_${_current!.name.replaceAll('.dcm', '')}_$ts.png';
      await File('${dir.path}/$name').writeAsBytes(_current!.pngBytes!);
      _toast('Saved: $name');
    } catch (e) {
      _toast('Error: $e');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _batchExport() async {
    if (_images.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text(
          'Batch Export',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Export all ${_images.length} images to Documents folder?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _cyan),
            child: const Text(
              'Export All',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isExporting = true);
    try {
      int ok = 0;
      final dir = await getApplicationDocumentsDirectory();
      for (final img in _images) {
        if (img.pngBytes != null) {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final fn = 'dicom_batch_${img.name.replaceAll('.dcm', '')}_$ts.png';
          await File('${dir.path}/$fn').writeAsBytes(img.pngBytes!);
          ok++;
        }
      }
      _toast('Exported $ok/${_images.length} images');
    } catch (e) {
      _toast('Batch error: $e');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  // ── Image info dialog ─────────────────────────────────────────────────────
  void _showImageInfo() {
    final cur = _current;
    if (cur == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text(
          'Image Information',
          style: TextStyle(color: Colors.white),
        ),
        content: Container(
          width: 320,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('File', cur.name),
                _infoRow('Patient', cur.patientName),
                _infoRow('Modality', cur.modality),
                _infoRow('Study Date', cur.studyDate),
                _infoRow('Institution', cur.institution),
                if (cur.studyDescription.isNotEmpty)
                  _infoRow('Study Desc', cur.studyDescription),
                if (cur.seriesDescription.isNotEmpty)
                  _infoRow('Series Desc', cur.seriesDescription),
                if (cur.windowCenter.isNotEmpty)
                  _infoRow('Window Center', cur.windowCenter),
                if (cur.windowWidth.isNotEmpty)
                  _infoRow('Window Width', cur.windowWidth),
                if (cur.loadedAt != null)
                  _infoRow(
                    'Loaded',
                    '${cur.loadedAt!.toLocal()}'.split('.')[0],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: _cyan)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final cur = _current;
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(
          children: [
            if (!_isFullscreen) _topBar(cur),
            if (!_isFullscreen && cur?.pngBytes != null) _toolBar(),
            Expanded(
              child: Row(
                children: [
                  if (_images.isNotEmpty && !_isFullscreen) _thumbnailSidebar(),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _viewport(cur)),
                        if (_showWindowLevel && cur?.pngBytes != null)
                          _windowLevelPanel(),
                      ],
                    ),
                  ),
                  SizeTransition(
                    sizeFactor: _panelSlide,
                    axis: Axis.horizontal,
                    child: _metaPanel(cur),
                  ),
                ],
              ),
            ),
            if (cur?.pngBytes != null) _statusBar(cur!),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _topBar(DicomImage? cur) => Container(
    height: 52,
    color: _surface,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        // Back
        IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white54,
            size: 16,
          ),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        ),
        const SizedBox(width: 10),

        // ── WIESPL DICOM logo ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_cyan, _violet],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: _cyan.withOpacity(0.2),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WIESPL',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(width: 5),
              Text(
                'DICOM',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w300,
                  fontSize: 11,
                  letterSpacing: 2.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 14),

        // File info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                cur?.name ?? 'No file loaded',
                style: TextStyle(
                  color: cur != null ? Colors.white60 : _dim,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (_images.length > 1 || _loadingCount > 0)
                Text(
                  _loadingCount > 0
                      ? '${_selectedIndex + 1} / ${_images.length}  •  $_loadingCount rendering…'
                      : '${_selectedIndex + 1} / ${_images.length} images',
                  style: const TextStyle(color: _cyan, fontSize: 9),
                ),
            ],
          ),
        ),

        // Actions
        if (_images.isNotEmpty) ...[
          _iconBtn(Icons.delete_sweep_outlined, 'Clear All', _clearAll),
          const SizedBox(width: 6),
        ],
        ElevatedButton.icon(
          onPressed: _pickingFiles ? null : _pickFiles,
          icon: _pickingFiles
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Icon(Icons.folder_open, size: 14),
          label: const Text('Open .dcm'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _cyan,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
      ],
    ),
  );

  // ── Secondary toolbar ─────────────────────────────────────────────────────
  Widget _toolBar() => Container(
    height: 42,
    decoration: const BoxDecoration(
      color: _card,
      border: Border(
        bottom: BorderSide(color: _border),
        top: BorderSide(color: _border),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      children: [
        // History
        _iconBtn(Icons.undo_rounded, 'Undo', _undo),
        _iconBtn(Icons.redo_rounded, 'Redo', _redo),
        _sep(),
        // Zoom
        _iconBtn(Icons.zoom_in_rounded, 'Zoom In (+)', _zoomIn),
        _iconBtn(Icons.zoom_out_rounded, 'Zoom Out (−)', _zoomOut),
        _iconBtn(Icons.fit_screen_rounded, 'Fit to Screen (F)', _fitToScreen),
        _sep(),
        // Transform
        _iconBtn(Icons.rotate_right_rounded, 'Rotate 90° (R)', _rotateImage),
        _iconBtn(Icons.flip_rounded, 'Flip Horizontal', _flipH),
        _iconBtn(Icons.flip_camera_android_rounded, 'Flip Vertical', _flipV),
        _sep(),
        // Display
        _iconBtn(
          Icons.invert_colors_rounded,
          'Invert Colors (I)',
          _toggleInvert,
          active: _invertColors,
        ),
        _iconBtn(
          Icons.brightness_6_rounded,
          'Window / Level (W)',
          _toggleWindowLevel,
          active: _showWindowLevel,
        ),
        _sep(),
        // Overlays
        _iconBtn(Icons.grid_on_rounded, 'Grid', _toggleGrid, active: _showGrid),
        _iconBtn(
          Icons.add_circle_outline_rounded,
          'Crosshair',
          _toggleCrosshair,
          active: _showCrosshair,
        ),
        _sep(),
        // Misc
        _iconBtn(Icons.info_outline_rounded, 'Image Info', _showImageInfo),
        _iconBtn(
          Icons.table_rows_rounded,
          'Metadata (M)',
          _toggleMeta,
          active: _showMeta,
        ),
        _iconBtn(
          _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen_rounded,
          _isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
          _toggleFullscreen,
        ),
        _sep(),
        // Export
        _iconBtn(Icons.ios_share_rounded, 'Share', _shareImage),
        _iconBtn(Icons.save_alt_rounded, 'Save PNG', _saveImage),
        if (_images.length > 1)
          _iconBtn(Icons.save_rounded, 'Batch Export', _batchExport),
        _iconBtn(Icons.refresh_rounded, 'Reset View (0)', _resetView),
        const Spacer(),
        // Shortcut hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '← → navigate  •  +/− zoom  •  R rotate  •  F fit  •  I invert  •  W window  •  0 reset',
            style: TextStyle(color: _muted, fontSize: 8.5),
          ),
        ),
      ],
    ),
  );

  Widget _sep() => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: _border,
  );

  Widget _iconBtn(
    IconData icon,
    String tip,
    VoidCallback cb, {
    bool active = false,
  }) => Tooltip(
    message: tip,
    child: InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: cb,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.only(right: 1),
        decoration: BoxDecoration(
          color: active ? _cyan.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: active ? Border.all(color: _cyan.withOpacity(0.5)) : null,
        ),
        child: Icon(icon, color: active ? _cyan : Colors.white30, size: 15),
      ),
    ),
  );

  // ── Thumbnail sidebar ─────────────────────────────────────────────────────
  Widget _thumbnailSidebar() => Container(
    width: 94,
    color: _surface,
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Text(
            '${_images.length} FILE${_images.length != 1 ? "S" : ""}',
            style: const TextStyle(
              color: _muted,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: _images.length,
            itemBuilder: (_, i) => _thumbnail(i),
          ),
        ),
      ],
    ),
  );

  Widget _thumbnail(int index) {
    final img = _images[index];
    final sel = index == _selectedIndex;
    return GestureDetector(
      onTap: () => _selectImage(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sel ? _cyan : _border, width: sel ? 2 : 1),
          color: sel ? _cyan.withOpacity(0.08) : _card,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 66,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
                child: img.loading
                    ? Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _cyan,
                          ),
                        ),
                      )
                    : img.error != null
                    ? const Center(
                        child: Icon(Icons.broken_image, color: _red, size: 20),
                      )
                    : img.pngBytes != null
                    ? Image.memory(
                        img.pngBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      )
                    : const Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: _muted,
                          size: 20,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 2, 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      img.name.replaceAll(
                        RegExp(r'\.(dcm|dicom)$', caseSensitive: false),
                        '',
                      ),
                      style: TextStyle(
                        color: sel ? _cyan : Colors.white30,
                        fontSize: 7,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _removeImage(index),
                    child: const Icon(Icons.close, color: _muted, size: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Viewport ──────────────────────────────────────────────────────────────
  Widget _viewport(DicomImage? cur) {
    // Empty state
    if (_images.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _border, width: 2),
              ),
              child: const Icon(
                Icons.medical_services_outlined,
                color: _muted,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Open DICOM files to begin',
              style: TextStyle(
                color: _muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Supports multiple .dcm files at once',
              style: TextStyle(color: _dim, fontSize: 11),
            ),
          ],
        ),
      );
    }

    if (cur == null) return const SizedBox.shrink();

    // Loading
    if (cur.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _cyan, strokeWidth: 2),
            SizedBox(height: 12),
            Text(
              'Rendering…',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Error
    if (cur.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _red, size: 42),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0808),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF3A1010)),
                ),
                child: Text(
                  cur.error!,
                  style: const TextStyle(
                    color: Color(0xFFFF8888),
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => _renderImage(cur),
                icon: const Icon(Icons.refresh, color: _cyan, size: 14),
                label: const Text('Retry', style: TextStyle(color: _cyan)),
              ),
            ],
          ),
        ),
      );
    }

    if (cur.pngBytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: _cyan, strokeWidth: 2),
      );
    }

    // Image viewer
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Main interactive image ──────────────────────────────────────
          InteractiveViewer(
            transformationController: _transform,
            minScale: 0.05,
            maxScale: 20.0,
            onInteractionEnd: (_) => _saveToHistory(_transform.value),
            child: Center(
              child: Transform.rotate(
                angle: _rotationAngle * 3.14159 / 180,
                child: ColorFiltered(
                  colorFilter: _buildColorFilter(),
                  child: Image.memory(
                    cur.pngBytes!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),

          // ── Overlays ────────────────────────────────────────────────────
          if (_showCrosshair)
            IgnorePointer(child: CustomPaint(painter: _CrosshairPainter())),
          if (_showGrid)
            IgnorePointer(child: CustomPaint(painter: _GridPainter())),

          // ── Patient / modality badge (top-left) ─────────────────────────
          if (cur.patientName.isNotEmpty || cur.modality.isNotEmpty)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cur.patientName.isNotEmpty)
                      Text(
                        cur.patientName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (cur.modality.isNotEmpty)
                      Text(
                        cur.modality,
                        style: const TextStyle(color: _cyan, fontSize: 9),
                      ),
                    if (cur.studyDate.isNotEmpty)
                      Text(
                        cur.studyDate,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // ── Zoom badge (top-right) ──────────────────────────────────────
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '${(_currentZoom * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),

          // ── Navigation arrows ───────────────────────────────────────────
          if (_images.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _navBtn(Icons.chevron_left_rounded, () {
                  if (_selectedIndex > 0) _selectImage(_selectedIndex - 1);
                }, enabled: _selectedIndex > 0),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _navBtn(
                  Icons.chevron_right_rounded,
                  () {
                    if (_selectedIndex < _images.length - 1)
                      _selectImage(_selectedIndex + 1);
                  },
                  enabled: _selectedIndex < _images.length - 1,
                ),
              ),
            ),
          ],

          // ── Fullscreen toggle (bottom-right) ────────────────────────────
          Positioned(
            bottom: 10,
            right: 10,
            child: GestureDetector(
              onTap: _toggleFullscreen,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(
                  _isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen_rounded,
                  color: Colors.white38,
                  size: 16,
                ),
              ),
            ),
          ),

          // ── Export overlay ──────────────────────────────────────────────
          if (_isExporting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: _cyan),
                    SizedBox(height: 14),
                    Text('Processing…', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback cb, {required bool enabled}) =>
      GestureDetector(
        onTap: enabled ? cb : null,
        child: Container(
          width: 32,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(
            icon,
            color: enabled ? Colors.white60 : Colors.white24,
            size: 22,
          ),
        ),
      );

  // ── Window / Level panel ──────────────────────────────────────────────────
  Widget _windowLevelPanel() => Container(
    height: 78,
    decoration: const BoxDecoration(
      color: _card,
      border: Border(top: BorderSide(color: _border)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_cyan, _violet],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Text(
            'W/L',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _wlSlider(
                label: 'Brightness',
                value: _brightness,
                min: -100,
                max: 100,
                color: _cyan,
                onChanged: (v) => setState(() => _brightness = v),
              ),
              const SizedBox(height: 4),
              _wlSlider(
                label: 'Contrast',
                value: _contrast,
                min: 0.2,
                max: 3.0,
                color: _violet,
                onChanged: (v) => setState(() => _contrast = v),
                displayValue: _contrast.toStringAsFixed(2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        TextButton.icon(
          onPressed: _resetWindowLevel,
          icon: const Icon(
            Icons.refresh_rounded,
            size: 13,
            color: Colors.white38,
          ),
          label: const Text(
            'Reset',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ],
    ),
  );

  Widget _wlSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
    String? displayValue,
  }) => Row(
    children: [
      SizedBox(
        width: 68,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 9),
        ),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: color,
            inactiveTrackColor: _border,
            thumbColor: color,
            overlayColor: color.withOpacity(0.15),
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ),
      SizedBox(
        width: 38,
        child: Text(
          displayValue ?? value.toStringAsFixed(0),
          style: const TextStyle(color: Colors.white38, fontSize: 9),
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );

  // ── Metadata panel ────────────────────────────────────────────────────────
  Widget _metaPanel(DicomImage? cur) => Container(
    width: 230,
    decoration: const BoxDecoration(
      color: _surface,
      border: Border(left: BorderSide(color: _border)),
    ),
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: _cyan, size: 13),
              const SizedBox(width: 6),
              const Text(
                'METADATA',
                style: TextStyle(
                  color: _cyan,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: cur == null
              ? const SizedBox()
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _mrow('Patient', cur.patientName),
                    _mrow('Modality', cur.modality),
                    _mrow('Study Date', cur.studyDate),
                    _mrow('Institution', cur.institution),
                    if (cur.studyDescription.isNotEmpty)
                      _mrow('Study Desc', cur.studyDescription),
                    if (cur.seriesDescription.isNotEmpty)
                      _mrow('Series Desc', cur.seriesDescription),
                    if (cur.windowCenter.isNotEmpty)
                      _mrow('Window Center', cur.windowCenter),
                    if (cur.windowWidth.isNotEmpty)
                      _mrow('Window Width', cur.windowWidth),
                    _mrow('File', cur.name),
                    if (cur.loadedAt != null)
                      _mrow(
                        'Loaded',
                        '${cur.loadedAt!.toLocal()}'.split('.')[0],
                      ),
                  ],
                ),
        ),
      ],
    ),
  );

  Widget _mrow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: _muted,
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────────
  Widget _statusBar(DicomImage cur) => Container(
    height: 26,
    color: _surface,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        // Modality badge
        if (cur.modality.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: _cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: _cyan.withOpacity(0.3)),
            ),
            child: Text(
              cur.modality,
              style: const TextStyle(
                color: _cyan,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        const SizedBox(width: 8),

        // Image counter
        if (_images.length > 1)
          Text(
            '${_selectedIndex + 1} / ${_images.length}',
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
        const SizedBox(width: 8),

        // Zoom
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: _border,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '${(_currentZoom * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ),

        // Filter badge
        if (_hasFilter) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: _violet.withOpacity(0.12),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: _violet.withOpacity(0.35)),
            ),
            child: const Text(
              'FILTERED',
              style: TextStyle(
                color: _violet,
                fontSize: 7.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],

        // Rotation angle
        if (_rotationAngle != 0) ...[
          const SizedBox(width: 6),
          Text(
            '↻ ${_rotationAngle.toInt()}°',
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
        ],

        const Spacer(),

        // Institution
        if (cur.institution.isNotEmpty)
          Text(
            cur.institution,
            style: const TextStyle(color: _dim, fontSize: 9),
          ),
        const SizedBox(width: 10),

        // Shortcut hint
        const Text(
          '← → navigate  •  +/− zoom  •  R rotate  •  F fit  •  I invert  •  W window  •  0 reset',
          style: TextStyle(color: _dim, fontSize: 8.5),
        ),
      ],
    ),
  );
}
