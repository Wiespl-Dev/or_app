import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ESP32Provider with ChangeNotifier {
  // ESP32 connection
  String _esp32IP = "192.168.1.119:8080"; // fallback default
  String get esp32IP => _esp32IP;

  Timer? _pollingTimer;
  bool _isConnected = false;
  bool _isInitialized = false; // Track initialization status

  // Sensor data
  String _currentTemperature = "0.0";
  String _currentHumidity = "0.0";
  String _pressureValue = "0";
  bool _isPressurePositive = true;

  // Humidity setpoint
  String _humiditySetpoint = "50.0";

  // Temperature setpoint
  String _temperatureSetpoint = "25.0"; // Default value
  double _pendingTemperature = 25.0; // For gauge interaction
  DateTime? _temperatureSetpointGuardUntil;

  // ── Setpoint guards ───────────────────────────────────────────────────────
  static const Duration _setpointGuardDuration = Duration(seconds: 15);
  DateTime? _humiditySetpointGuardUntil;

  bool get _isHumidityGuardActive =>
      _humiditySetpointGuardUntil != null &&
      DateTime.now().isBefore(_humiditySetpointGuardUntil!);

  bool get _isTemperatureGuardActive =>
      _temperatureSetpointGuardUntil != null &&
      DateTime.now().isBefore(_temperatureSetpointGuardUntil!);
  // ─────────────────────────────────────────────────────────────────────────

  // Light states
  List<bool> _lightStates = List.filled(10, false);

  // Sensor faults
  List<String> _sensorFaults = List.filled(10, "-1");

  // Backward compatibility control states - now mapped to lights 8, 9, 10
  bool _defumigation = false; // Light 8
  bool _systemPower = false; // Light 10
  bool _dayNightMode = false; // Light 9

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Constructor — automatically loads the saved IP from SharedPreferences and starts polling.
  ESP32Provider() {
    _initialize();
  }

  /// Internal: loads IP and starts polling.
  Future<void> _initialize() async {
    await _loadIP();
    _isInitialized = true;
    // Start polling after IP is loaded
    startPolling();
    // Force an immediate data fetch
    await refreshData();
    notifyListeners();
  }

  /// Internal: loads IP on startup.
  Future<void> _loadIP() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('192.168.0.119:8080') ?? '';
    if (saved.isNotEmpty) {
      _esp32IP = saved;
    } else {}
    notifyListeners();
  }

  /// Public init — kept for backward compatibility.
  Future<void> init() async {
    if (!_isInitialized) {
      await _initialize();
    }
  }

  /// Update the ESP32 IP at runtime and persist it to SharedPreferences.
  Future<void> updateESP32IP(String ip) async {
    // Stop current polling
    stopPolling();

    _esp32IP = ip;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp32_ip', ip);

    // Reset connection status
    _isConnected = false;

    // Restart polling with new IP
    startPolling();

    notifyListeners();
  }

  // ── Getters ───────────────────────────────────────────────────────────────
  bool get isConnected => _isConnected;
  String get currentTemperature => _currentTemperature;
  String get currentHumidity => _currentHumidity;
  String get pressureValue => _pressureValue;
  bool get isPressurePositive => _isPressurePositive;

  String get humiditySetpoint => _humiditySetpoint;
  double get humiditySetpointAsDouble =>
      double.tryParse(_humiditySetpoint) ?? 50.0;

  // Temperature getters
  String get temperatureSetpoint => _temperatureSetpoint;
  double get temperatureSetpointAsDouble =>
      double.tryParse(_temperatureSetpoint) ?? 25.0;
  double get pendingTemperature => _pendingTemperature;
  double get currentTemperatureAsDouble =>
      double.tryParse(_currentTemperature) ?? 0.0;

  List<String> get sensorFaults => List.unmodifiable(_sensorFaults);

  // Individual light getters
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

  // State getters (aliases)
  bool get light1State => _lightStates[0];
  bool get light2State => _lightStates[1];
  bool get light3State => _lightStates[2];
  bool get light4State => _lightStates[3];
  bool get light5State => _lightStates[4];
  bool get light6State => _lightStates[5];
  bool get light7State => _lightStates[6];
  bool get light8State => _lightStates[7];
  bool get light9State => _lightStates[8];
  bool get light10State => _lightStates[9];

  List<bool> get allLightStates => List.unmodifiable(_lightStates);

  bool getLightState(int index) {
    if (index >= 0 && index < _lightStates.length) return _lightStates[index];
    return false;
  }

  // Backward compatibility getters
  bool get defumigation => _lightStates[7]; // Light 8 (index 7)
  bool get systemPower => _lightStates[9]; // Light 10 (index 9)
  bool get dayNightMode => _lightStates[8]; // Light 9 (index 8)

  // ── Temperature Methods ───────────────────────────────────────────────────

  void updatePendingTemperature(double change) {
    double newValue = _pendingTemperature + change;
    if (newValue < 16) newValue = 16;
    if (newValue > 24) newValue = 24;
    _pendingTemperature = newValue;
    print(
      "🌡️ Pending temperature updated to: ${_pendingTemperature.toStringAsFixed(0)}°C",
    );
    notifyListeners();
  }

  Future<void> setTemperature(double temperature) async {
    _temperatureSetpoint = temperature.toStringAsFixed(0);
    _pendingTemperature = temperature;
    _temperatureSetpointGuardUntil = DateTime.now().add(_setpointGuardDuration);
    notifyListeners();

    final String temperatureValue = (temperature * 10).round().toString();
    await _sendControl("S_TEMP_SETPT", temperatureValue);
  }

  Future<void> requestTemperatureStatus() async {
    await refreshData();
  }

  Color get sensor10Color {
    if (_sensorFaults.length <= 9) return Colors.red;
    return _sensorFaults[9] == "1" ? Colors.green : Colors.red;
  }

  bool isSensorHealthy(int index) {
    if (index < 0 || index >= _sensorFaults.length) return false;
    return _sensorFaults[index] == "1";
  }

  Color getSensorColor(int index, Color healthyColor) {
    return isSensorHealthy(index) ? healthyColor : Colors.red;
  }

  bool get isMGPSHealthy {
    for (int i = 0; i < 4; i++) {
      if (_sensorFaults.length <= i || _sensorFaults[i] != "1") {
        return false;
      }
    }
    return true;
  }

  Color get mgpsColor {
    return isMGPSHealthy ? Colors.green : Colors.red;
  }

  // ── HUMIDITY METHODS ──────────────────────────────────────────────────────

  static const double _minHumidity = 45.0;
  static const double _maxHumidity = 55.0;
  static const double _humidityStep = 0.5;

  void adjustHumidity(double change) {
    double newValue = humiditySetpointAsDouble + change;

    // Clamp between min and max
    newValue = newValue.clamp(_minHumidity, _maxHumidity);

    // Round to step
    newValue = (newValue / _humidityStep).round() * _humidityStep;

    _humiditySetpoint = newValue.toStringAsFixed(1);

    notifyListeners();
  }

  Future<void> setHumiditySetpoint() async {
    double value = humiditySetpointAsDouble;

    final String humidityValue = (value * 10).round().toString().padLeft(
      3,
      '0',
    );

    // Activate guard before sending
    _humiditySetpointGuardUntil = DateTime.now().add(_setpointGuardDuration);
    print('🛡️ Humidity guard active until $_humiditySetpointGuardUntil');

    await _sendControl("S_RH_SETPT", humidityValue);
  }

  // ── LIGHT METHODS ─────────────────────────────────────────────────────────

  Future<void> toggleLight(int lightNumber, bool value) async {
    if (lightNumber < 1 || lightNumber > 10) {
      print('❌ Invalid light number: $lightNumber');
      return;
    }
    _lightStates[lightNumber - 1] = value;

    // Update backward compatibility variables for lights 8, 9, 10
    if (lightNumber == 8) _defumigation = value;
    if (lightNumber == 9) _dayNightMode = value;
    if (lightNumber == 10) _systemPower = value;

    notifyListeners();
    await _sendControl("S_Light_${lightNumber}_ON_OFF", value ? "1" : "0");
  }

  Future<void> toggleMultipleLights(Map<int, bool> lightStates) async {
    if (lightStates.isEmpty) return;
    Map<String, String> controls = {};
    lightStates.forEach((lightNumber, value) {
      if (lightNumber >= 1 && lightNumber <= 10) {
        _lightStates[lightNumber - 1] = value;

        // Update backward compatibility variables for lights 8, 9, 10
        if (lightNumber == 8) _defumigation = value;
        if (lightNumber == 9) _dayNightMode = value;
        if (lightNumber == 10) _systemPower = value;

        controls["S_Light_${lightNumber}_ON_OFF"] = value ? "1" : "0";
      }
    });
    notifyListeners();
    if (controls.isNotEmpty) await _sendMultipleControls(controls);
  }

  Future<void> toggleAllLights(bool value) async {
    Map<String, String> controls = {};

    // Toggle ALL 10 lights
    for (int i = 1; i <= 10; i++) {
      _lightStates[i - 1] = value;
      controls["S_Light_${i}_ON_OFF"] = value ? "1" : "0";
    }

    // Update backward compatibility variables
    _defumigation = value; // Light 8
    _dayNightMode = value; // Light 9
    _systemPower = value; // Light 10

    notifyListeners();
    await _sendMultipleControls(controls);
    print('💡 All lights set to: $value');
  }

  Future<void> setLightPattern(List<bool> pattern) async {
    if (pattern.length > 10) return;
    Map<String, String> controls = {};
    for (int i = 0; i < pattern.length && i < 10; i++) {
      _lightStates[i] = pattern[i];
      controls["S_Light_${i + 1}_ON_OFF"] = pattern[i] ? "1" : "0";
    }

    // Update backward compatibility variables for lights 8, 9, 10
    if (pattern.length > 7) _defumigation = pattern[7]; // Light 8 (index 7)
    if (pattern.length > 8) _dayNightMode = pattern[8]; // Light 9 (index 8)
    if (pattern.length > 9) _systemPower = pattern[9]; // Light 10 (index 9)

    notifyListeners();
    await _sendMultipleControls(controls);
  }

  // Backward compatibility toggle methods
  Future<void> toggleDefumigation(bool value) async => toggleLight(8, value);
  Future<void> toggleSystemPower(bool value) async => toggleLight(10, value);
  Future<void> toggleDayNightMode(bool value) async => toggleLight(9, value);

  // ── Polling ───────────────────────────────────────────────────────────────
  void startPolling() {
    stopPolling();
    print('🔄 Starting polling to $_esp32IP');
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkConnection();
      if (_isConnected) _fetchData();
    });
    // Immediate first check
    _checkConnection();
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // ── FIX: Use _esp32IP instead of hardcoded IP ─────────────────────────────

  Future<void> _checkConnection() async {
    try {
      final response = await http
          .get(Uri.parse('http://$_esp32IP/connection-test')) // ✅ FIXED
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        if (!_isConnected) {
          _isConnected = true;
          print("✅ Connected to ESP32 at $_esp32IP");
          // Fetch data immediately on connection
          await _fetchData();
          notifyListeners();
        }
      } else {
        if (_isConnected) {
          _isConnected = false;
          print("❌ Connection lost to ESP32");
          notifyListeners();
        }
      }
    } catch (e) {
      if (_isConnected) {
        _isConnected = false;
        print("❌ Disconnected from ESP32: $e");
        notifyListeners();
      }
    }
  }

  Future<void> refreshData() async {
    print('🔄 Manual refresh triggered');
    await _checkConnection();
    if (_isConnected) {
      await _fetchData();
    } else {
      print('⚠️ Not connected, cannot refresh');
    }
  }

  Future<void> _fetchData() async {
    if (!_isConnected) return;

    try {
      print('📡 Trying /all-parameters at $_esp32IP...');
      final response = await http
          .get(Uri.parse('http://$_esp32IP/all-parameters')) // ✅ FIXED
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.containsKey('sensor_faults')) {
          _parseAllParameters(data);
          return;
        }
      }
    } catch (e) {
      print("⚠️ /all-parameters failed: $e");
    }

    try {
      print('📡 Trying /sensor-data at $_esp32IP...');
      final response = await http
          .get(Uri.parse('http://$_esp32IP/sensor-data')) // ✅ FIXED
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Received sensor data: $data');
        _parseSensorData(data);
        return;
      }
    } catch (e) {
      print("⚠️ /sensor-data failed: $e");
    }

    try {
      print('📡 Trying /data at $_esp32IP...');
      final response = await http
          .get(Uri.parse('http://$_esp32IP/data')) // ✅ FIXED
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String rawData = data['data'];
        print('✅ Received legacy data: $rawData');
        if (rawData.contains('F_Sensor')) {
          _parseData(rawData);
          return;
        }
      }
    } catch (e) {
      print("⚠️ /data failed: $e");
    }

    print("❌ All endpoints failed");
    _isConnected = false;
    notifyListeners();
  }

  // ── Parsers ───────────────────────────────────────────────────────────────

  void _parseAllParameters(Map<String, dynamic> data) {
    bool changed = false;

    try {
      if (data['temperature'] != null) {
        String newTemp = data['temperature'].toString();
        print('🌡️ Temperature from ESP: $newTemp');
        if (_currentTemperature != newTemp) {
          _currentTemperature = newTemp;
          changed = true;
        }
      }

      if (data['humidity'] != null) {
        String newHumidity = data['humidity'].toString();
        print('💧 Humidity from ESP: $newHumidity');
        if (_currentHumidity != newHumidity) {
          _currentHumidity = newHumidity;
          changed = true;
        }
      }

      if (data['pressure2'] != null) {
        int pressureInt = int.tryParse(data['pressure2'].toString()) ?? 0;
        String newPressure = pressureInt.toString();
        print('📊 Pressure from ESP: $newPressure');
        if (_pressureValue != newPressure) {
          _pressureValue = newPressure;
          changed = true;
        }
      }

      if (data['pressure2_positive'] != null) {
        bool newPositive = data['pressure2_positive'] == true;
        if (_isPressurePositive != newPositive) {
          _isPressurePositive = newPositive;
          changed = true;
        }
      }

      if (data['sensor_faults'] != null && data['sensor_faults'] is List) {
        final faultList = data['sensor_faults'] as List;
        for (int i = 0; i < faultList.length && i < _sensorFaults.length; i++) {
          String newValue = faultList[i].toString();
          if (_sensorFaults[i] != newValue) {
            _sensorFaults[i] = newValue;
            changed = true;
          }
        }
      }

      if (data['humidity_setpoint'] != null) {
        if (_isHumidityGuardActive) {
          print('🛡️ Humidity guard active — ignoring ESP32 value');
        } else {
          String newSetpoint = data['humidity_setpoint'].toString();
          if (_humiditySetpoint != newSetpoint) {
            _humiditySetpoint = newSetpoint;
            changed = true;
            print('💧 Humidity setpoint updated: $_humiditySetpoint');
          }
        }
      }

      if (data['temperature_setpoint'] != null) {
        if (_isTemperatureGuardActive) {
          print('🛡️ Temperature guard active — ignoring ESP32 value');
        } else {
          String newSetpoint = data['temperature_setpoint'].toString();
          if (_temperatureSetpoint != newSetpoint) {
            _temperatureSetpoint = newSetpoint;
            _pendingTemperature = double.tryParse(newSetpoint) ?? 25.0;
            changed = true;
            print('🌡️ Temperature setpoint updated: $_temperatureSetpoint');
          }
        }
      }

      if (data['light_status'] != null && data['light_status'] is List) {
        final lightList = data['light_status'] as List;
        for (int i = 0; i < lightList.length && i < _lightStates.length; i++) {
          bool newState = lightList[i] == 1 || lightList[i] == "1";
          if (_lightStates[i] != newState) {
            _lightStates[i] = newState;
            if (i == 7) _defumigation = newState;
            if (i == 8) _dayNightMode = newState;
            if (i == 9) _systemPower = newState;
            changed = true;
          }
        }
      }

      if (changed) {
        print('✅ Data changed, notifying listeners');
        notifyListeners();
      }
    } catch (e) {
      print("❌ Error parsing all parameters: $e");
    }
  }

  void _parseSensorData(Map<String, dynamic> data) {
    print('📊 Parsing sensor data');
    bool changed = false;

    try {
      if (data['temperature'] != null) {
        String newTemp = data['temperature'].toString();
        if (_currentTemperature != newTemp) {
          _currentTemperature = newTemp;
          changed = true;
        }
      }

      if (data['humidity'] != null) {
        String newHumidity = data['humidity'].toString();
        if (_currentHumidity != newHumidity) {
          _currentHumidity = newHumidity;
          changed = true;
        }
      }

      if (data['pressure'] != null) {
        final pressureDouble =
            double.tryParse(data['pressure'].toString()) ?? 0.0;
        int pressureInt = (pressureDouble * 100).toInt();
        String newPressure = pressureInt.toString();
        if (_pressureValue != newPressure) {
          _pressureValue = newPressure;
          changed = true;
        }
      }

      if (data['pressure_positive'] != null) {
        bool newPositive =
            data['pressure_positive'] == true ||
            data['pressure_positive'] == "1" ||
            data['pressure_positive'] == 1;
        if (_isPressurePositive != newPositive) {
          _isPressurePositive = newPositive;
          changed = true;
        }
      }

      for (int i = 1; i <= 10; i++) {
        String key1 = 'F_Sensor_${i}_FAULT_BIT';
        String key2 = 'sensor_fault_$i';
        if (data.containsKey(key1)) {
          String newValue = data[key1].toString();
          if (_sensorFaults[i - 1] != newValue) {
            _sensorFaults[i - 1] = newValue;
            changed = true;
          }
        } else if (data.containsKey(key2)) {
          String newValue = data[key2].toString();
          if (_sensorFaults[i - 1] != newValue) {
            _sensorFaults[i - 1] = newValue;
            changed = true;
          }
        }
      }

      if (changed) {
        print('✅ Sensor data changed, notifying listeners');
        notifyListeners();
      }
    } catch (e) {
      print("❌ Error parsing sensor data: $e");
    }
  }

  void _parseData(String data) {
    print('🔄 Parsing legacy data');
    bool changed = false;

    try {
      final tempMatch = RegExp(r'C_OT_TEMP:(\d+)').firstMatch(data);
      if (tempMatch != null) {
        String newTemp = ((int.tryParse(tempMatch.group(1) ?? '0') ?? 0) / 10.0)
            .toStringAsFixed(1);
        if (_currentTemperature != newTemp) {
          _currentTemperature = newTemp;
          changed = true;
        }
      }

      final humidityMatch = RegExp(r'C_RH:(\d+)').firstMatch(data);
      if (humidityMatch != null) {
        String newHumidity =
            ((int.tryParse(humidityMatch.group(1) ?? '0') ?? 0) / 10.0)
                .toStringAsFixed(1);
        if (_currentHumidity != newHumidity) {
          _currentHumidity = newHumidity;
          changed = true;
        }
      }

      final pressureMatch = RegExp(r'C_PRESSURE_2:(\d+)').firstMatch(data);
      final pressureSignMatch = RegExp(
        r'C_PRESSURE_2_SIGN_BIT:(\d+)',
      ).firstMatch(data);
      if (pressureMatch != null) {
        final pressureInt = int.tryParse(pressureMatch.group(1) ?? '0') ?? 0;
        String newPressure = (pressureInt * 100).toInt().toString();
        if (_pressureValue != newPressure) {
          _pressureValue = newPressure;
          changed = true;
        }
        _isPressurePositive = pressureSignMatch?.group(1) == '0';
      }

      if (changed) {
        print('✅ Legacy data changed, notifying listeners');
        notifyListeners();
      }
    } catch (e) {
      print("❌ Error parsing legacy data: $e");
    }
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> sendControl(String key, String value) async {
    await _sendControl(key, value);
  }

  Future<void> _sendControl(String key, String value) async {
    print('🚀 Sending control: $key = $value to $_esp32IP');
    try {
      final response = await http
          .post(
            Uri.parse('http://$_esp32IP/control'), // ✅ FIXED
            body: {key: value},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        print('✅ Control $key = $value confirmed by ESP32');

        if (key == "S_RH_SETPT") {
          print(
            '🛡️ Humidity guard remains active until $_humiditySetpointGuardUntil',
          );
        } else if (key == "S_TEMP_SETPT") {
          print(
            '🛡️ Temperature guard remains active until $_temperatureSetpointGuardUntil',
          );
        } else if (key.startsWith("S_Light_") && key.endsWith("_ON_OFF")) {
          final lightNumber =
              int.tryParse(key.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          if (lightNumber >= 1 && lightNumber <= 10) {
            _lightStates[lightNumber - 1] = value == "1";

            if (lightNumber == 8) _defumigation = value == "1";
            if (lightNumber == 9) _dayNightMode = value == "1";
            if (lightNumber == 10) _systemPower = value == "1";

            notifyListeners();
          }
        }
      } else {
        print('❌ Control failed: ${response.statusCode}');
        throw Exception('Control failed: ${response.statusCode}');
      }
    } catch (e) {
      print("❌ Failed to send control: $e");
      rethrow;
    }
  }

  Future<void> _sendMultipleControls(Map<String, String> controls) async {
    print('🚀 Sending multiple controls to $_esp32IP: $controls');
    try {
      final response = await http
          .post(
            Uri.parse('http://$_esp32IP/control'), // ✅ FIXED
            body: controls,
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        print('✅ Multiple controls confirmed');
        controls.forEach((key, value) {
          if (key.startsWith("S_Light_") && key.endsWith("_ON_OFF")) {
            final n = int.tryParse(key.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            if (n >= 1 && n <= 10) {
              _lightStates[n - 1] = value == "1";

              // Update backward compatibility variables for lights 8, 9, 10
              if (n == 8) _defumigation = value == "1";
              if (n == 9) _dayNightMode = value == "1";
              if (n == 10) _systemPower = value == "1";
            }
          }
        });
        notifyListeners();
      } else {
        print('❌ Multiple controls failed: ${response.statusCode}');
      }
    } catch (e) {
      print("❌ Multiple controls error: $e");
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  String getFormattedPressure() {
    int pressureInt = int.tryParse(_pressureValue) ?? 0;
    String formattedValue = pressureInt.toString();
    return _isPressurePositive ? formattedValue : "-$formattedValue";
  }

  Color getPressureColor() {
    return _isPressurePositive ? Colors.greenAccent : Colors.redAccent;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
