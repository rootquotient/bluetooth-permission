import 'package:flutter/services.dart';

class BleOperations {
  static const MethodChannel _channel = MethodChannel('ble_advertiser_scanner');
  static const EventChannel _eventChannel = EventChannel(
    'ble_advertiser_scan_results',
  );

  static Future<bool> startAdvertising(String uuid) async {
    final result = await _channel.invokeMethod('startAdvertising', {
      'serviceUuid': uuid,
    });
    return result as bool;
  }

  static Future<bool> stopAdvertising() async {
    final result = await _channel.invokeMethod('stopAdvertising');
    return result as bool;
  }

  static Future<bool> startScanning() async {
    final result = await _channel.invokeMethod('startScanning');
    return result as bool;
  }

  static Future<bool> stopScanning() async {
    final result = await _channel.invokeMethod('stopScanning');
    return result as bool;
  }

  static Future<bool> isBluetoothEnabled() async {
    final result = await _channel.invokeMethod('isBluetoothEnabled');
    return result as bool;
  }

  static Future<bool> isAdvertising() async {
    final result = await _channel.invokeMethod('isAdvertising');
    return result as bool;
  }

  static Future<bool> isScanning() async {
    final result = await _channel.invokeMethod('isScanning');
    return result as bool;
  }

  static Future<List<Map<String, dynamic>>> getScannedDevices() async {
    final List devices = await _channel.invokeMethod('getScannedDevices');
    return devices.map((d) => Map<String, dynamic>.from(d)).toList();
  }

  static Future<bool> clearScannedDevices() async {
    final result = await _channel.invokeMethod('clearScannedDevices');
    return result as bool;
  }

  static Future<bool> startSimpleAdvertising() async {
    final result = await _channel.invokeMethod('startSimpleAdvertising');
    return result as bool;
  }

  static Future<bool> enableBackgroundMode(String uuid) async {
    final result = await _channel.invokeMethod('enableBackgroundMode', {
      'serviceUuid': uuid,
    });
    return result as bool;
  }

  static Future<bool> disableBackgroundMode() async {
    final result = await _channel.invokeMethod('disableBackgroundMode');
    return result as bool;
  }

  static Future<bool> isBackgroundModeEnabled() async {
    final result = await _channel.invokeMethod('isBackgroundModeEnabled');
    return result as bool;
  }

  static Future<bool> requestBluetoothPermissions() async {
    final result = await _channel.invokeMethod('requestBluetoothPermissions');
    return result as bool;
  }

  static Stream<dynamic> listenForScanResults() {
    return _eventChannel.receiveBroadcastStream();
  }
}
