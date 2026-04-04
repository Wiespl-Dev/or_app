import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

class _K {
  // SharedPreferences key (was accidentally the IP string itself — fixed)
  static const prefEsp32Ip = 'esp32_ip';

  // ESP32 endpoints
  static const epConnection = '/connection-test';
  static const epAllParams = '/all-parameters';
  static const epSensorData = '/sensor-data';
  static const epLegacyData = '/data';
  static const epControl = '/control';

  // Setpoint guard
  static const setpointGuard = Duration(seconds: 15);

  // Sensor / light counts
  static const lightCount = 10;
  static const sensorCount = 10;

  // Humidity clamp
  static const minHumidity = 45.0;
  static const maxHumidity = 55.0;
  static const humidityStep = 0.5;

  // Temperature clamp
  static const minTemp = 16.0;
  static const maxTemp = 24.0;

  // HTTP timeouts
  static const connectTimeout = Duration(seconds: 3);
  static const fetchTimeout = Duration(seconds: 2);

  // Polling interval
  static const pollInterval = Duration(seconds: 3);

  // Backward-compat light indices (0-based)
  static const idxDefumigation = 7; // light 8
  static const idxDayNight = 8; // light 9
  static const idxSystemPower = 9; // light 10
}

// ─── Provider ─────────────────────────────────────────────────────────────────

class ESP32Provider with ChangeNotifier {
  // ── Connection ────────────────────────────────────────────────────────────
  String _esp32IP = '192.168.1.119:8080';
  bool _isConnected = false;
  bool _isInitialized = false;
  Timer? _pollingTimer;

  String get esp32IP => _esp32IP;
  bool get isConnected => _isConnected;

  Uri _uri(String path) => Uri.parse('http://$_esp32IP$path');

  // ── Sensor data ───────────────────────────────────────────────────────────
  String _currentTemperature = '0.0';
  String _currentHumidity = '0.0';
  String _pressureValue = '0';
  bool _isPressurePositive = true;

  String get currentTemperature => _currentTemperature;
  String get currentHumidity => _currentHumidity;
  String get pressureValue => _pressureValue;
  bool get isPressurePositive => _isPressurePositive;
  double get currentTemperatureAsDouble =>
      double.tryParse(_currentTemperature) ?? 0.0;

  // ── Setpoints ─────────────────────────────────────────────────────────────
  String _humiditySetpoint = '50.0';
  String _temperatureSetpoint = '25.0';
  double _pendingTemperature = 25.0;
  DateTime? _humidityGuardUntil;
  DateTime? _temperatureGuardUntil;

  String get humiditySetpoint => _humiditySetpoint;
  double get humiditySetpointAsDouble =>
      double.tryParse(_humiditySetpoint) ?? 50.0;
  String get temperatureSetpoint => _temperatureSetpoint;
  double get temperatureSetpointAsDouble =>
      double.tryParse(_temperatureSetpoint) ?? 25.0;
  double get pendingTemperature => _pendingTemperature;

  bool get _humidityGuardActive =>
      _humidityGuardUntil != null &&
      DateTime.now().isBefore(_humidityGuardUntil!);

  bool get _temperatureGuardActive =>
      _temperatureGuardUntil != null &&
      DateTime.now().isBefore(_temperatureGuardUntil!);

  // ── Lights & sensors ──────────────────────────────────────────────────────
  final List<bool> _lightStates = List.filled(_K.lightCount, false);
  final List<String> _sensorFaults = List.filled(_K.sensorCount, '-1');

  List<bool> get allLightStates => List.unmodifiable(_lightStates);
  List<String> get sensorFaults => List.unmodifiable(_sensorFaults);

  bool getLightState(int index) =>
      (index >= 0 && index < _lightStates.length) ? _lightStates[index] : false;

  // Individual named getters (1-based, for external consumers)
  bool get light1 => _lightStates[0];
  bool get light2 => _lightStates[1];
  bool get light3 => _lightStates[2];
  bool get light4 => _lightStates[3];
  bool get light5 => _lightStates[4];
  bool get light6 => _lightStates[5];
  bool get light7 => _lightStates[6];
  bool get light8 => _lightStates[7];
  bool get light9 => _lightStates[8];
  bool get light10 => _lightStates[9];

  // Aliases kept for backward compatibility
  bool get light1State => light1;
  bool get light2State => light2;
  bool get light3State => light3;
  bool get light4State => light4;
  bool get light5State => light5;
  bool get light6State => light6;
  bool get light7State => light7;
  bool get light8State => light8;
  bool get light9State => light9;
  bool get light10State => light10;

