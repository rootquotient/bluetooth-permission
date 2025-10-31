## 0.0.1

# Features in this version
- Start/stop BLE advertising (UUID) - background & killed states also possible in android
- Pass the UUID as an argument to start advertising
- Start/stop BLE scanning
- Request runtime permissions (Android 12+ also supported)
- Check state (Bluetooth enabled, advertising(foreground/background), scanning)
- Get/clear scanned devices
- Discovered devices are streamed to Flutter via ble_advertiser_scan_results. Each device list item includes: id, name, rssi, timestamp, serviceUUIDs, optional manufacturer info, etc
- Only one advertising mode can be active at a time (foreground/background) – plugin enforces this by disabling background before foreground & vice versa
- If by during an ongoing background/killed state advertising the device is switched off either by the user or by the OS, the advertising is auto restarted once the device is switched on

