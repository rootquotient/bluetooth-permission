# ble_operations plugin
A Flutter plugin to perform Bluetooth Low Energy (BLE) operations such as:
- Advertising a custom service UUID 
- Scanning for nearby BLE devices
- Managing BLE runtime permissions
- Restoring advertising state across device reboots

# Supported Versions
Dart: >=3.0.0 <4.0.0
Flutter: >=3.10.0
Android: API level 23+ (Android 6.0+)

# Features
- Start/stop BLE advertising (UUID) - background & killed states also possible in android
- Pass the UUID as an argument to start advertising
- Start/stop BLE scanning
- Request runtime permissions (Android 12+ also supported)
- Check state (Bluetooth enabled, advertising(foreground/background), scanning)
- Get/clear scanned devices
- Discovered devices are streamed to Flutter via ble_advertiser_scan_results. Each device list item includes: id, name, rssi, timestamp, serviceUUIDs, optional manufacturer info, etc
- Only one advertising mode can be active at a time (foreground/background) – plugin enforces this by disabling background before foreground & vice versa
- If by during an ongoing background/killed state advertising the device is switched off either by the user or by the OS, the advertising is auto restarted once the device is switched on

# Android Services used for building the plugin: 
i.   For BLE Operations: bluetooth (BluetoothAdapter, le), ParcelUUID, EventChannel, MethodChannel
ii.  For Notifications: NotificationManager, NotificationChannel, NotificationCompat
iii. Other Core: Context, PackageManager, Intent, BroadcastReceiver, ActivityCompat, Manifest, Build, Log, Handler, HandlerThread
iv.  For Flutter Plugin: FlutterPlugin, ActivityAware, ActivityPluginBinding

# Notes
**Shared Preferences**
Make sure you name the shared preferences key as follows to save and restore state: “ble_prefs”
    The keys of the key-value pairs in “ble_prefs” include: 
i.  background_mode_enabled  -- Boolean – to keep track whether background advertising was turned on/not
ii. last_uuid  -- String  -- to save the most recent UUID used for advertising
The UI makes use of this to manage state and reflect changes based upon it.

**Using the ble_operations plugin in an app**
1.Include the plugin under the dependencies section in the pubspec.yaml of the app you’re building.
dependencies:
	ble_operations:
		path: the_path_to_the_plugin

2.During app launch at runtime request the necessary permissions required to perform the ble operations if not already granted using the requestBluetoothPermissions function that is already defined.
import 'package:ble_operations/ble_operations.dart';
await BleOperations.requestBluetoothPermissions();

3.Import the ble_operations.dart file of the package to make use of the functions defined to perform the ble operations.
import 'package:ble_operations/ble_operations.dart';
await BleOperations.getScannedDevices();

For reference on how to make use of the plugin, an example app using the plugin is available under the example folder of the plugin. 


