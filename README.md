# ble_operations plugin

A Flutter plugin to perform Bluetooth Low Energy (BLE) operations such as:

- Advertising a custom service UUID
- Scanning for nearby BLE devices
- Managing BLE runtime permissions
- Restoring advertising state across device reboots

---

## Supported Versions

| Component | Version                      |
| --------- | ---------------------------- |
| Dart      | >=3.0.0 <4.0.0               |
| Flutter   | >=3.10.0                     |
| Android   | API level 23+ (Android 6.0+) |
| iOS       | 13.0+                        |

---

## Features

- Start/stop BLE advertising (UUID) – background and killed states also supported on Android
- Pass a UUID as an argument to start advertising
- Start/stop BLE scanning
- Request runtime permissions (Android 12+ supported)
- Check state (Bluetooth enabled, advertising in foreground/background, scanning)
- Get and clear scanned devices
- Discovered devices are streamed to Flutter via `ble_advertiser_scan_results`  
  Each device list item includes:  
  `id`, `name`, `rssi`, `timestamp`, `serviceUUIDs`, and optional manufacturer information
- Only one advertising mode can be active at a time (foreground or background) – the plugin enforces this by disabling background mode before starting foreground advertising and vice versa
- If during an ongoing background or killed-state advertising session the device is switched off (by the user or OS), the advertising is automatically restarted once the device is powered back on

---

## Android Services Used

**For BLE Operations:**  
`BluetoothAdapter`, `BluetoothLeScanner`, `ParcelUUID`, `EventChannel`, `MethodChannel`

**For Notifications:**  
`NotificationManager`, `NotificationChannel`, `NotificationCompat`

**Other Core Components:**  
`Context`, `PackageManager`, `Intent`, `BroadcastReceiver`, `ActivityCompat`, `Manifest`, `Build`, `Log`, `Handler`, `HandlerThread`

**For Flutter Plugin Integration:**  
`FlutterPlugin`, `ActivityAware`, `ActivityPluginBinding`

---

## Android Setup

### Required Permissions

Add the following permissions to your app's `AndroidManifest.xml` file:
```xml
<uses-feature
    android:name="android.hardware.bluetooth_le"
    android:required="false" />

<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />

<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />

<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />

<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

---

## iOS Support and Limitations

**Important Note:**  
As of the current version, BLE operations on iOS work **only in foreground mode**.

- Advertising and scanning stop when the app enters the background or is killed.
- Background BLE restoration, persistent state recovery, and full UIScene lifecycle support are not yet implemented.
- These limitations are temporary and will be addressed in future updates.

### iOS Setup

Add the following keys to your app’s `Info.plist` file:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to advertise and scan for nearby devices.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app requires location access for BLE scanning.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app requires location access for BLE scanning.</string>
```

---

# Notes

## Shared Preferences

Make sure you name the shared preferences key as `"ble_prefs"` to save and restore state.

**The keys of the key-value pairs in `"ble_prefs"` include:**

1. **`background_mode_enabled`** (Boolean)  
   Used to keep track of whether background advertising was turned on or not.

2. **`last_uuid`** (String)  
   Used to save the most recent UUID used for advertising.

The UI makes use of this to manage state and reflect changes based upon it.

---

## Using the ble_operations Plugin in an App

### 1. Include the plugin

Add the plugin under the `dependencies` section in the `pubspec.yaml` of the app you're building:
```yaml
dependencies:
  ble_operations:
    path: the_path_to_the_plugin
```

### 2. Request permissions at runtime

During app launch at runtime, request the necessary permissions required to perform the BLE operations if not already granted using the `requestBluetoothPermissions` function that is already defined:
```dart
import 'package:ble_operations/ble_operations.dart';
await BleOperations.requestBluetoothPermissions();
```

### 3. Import and use BLE operations

Import the `ble_operations.dart` file of the package to make use of the functions defined to perform the BLE operations:
```dart
import 'package:ble_operations/ble_operations.dart';
await BleOperations.getScannedDevices();
```

**For reference on how to make use of the plugin, an example app using the plugin is available under the `example` folder of the plugin.**

---

# Example - Recordings

 - [View Recording - Advertiser](recordings/advertiser.mp4)
 - [View Recording - Scanner](recordings/scanner.mp4)
