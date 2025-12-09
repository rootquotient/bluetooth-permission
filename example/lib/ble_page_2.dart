import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'details_page.dart';
import 'package:ble_operations/ble_operations.dart';

class BLEHomePage extends StatefulWidget {
  const BLEHomePage({super.key});

  @override
  BLEHomePageState createState() => BLEHomePageState();
}

class BLEHomePageState extends State<BLEHomePage> with WidgetsBindingObserver {
  static const platform = MethodChannel('ble_advertiser_scanner');
  bool _isAdvertising = false;
  bool _isScanning = false;
  bool _backgroundModeEnabled = false;
  String _currentAdvertisingUUID = '';
  String _bluetoothState = 'unknown';
  String _peripheralState = 'unknown';
  String _locationAuthStatus = 'unknown';
  List<Map<String, dynamic>> _scannedDevices = [];
  int _deviceRank(Map<String, dynamic> d) {
    final uuids = List<String>.from(d['serviceUUIDs'] ?? const []);
    return uuids.isNotEmpty ? 0 : 1;
  }

  void _sortScannedDevices() {
    _scannedDevices.sort((a, b) {
      final rankA = _deviceRank(a);
      final rankB = _deviceRank(b);
      if (rankA != rankB) return rankA.compareTo(rankB);

      final rssiA = (a['rssi'] ?? -999) as int;
      final rssiB = (b['rssi'] ?? -999) as int;
      if (rssiA != rssiB) return rssiB.compareTo(rssiA);

      final tsA = ((a['timestamp'] ?? 0) as num).toDouble();
      final tsB = ((b['timestamp'] ?? 0) as num).toDouble();
      return tsB.compareTo(tsA);
    });
  }