  // Backward-compat semantic aliases
  bool get defumigation => _lightStates[_K.idxDefumigation];
  bool get dayNightMode => _lightStates[_K.idxDayNight];
  bool get systemPower => _lightStates[_K.idxSystemPower];

  // ── Sensor helpers ────────────────────────────────────────────────────────
  bool isSensorHealthy(int i) =>
      i >= 0 && i < _sensorFaults.length && _sensorFaults[i] == '1';

  Color getSensorColor(int i, Color healthyColor) =>
      isSensorHealthy(i) ? healthyColor : Colors.red;

  Color get sensor10Color => _sensorFaults.length > 9 && _sensorFaults[9] == '1'
      ? Colors.green
      : Colors.red;

  bool get isMGPSHealthy =>
      List.generate(4, (i) => isSensorHealthy(i)).every((ok) => ok);

  Color get mgpsColor => isMGPSHealthy ? Colors.green : Colors.red;

  // ── Pressure helpers ──────────────────────────────────────────────────────
  String getFormattedPressure() {
    final v = int.tryParse(_pressureValue) ?? 0;
    return _isPressurePositive ? '$v' : '-$v';
  }

  Color getPressureColor() =>
      _isPressurePositive ? Colors.greenAccent : Colors.redAccent;

  // ── Init ──────────────────────────────────────────────────────────────────
  ESP32Provider() {
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadIP();
    _isInitialized = true;
    startPolling();
    await refreshData();
    notifyListeners();
  }