  final TextEditingController _uuidController = TextEditingController();
  final Uuid _uuidGenerator = Uuid();
  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();
  List<String> _logMessages = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupMethodChannelHandler();
    _setupEventChannelListener();
    _loadSavedUUID();
    _checkInitialStates();
    _testEventChannel();
  }

  List<Map<String, dynamic>> _detectedBeacons = [];
  void _setupEventChannelListener() {
    _scanSubscription?.cancel();
    _scanSubscription = BleOperations.listenForScanResults().listen(
      (dynamic event) {
        if (event is Map<String, dynamic>) {
          _handleDeviceDiscovered(event);
        }
      },
      onError: (dynamic error) {
        _addLog('EventChannel error: $error');
      },
      onDone: () {
        _addLog('EventChannel stream closed');
      },
    );
  }

  void _handleBeaconDetected(dynamic arguments) {
    final beacon = Map<String, dynamic>.from(arguments);
    final uuid = beacon['uuid'];
    final major = beacon['major'].toString();
    final minor = beacon['minor'].toString();
    final key = '$uuid-$major-$minor';
    beacon['key'] = key;
    final existingIndex = _detectedBeacons.indexWhere((b) => b['key'] == key);
    setState(() {
      if (existingIndex != -1) {
        _detectedBeacons[existingIndex] = beacon;
      } else {
        _detectedBeacons.insert(0, beacon);
        if (_detectedBeacons.length > 50) {
          _detectedBeacons = _detectedBeacons.take(50).toList();
        }
      }
    });
    _addLog(
        'iBeacon detected: UUID=$uuid Major=$major Minor=$minor RSSI=${beacon['rssi']}');
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _logStreamController.close();
    _uuidController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _addLog('App lifecycle state: ${state.toString()}');
    if (state == AppLifecycleState.paused) {
      _addLog('App backgrounded - BLE operations should continue');
    } else if (state == AppLifecycleState.resumed) {
      _addLog('App foregrounded - refreshing status');
    }
  }

  void _handleDeviceUpdated(dynamic arguments) {
    final updatedInfo = Map<String, dynamic>.from(arguments);
    final deviceId = updatedInfo['id'];

    final existingIndex =
        _scannedDevices.indexWhere((d) => d['id'] == deviceId);
    if (existingIndex != -1) {
      setState(() {
        final existing = _scannedDevices[existingIndex];
        existing['timestamp'] = updatedInfo['timestamp'];
        existing['rssi'] = updatedInfo['rssi'];
        _scannedDevices[existingIndex] = existing;
        _sortScannedDevices();
      });

      _addLog(
          'Device updated (timestamp refreshed): ${updatedInfo['name']} - ${updatedInfo['id']}');
    }
  }

  void _setupMethodChannelHandler() {
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDeviceDiscovered':
          _handleDeviceDiscovered(call.arguments);
          break;
        case 'onDeviceUpdated':
          _handleDeviceUpdated(call.arguments);
          break;
        case 'onBeaconDetected':
          _handleBeaconDetected(call.arguments);
          break;
        case 'onAdvertisingStarted':
          setState(() {
            _isAdvertising = true;
            _currentAdvertisingUUID = call.arguments['uuid'] ?? '';
          });
          _addLog('Foreground advertising started: $_currentAdvertisingUUID');
          _saveUUID(_currentAdvertisingUUID);
          break;
        case 'onAdvertisingStopped':
          setState(() {
            _isAdvertising = false;
            _currentAdvertisingUUID = '';
          });
          _addLog('Foreground advertising stopped');
          break;
        case 'onScanningStarted':
          setState(() => _isScanning = true);
          _addLog('Scanning started');
          break;
        case 'onScanningStopped':
          setState(() => _isScanning = false);
          _addLog('Scanning stopped');
          break;
        case 'onBluetoothStateChanged':
          setState(() => _bluetoothState = call.arguments['state']);
          _addLog('Bluetooth state: $_bluetoothState');
          break;
        case 'onPeripheralStateChanged':
          setState(() => _peripheralState = call.arguments['state']);
          _addLog('Peripheral state: $_peripheralState');
          break;
        case 'onLocationAuthorizationChanged':
          setState(() => _locationAuthStatus = call.arguments['status']);
          _addLog('Location auth: $_locationAuthStatus');
          break;
        case 'onBackgroundModeEnabled':
          setState(() {
            _backgroundModeEnabled = true;
            _currentAdvertisingUUID =
                call.arguments['uuid'] ?? _uuidController.text;
          });
          _addLog(
              'Background advertising enabled with UUID: $_currentAdvertisingUUID');
          _saveUUID(_currentAdvertisingUUID);
          break;
        case 'onBackgroundModeDisabled':
          setState(() {
            _backgroundModeEnabled = false;
            _currentAdvertisingUUID = '';
          });
          _addLog('Background advertising disabled');
          break;
        case 'onAdvertisingError':
          _addLog('Advertising error: ${call.arguments['error']}');
          break;
      }
    });
  }

  void _handleDeviceDiscovered(dynamic arguments) {
    final deviceInfo = Map<String, dynamic>.from(arguments);
    final serviceUUIDs = List<String>.from(deviceInfo['serviceUUIDs'] ?? []);
    final isBeacon = deviceInfo['isBeacon'] == true;

    _addLog(
        'Device discovered: ${deviceInfo['name']} (${deviceInfo['rssi']} dBm) - ID: ${deviceInfo['id']}');

    if (isBeacon) {
      final existingIndex =
          _detectedBeacons.indexWhere((d) => d['id'] == deviceInfo['id']);
      if (existingIndex != -1) {
        setState(() {
          _detectedBeacons[existingIndex] = deviceInfo;
        });
      } else {
        setState(() {
          _detectedBeacons.insert(0, deviceInfo);
          if (_detectedBeacons.length > 50) {
            _detectedBeacons = _detectedBeacons.take(50).toList();
          }
        });
      }
    } else {
      final existingIndex =
          _scannedDevices.indexWhere((d) => d['id'] == deviceInfo['id']);
      if (existingIndex != -1) {
        final existingDevice = _scannedDevices[existingIndex];
        final isSame = existingDevice['rssi'] == deviceInfo['rssi'] &&
            existingDevice['name'] == deviceInfo['name'] &&
            ListEquality().equals(existingDevice['serviceUUIDs'], serviceUUIDs);
        if (isSame) return;

        setState(() {
          _scannedDevices[existingIndex] = deviceInfo;
          _sortScannedDevices();
        });
      } else {
        setState(() {
          _scannedDevices.insert(0, deviceInfo);
          if (_scannedDevices.length > 50) {
            _scannedDevices = _scannedDevices.take(50).toList();
          }
          _sortScannedDevices();
        });
      }
    }
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';
    setState(() {
      _logMessages.insert(0, logMessage);
      if (_logMessages.length > 100) {
        _logMessages = _logMessages.take(100).toList();
      }
    });
    _logStreamController.add(logMessage);
  }

  Future<void> _loadSavedUUID() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUUID = prefs.getString('last_uuid');
    if (savedUUID != null && savedUUID.isNotEmpty) {
      setState(() {
        _uuidController.text = savedUUID;
      });
    } else {
      final newUUID = _uuidGenerator.v4();
      setState(() {
        _uuidController.text = newUUID;
      });
      await prefs.setString('last_uuid', newUUID);
    }
    _addLog('Loaded UUID: ${_uuidController.text}');
  }

  Future<void> _saveUUID(String uuid) async {
    if (uuid.isNotEmpty && (_isAdvertising || _backgroundModeEnabled)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_uuid', uuid);
      setState(() {
        _currentAdvertisingUUID = uuid;
      });
      _addLog('Saved UUID: $uuid');
    }
  }

  Future<void> _checkInitialStates() async {
    try {
      final bluetoothEnabled = await BleOperations.isBluetoothEnabled();
      final isAdvertising = await BleOperations.isAdvertising();
      final isScanning = await BleOperations.isScanning();
      final isBackgroundEnabled = await BleOperations.isBackgroundModeEnabled();
      try {
        final devices = await BleOperations.getScannedDevices();
        _scannedDevices = devices;
      } catch (e) {
        _addLog('getScannedDevices not implemented: $e');
      }
      final prefs = await SharedPreferences.getInstance();
      final savedUUID = prefs.getString('last_uuid') ?? '';
      setState(() {
        _isAdvertising = isAdvertising;
        _isScanning = isScanning;
        _backgroundModeEnabled = isBackgroundEnabled;
        _currentAdvertisingUUID =
            (isAdvertising || isBackgroundEnabled) ? savedUUID : '';
      });
      _addLog(
          'Initial states loaded - BT: $bluetoothEnabled, Adv: $_isAdvertising, Scan: $_isScanning, Background: $_backgroundModeEnabled, UUID: $_currentAdvertisingUUID');
    } catch (e) {
      _addLog('Error loading initial states: $e');
    }
  }

  Future<void> _startAdvertising() async {
    final uuid = _uuidController.text.trim();
    if (uuid.isEmpty) {
      _showSnackBar('Please enter a UUID');
      return;
    }
    try {
      if (Platform.isIOS) {
        _addLog('Foreground advertising requested: $uuid');
        await BleOperations.startAdvertising(uuid);
      } else {
        _addLog('Foreground advertising requested: $uuid');
        await BleOperations.startAdvertising(uuid);
      }
      await _saveUUID(uuid);
    } catch (e) {
      _addLog('Error starting advertising: $e');
      _showSnackBar('Failed to start advertising: $e');
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      _addLog('Stop foreground advertising requested');
      await BleOperations.stopAdvertising();
    } catch (e) {
      _addLog('Error stopping advertising: $e');
      _showSnackBar('Failed to stop advertising: $e');
    }
  }

  Future<void> _startScanning() async {
    try {
      _addLog('Start scanning requested');
      await BleOperations.startScanning();
      if (_scanSubscription == null) {
        _setupEventChannelListener();
      }
    } catch (e) {
      _addLog('Error starting scanning: $e');
      _showSnackBar('Failed to start scanning: $e');
    }
  }

  Future<void> _testEventChannel() async {
    final testSub = BleOperations.listenForScanResults().listen(
      (dynamic event) {
        _addLog('TEST: EventChannel is working! Received: $event');
      },
      onError: (dynamic error) {
        _addLog('TEST: EventChannel error: $error');
      },
    );

    Timer(Duration(seconds: 5), () {
      testSub.cancel();
    });
  }

  Future<void> _stopScanning() async {
    try {
      _addLog('Stop scanning requested');
      await BleOperations.stopScanning();
    } catch (e) {
      _addLog('Error stopping scanning: $e');
      _showSnackBar('Failed to stop scanning: $e');
    }
  }

  Future<void> _clearScannedDevices() async {
    try {
      await BleOperations.clearScannedDevices();
      setState(() => _scannedDevices.clear());
      _addLog('Scanned devices cleared');
    } catch (e) {
      _addLog('Error clearing devices: $e');
      setState(() => _scannedDevices.clear());
    }
  }

  Future<void> _toggleBackgroundMode() async {
    try {
      if (_backgroundModeEnabled) {
        _addLog('Background advertising disable requested');
        await BleOperations.disableBackgroundMode();
      } else {
        final uuid = _uuidController.text.trim();
        if (uuid.isEmpty) {
          _showSnackBar('Please enter a UUID before enabling background mode');
          return;
        }
        await _saveUUID(uuid);
        _addLog('Background advertising enable requested with UUID: $uuid');
        await BleOperations.enableBackgroundMode(uuid);
      }
    } catch (e) {
      _addLog('Error toggling background mode: $e');
      _showSnackBar('Failed to toggle background mode: $e');
    }
  }

  void _generateNewUUID() {
    final newUUID = _uuidGenerator.v4();
    _uuidController.text = newUUID;
    if (!_isAdvertising && !_backgroundModeEnabled) {
      setState(() {
        _currentAdvertisingUUID = '';
      });
    }
    _addLog('Generated new UUID: $newUUID');
  }

  void _showSnackBar(String message) {
    log(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Color _getStateColor(String state) {
    switch (state.toLowerCase()) {
      case 'poweredon':
        return Colors.green;
      case 'poweredoff':
        return Colors.red;
      case 'authorized':
      case 'authorizedalways':
        return Colors.green;
      case 'denied':
      case 'unauthorized':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('BLE Advertiser Scanner'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                    child: Row(
                  children: [
                    _StatusChip('BLE', _bluetoothState,
                        _getStateColor(_bluetoothState)),
                    SizedBox(width: 8),
                    _StatusChip('Peripheral', _peripheralState,
                        _getStateColor(_peripheralState)),
                    SizedBox(width: 8),
                    _StatusChip('Location', _locationAuthStatus,
                        _getStateColor(_locationAuthStatus)),
                  ],
                )),
                SizedBox(height: 8),
                Row(
                  children: [
                    _StatusChip('Advertising', _isAdvertising ? 'ON' : 'OFF',
                        _isAdvertising ? Colors.green : Colors.grey),
                    SizedBox(width: 8),
                    _StatusChip('Scanning', _isScanning ? 'ON' : 'OFF',
                        _isScanning ? Colors.green : Colors.grey),
                    SizedBox(width: 8),
                    _StatusChip(
                        'Background',
                        _backgroundModeEnabled ? 'ON' : 'OFF',
                        _backgroundModeEnabled ? Colors.blue : Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    labelColor: Colors.blue,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(text: 'Advertise'),
                      Tab(text: 'Scan (${_scannedDevices.length})'),
                      Tab(text: 'Logs'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildAdvertiseTab(),
                        _buildScanTab(),
                        _buildLogsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvertiseTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UUID to Advertise',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _uuidController,
                          decoration: InputDecoration(
                            labelText: 'Service UUID',
                            border: OutlineInputBorder(),
                            hintText: 'Enter UUID or generate new one',
                          ),
                          onChanged: (value) {
                            if (_isAdvertising || _backgroundModeEnabled) {
                              _saveUUID(value);
                            }
                          },
                        ),
                      ),
                      SizedBox(width: 8),
                      IconButton(
                        onPressed: _generateNewUUID,
                        icon: Icon(Icons.refresh),
                        tooltip: 'Generate New UUID',
                      ),
                    ],
                  ),
                  if (_currentAdvertisingUUID.isNotEmpty &&
                      (_isAdvertising || _backgroundModeEnabled)) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.green[200] ?? Colors.green),
                      ),
                      child: Text(
                        'Currently advertising: $_currentAdvertisingUUID',
                        style:
                            TextStyle(color: Colors.green[800], fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isAdvertising ? null : _startAdvertising,
                  icon: Icon(Icons.broadcast_on_personal),
                  label: Text('Start Advertising'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: !_isAdvertising ? null : _stopAdvertising,
                  icon: Icon(Icons.stop),
                  label: Text('Stop Advertising'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _toggleBackgroundMode,
            icon: Icon(_backgroundModeEnabled ? Icons.pause : Icons.play_arrow),
            label: Text(_backgroundModeEnabled
                ? 'Stop Background Advertising'
                : 'Start Background Advertising'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _backgroundModeEnabled ? Colors.orange : Colors.blue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScanning,
                  icon: Icon(Icons.search),
                  label: Text('Start Scanning'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: !_isScanning ? null : _stopScanning,
                  icon: Icon(Icons.stop),
                  label: Text('Stop Scanning'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scannedDevices.isEmpty ? null : _clearScannedDevices,
              icon: Icon(Icons.clear_all),
              label: Text('Clear All Devices'),
            ),
          ),
        ),
        SizedBox(height: 8),
        Expanded(
          child: _scannedDevices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bluetooth_searching,
                          size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        _isScanning
                            ? 'Scanning for devices...'
                            : 'No devices found',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      if (!_isScanning)
                        Text(
                          'Start scanning to discover BLE devices',
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _scannedDevices.length,
                  itemBuilder: (context, index) {
                    final device = _scannedDevices[index];
                    return _buildDeviceCard(device);
                  },
                ),
        ),
        if (_detectedBeacons.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.location_on, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Detected iBeacons',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemCount: _detectedBeacons.length,
              itemBuilder: (context, index) {
                final beacon = _detectedBeacons[index];
                return _buildBeaconCard(beacon);
              },
            ),
          ),
        ]
      ],
    );
  }

  Widget _buildBeaconCard(Map<String, dynamic> beacon) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(Icons.bluetooth, color: Colors.deepOrange),
        title: Text('UUID: ${beacon['uuid']}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Major: ${beacon['major']}, Minor: ${beacon['minor']}'),
            Text(
                'RSSI: ${beacon['rssi']}, Accuracy: ${beacon['accuracy']?.toStringAsFixed(2)}m'),
            Text('Proximity: ${_proximityToText(beacon['proximity'])}'),
          ],
        ),
      ),
    );
  }

  String _proximityToText(dynamic proximity) {
    switch (proximity) {
      case 0:
        return "Unknown";
      case 1:
        return "Immediate";
      case 2:
        return "Near";
      case 3:
        return "Far";
      default:
        return "Unknown";
    }
  }

  Widget _buildDeviceCard(Map<String, dynamic> device) {
    final name = device['name'] ?? 'Unknown Device';
    final id = device['id'] ?? '';
    final rssi = device['rssi'] ?? 0;
    final serviceUUIDs = List<String>.from(device['serviceUUIDs'] ?? []);
    final timestamp = device['timestamp'];
    final lastSeen = timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round())
        : DateTime.now();
    final timeDiff = DateTime.now().difference(lastSeen);
    final lastSeenText = timeDiff.inSeconds < 60
        ? '${timeDiff.inSeconds}s ago'
        : '${timeDiff.inMinutes}m ago';
    return InkWell(
      child: Card(
        margin: EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getRSSIColor(rssi),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$rssi dBm',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                'ID: ${id.length > 8 ? id.substring(0, 8) + '...' : id}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Text(
                'Last seen: $lastSeenText',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (serviceUUIDs.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  'Service UUIDs:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                ...serviceUUIDs.map((uuid) => Padding(
                      padding: EdgeInsets.only(left: 8, top: 2),
                      child: Text(
                        uuid,
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.blue[700]),
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
      onTap: () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (BuildContext context) =>
                    DetailsPage(device: device)));
      },
    );
  }

  Widget _buildLogsTab() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() => _logMessages.clear());
              },
              icon: Icon(Icons.clear),
              label: Text('Clear Logs'),
            ),
          ),
        ),
        Expanded(
          child: _logMessages.isEmpty
              ? Center(
                  child: Text(
                    'No logs yet',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _logMessages.length,
                  itemBuilder: (context, index) {
                    return Container(
                      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      margin: EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: index.isEven ? Colors.grey[50] : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _logMessages[index],
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _getRSSIColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatusChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color.withOpacity(0.8),
        ),
      ),
    );
  }
}