  Future<void> _loadIP() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_K.prefEsp32Ip) ?? '';
    if (saved.isNotEmpty) _esp32IP = saved;
  }

  /// Public init kept for backward compatibility.
  Future<void> init() async {
    if (!_isInitialized) await _initialize();
  }

  Future<void> updateESP32IP(String ip) async {
    stopPolling();
    _esp32IP = ip;
    _isConnected = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_K.prefEsp32Ip, ip);
    startPolling();
    notifyListeners();
  }

  // ── Temperature ───────────────────────────────────────────────────────────
  void updatePendingTemperature(double change) {
    _pendingTemperature = (_pendingTemperature + change).clamp(
      _K.minTemp,
      _K.maxTemp,
    );
    notifyListeners();
  }

  Future<void> setTemperature(double temperature) async {
    _temperatureSetpoint = temperature.toStringAsFixed(0);
    _pendingTemperature = temperature;
    _temperatureGuardUntil = DateTime.now().add(_K.setpointGuard);
    notifyListeners();
    await _sendControl('S_TEMP_SETPT', (temperature * 10).round().toString());
  }

  /// Convenience alias.
  Future<void> requestTemperatureStatus() => refreshData();

  // ── Humidity ──────────────────────────────────────────────────────────────
  void adjustHumidity(double change) {
    double v = (humiditySetpointAsDouble + change).clamp(
      _K.minHumidity,
      _K.maxHumidity,
    );
    v = (v / _K.humidityStep).round() * _K.humidityStep;
    _humiditySetpoint = v.toStringAsFixed(1);
    notifyListeners();
  }

  Future<void> setHumiditySetpoint() async {
    final encoded = (humiditySetpointAsDouble * 10).round().toString().padLeft(
      3,
      '0',
    );
    _humidityGuardUntil = DateTime.now().add(_K.setpointGuard);
    await _sendControl('S_RH_SETPT', encoded);
  }

  // ── Lights ────────────────────────────────────────────────────────────────
  Future<void> toggleLight(int lightNumber, bool value) async {
    if (!_validLight(lightNumber)) return;
    _setLight(lightNumber - 1, value);
    notifyListeners();
    await _sendControl('S_Light_${lightNumber}_ON_OFF', value ? '1' : '0');
  }

  Future<void> toggleMultipleLights(Map<int, bool> states) async {
    if (states.isEmpty) return;
    final controls = <String, String>{};
    states.forEach((n, v) {
      if (_validLight(n)) {
        _setLight(n - 1, v);
        controls['S_Light_${n}_ON_OFF'] = v ? '1' : '0';
      }
    });
    notifyListeners();
    if (controls.isNotEmpty) await _sendMultipleControls(controls);
  }

  Future<void> toggleAllLights(bool value) async {
    final controls = <String, String>{};
    for (int i = 0; i < _K.lightCount; i++) {
      _setLight(i, value);
      controls['S_Light_${i + 1}_ON_OFF'] = value ? '1' : '0';
    }
    notifyListeners();
    await _sendMultipleControls(controls);
  }

  Future<void> setLightPattern(List<bool> pattern) async {
    final controls = <String, String>{};
    for (int i = 0; i < pattern.length && i < _K.lightCount; i++) {
      _setLight(i, pattern[i]);
      controls['S_Light_${i + 1}_ON_OFF'] = pattern[i] ? '1' : '0';
    }
    notifyListeners();
    await _sendMultipleControls(controls);
  }

  // Backward-compat semantic toggles
  Future<void> toggleDefumigation(bool v) => toggleLight(8, v);
  Future<void> toggleSystemPower(bool v) => toggleLight(10, v);
  Future<void> toggleDayNightMode(bool v) => toggleLight(9, v);

  /// Sets a single light state and keeps backward-compat aliases in sync.
  void _setLight(int index, bool value) {
    _lightStates[index] = value;
  }

  bool _validLight(int n) => n >= 1 && n <= _K.lightCount;

  // ── Polling ───────────────────────────────────────────────────────────────
  void startPolling() {
    stopPolling();
    _pollingTimer = Timer.periodic(_K.pollInterval, (_) async {
      await _checkConnection();
      if (_isConnected) await _fetchData();
    });
    // Immediate first check without waiting for the timer
    _checkConnection();
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> refreshData() async {
    await _checkConnection();
    if (_isConnected) await _fetchData();
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────────
  Future<void> _checkConnection() async {
    try {
      final res = await http
          .get(_uri(_K.epConnection))
          .timeout(_K.connectTimeout);
      final ok = res.statusCode == 200;
      if (ok != _isConnected) {
        _isConnected = ok;
        if (ok) await _fetchData();
        notifyListeners();
      }
    } catch (_) {
      if (_isConnected) {
        _isConnected = false;
        notifyListeners();
      }
    }
  }

  Future<void> _fetchData() async {
    if (!_isConnected) return;

    // 1. Try /all-parameters
    try {
      final res = await http.get(_uri(_K.epAllParams)).timeout(_K.fetchTimeout);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        if (data.containsKey('sensor_faults')) {
          _parseAllParameters(data);
          return;
        }
      }
    } catch (_) {}

    // 2. Try /sensor-data
    try {
      final res = await http
          .get(_uri(_K.epSensorData))
          .timeout(_K.fetchTimeout);
      if (res.statusCode == 200) {
        _parseSensorData(json.decode(res.body) as Map<String, dynamic>);
        return;
      }
    } catch (_) {}

    // 3. Try legacy /data
    try {
      final res = await http
          .get(_uri(_K.epLegacyData))
          .timeout(_K.fetchTimeout);
      if (res.statusCode == 200) {
        final raw =
            (json.decode(res.body) as Map<String, dynamic>)['data'] as String?;
        if (raw != null && raw.contains('F_Sensor')) {
          _parseData(raw);
          return;
        }
      }
    } catch (_) {}

    // All endpoints failed
    _isConnected = false;
    notifyListeners();
  }

  // ── Parsers ───────────────────────────────────────────────────────────────

  void _parseAllParameters(Map<String, dynamic> d) {
    bool changed = false;

    changed |= _setIfChanged<String>(
      () => _currentTemperature,
      (v) => _currentTemperature = v,
      d['temperature']?.toString(),
    );

    changed |= _setIfChanged<String>(
      () => _currentHumidity,
      (v) => _currentHumidity = v,
      d['humidity']?.toString(),
    );

    if (d['pressure2'] != null) {
      final v = (int.tryParse(d['pressure2'].toString()) ?? 0).toString();
      changed |= _setIfChanged(
        () => _pressureValue,
        (x) => _pressureValue = x,
        v,
      );
    }

    if (d['pressure2_positive'] != null) {
      final v = d['pressure2_positive'] == true;
      if (_isPressurePositive != v) {
        _isPressurePositive = v;
        changed = true;
      }
    }

    if (d['sensor_faults'] is List) {
      final list = d['sensor_faults'] as List;
      for (int i = 0; i < list.length && i < _sensorFaults.length; i++) {
        changed |= _setIfChanged(
          () => _sensorFaults[i],
          (v) => _sensorFaults[i] = v,
          list[i].toString(),
        );
      }
    }

    if (d['humidity_setpoint'] != null && !_humidityGuardActive) {
      changed |= _setIfChanged(
        () => _humiditySetpoint,
        (v) => _humiditySetpoint = v,
        d['humidity_setpoint'].toString(),
      );
    }

    if (d['temperature_setpoint'] != null && !_temperatureGuardActive) {
      final v = d['temperature_setpoint'].toString();
      if (_temperatureSetpoint != v) {
        _temperatureSetpoint = v;
        _pendingTemperature = double.tryParse(v) ?? 25.0;
        changed = true;
      }
    }

    if (d['light_status'] is List) {
      final list = d['light_status'] as List;
      for (int i = 0; i < list.length && i < _lightStates.length; i++) {
        final v = list[i] == 1 || list[i] == '1';
        if (_lightStates[i] != v) {
          _setLight(i, v);
          changed = true;
        }
      }
    }

    if (changed) notifyListeners();
  }

  void _parseSensorData(Map<String, dynamic> d) {
    bool changed = false;

    changed |= _setIfChanged(
      () => _currentTemperature,
      (v) => _currentTemperature = v,
      d['temperature']?.toString(),
    );

    changed |= _setIfChanged(
      () => _currentHumidity,
      (v) => _currentHumidity = v,
      d['humidity']?.toString(),
    );

    if (d['pressure'] != null) {
      final v = ((double.tryParse(d['pressure'].toString()) ?? 0.0) * 100)
          .toInt()
          .toString();
      changed |= _setIfChanged(
        () => _pressureValue,
        (x) => _pressureValue = x,
        v,
      );
    }

    if (d['pressure_positive'] != null) {
      final v =
          d['pressure_positive'] == true ||
          d['pressure_positive'] == '1' ||
          d['pressure_positive'] == 1;
      if (_isPressurePositive != v) {
        _isPressurePositive = v;
        changed = true;
      }
    }

    for (int i = 1; i <= _K.sensorCount; i++) {
      final raw = d['F_Sensor_${i}_FAULT_BIT'] ?? d['sensor_fault_$i'];
      if (raw != null) {
        changed |= _setIfChanged(
          () => _sensorFaults[i - 1],
          (v) => _sensorFaults[i - 1] = v,
          raw.toString(),
        );
      }
    }

    if (changed) notifyListeners();
  }

  static final _tempRx = RegExp(r'C_OT_TEMP:(\d+)');
  static final _humidityRx = RegExp(r'C_RH:(\d+)');
  static final _pressureRx = RegExp(r'C_PRESSURE_2:(\d+)');
  static final _pressSignRx = RegExp(r'C_PRESSURE_2_SIGN_BIT:(\d+)');

  void _parseData(String data) {
    bool changed = false;

    final tMatch = _tempRx.firstMatch(data);
    if (tMatch != null) {
      final v = ((int.tryParse(tMatch.group(1) ?? '0') ?? 0) / 10.0)
          .toStringAsFixed(1);
      changed |= _setIfChanged(
        () => _currentTemperature,
        (x) => _currentTemperature = x,
        v,
      );
    }

    final hMatch = _humidityRx.firstMatch(data);
    if (hMatch != null) {
      final v = ((int.tryParse(hMatch.group(1) ?? '0') ?? 0) / 10.0)
          .toStringAsFixed(1);
      changed |= _setIfChanged(
        () => _currentHumidity,
        (x) => _currentHumidity = x,
        v,
      );
    }

    final pMatch = _pressureRx.firstMatch(data);
    if (pMatch != null) {
      final v = ((int.tryParse(pMatch.group(1) ?? '0') ?? 0) * 100).toString();
      changed |= _setIfChanged(
        () => _pressureValue,
        (x) => _pressureValue = x,
        v,
      );
      _isPressurePositive = _pressSignRx.firstMatch(data)?.group(1) == '0';
    }

    if (changed) notifyListeners();
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  /// Public alias for external callers.
  Future<void> sendControl(String key, String value) =>
      _sendControl(key, value);

  Future<void> _sendControl(String key, String value) async {
    try {
      final res = await http
          .post(_uri(_K.epControl), body: {key: value})
          .timeout(_K.connectTimeout);

      if (res.statusCode == 200) {
        _applyLightFromKey(key, value);
      } else {
        throw Exception('Control failed: ${res.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _sendMultipleControls(Map<String, String> controls) async {
    try {
      final res = await http
          .post(_uri(_K.epControl), body: controls)
          .timeout(_K.connectTimeout);

      if (res.statusCode == 200) {
        controls.forEach(_applyLightFromKey);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Parses a control key like `S_Light_3_ON_OFF` and applies the state locally.
  void _applyLightFromKey(String key, String value) {
    if (!key.startsWith('S_Light_') || !key.endsWith('_ON_OFF')) return;
    final n = int.tryParse(key.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (!_validLight(n)) return;
    _setLight(n - 1, value == '1');
    notifyListeners();
  }

  // ── Utility: generic change-detector ─────────────────────────────────────

  /// Returns `true` if the value changed and assigns it.
  /// Skips assignment if [newVal] is null.
  bool _setIfChanged<T>(
    T Function() getter,
    void Function(T) setter,
    T? newVal,
  ) {
    if (newVal == null) return false;
    if (getter() == newVal) return false;
    setter(newVal);
    return true;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
