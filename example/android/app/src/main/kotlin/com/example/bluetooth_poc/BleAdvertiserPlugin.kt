// package com.example.bluetooth_poc

// import android.Manifest
// import android.bluetooth.BluetoothAdapter
// import android.bluetooth.BluetoothDevice
// import android.bluetooth.BluetoothManager
// import android.bluetooth.le.AdvertiseCallback
// import android.bluetooth.le.AdvertiseData
// import android.bluetooth.le.AdvertiseSettings
// import android.bluetooth.le.ScanCallback
// import android.bluetooth.le.ScanFilter
// import android.bluetooth.le.ScanResult
// import android.bluetooth.le.ScanSettings
// import android.content.Context
// import android.content.pm.PackageManager
// import android.os.Build
// import android.os.ParcelUuid
// import android.util.Log
// import androidx.core.app.ActivityCompat
// import io.flutter.embedding.engine.plugins.FlutterPlugin
// import io.flutter.embedding.engine.plugins.activity.ActivityAware
// import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
// import io.flutter.plugin.common.EventChannel
// import io.flutter.plugin.common.MethodCall
// import io.flutter.plugin.common.MethodChannel
// import java.util.UUID

// class BleAdvertiserPlugin: FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware {
//     private lateinit var methodChannel: MethodChannel
//     private lateinit var eventChannel: EventChannel
//     private lateinit var context: Context
    
//     private var bluetoothManager: BluetoothManager? = null
//     private var bluetoothAdapter: BluetoothAdapter? = null
//     private var eventSink: EventChannel.EventSink? = null
//     private var deviceUuid: String? = null
    
//     private val TAG = "BleAdvertiserPlugin"
    
//     // Advertising callback
//     private val advertiseCallback = object : AdvertiseCallback() {
//         override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
//             Log.i(TAG, "BLE Advertising started successfully")
//         }
        
//         override fun onStartFailure(errorCode: Int) {
//             Log.e(TAG, "BLE Advertising failed with error code: $errorCode")
//         }
//     }
    
//     // Scanning callback
//     private val scanCallback = object : ScanCallback() {
//         override fun onScanResult(callbackType: Int, result: ScanResult) {
//             val device = result.device
//             val rssi = result.rssi
            
//             result.scanRecord?.serviceUuids?.forEach { parcelUuid ->
//                 val scanResult = mapOf(
//                     "deviceId" to device.address,
//                     "deviceName" to (device.name ?: "Unknown"),
//                     "serviceUuid" to parcelUuid.uuid.toString(),
//                     "rssi" to rssi
//                 )
                
//                 eventSink?.success(scanResult)
//             }
//         }
        
//         override fun onScanFailed(errorCode: Int) {
//             Log.e(TAG, "BLE Scan failed with error code: $errorCode")
//         }
//     }
    
//     override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
//         context = binding.applicationContext
        
//         methodChannel = MethodChannel(binding.binaryMessenger, "ble_advertiser")
//         methodChannel.setMethodCallHandler(this)
        
//         eventChannel = EventChannel(binding.binaryMessenger, "ble_advertiser_scan_results")
//         eventChannel.setStreamHandler(this)
        
//         // Initialize Bluetooth
//         bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
//         bluetoothAdapter = bluetoothManager?.adapter
//     }
    
//     override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
//         when (call.method) {
//             "startAdvertising" -> {
//                 val serviceUuid = call.argument<String>("serviceUuid")
//                 if (serviceUuid == null) {
//                     result.error("INVALID_ARGUMENT", "Service UUID is required", null)
//                     return
//                 }
//                 deviceUuid = serviceUuid
//                 startAdvertising(serviceUuid)
//                 result.success(true)
//             }
//             "stopAdvertising" -> {
//                 stopAdvertising()
//                 result.success(true)
//             }
//             "startScanning" -> {
//                 startScanning()
//                 result.success(true)
//             }
//             "stopScanning" -> {
//                 stopScanning()
//                 result.success(true)
//             }
//             "isBluetoothEnabled" -> {
//                 result.success(bluetoothAdapter?.isEnabled ?: false)
//             }
//             else -> {
//                 result.notImplemented()
//             }
//         }
//     }
    
//     private fun startAdvertising(serviceUuidString: String) {
//         if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
//             Log.e(TAG, "Bluetooth is not enabled")
//             return
//         }
        
//         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && 
//             ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED) {
//             Log.e(TAG, "Bluetooth advertise permission not granted")
//             return
//         }
        
//         try {
//             val serviceUuid = UUID.fromString(serviceUuidString)
//             val parcelUuid = ParcelUuid(serviceUuid)
            
//             val advertiseSettings = AdvertiseSettings.Builder()
//                 .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
//                 .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
//                 .setConnectable(true)
//                 .build()
            
//             val advertiseData = AdvertiseData.Builder()
//                 .addServiceUuid(parcelUuid)
//                 .setIncludeDeviceName(false)
//                 .build()
            
//             bluetoothAdapter?.bluetoothLeAdvertiser?.startAdvertising(
//                 advertiseSettings, 
//                 advertiseData, 
//                 advertiseCallback
//             )
            
//             Log.i(TAG, "Started advertising with UUID: $serviceUuidString")
//         } catch (e: Exception) {
//             Log.e(TAG, "Error starting advertising: ${e.message}")
//         }
//     }
    
//     private fun stopAdvertising() {
//         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && 
//             ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED) {
//             return
//         }
        
//         try {
//             bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
//             Log.i(TAG, "Stopped advertising")
//         } catch (e: Exception) {
//             Log.e(TAG, "Error stopping advertising: ${e.message}")
//         }
//     }
    
//     private fun startScanning() {
//         if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
//             Log.e(TAG, "Bluetooth is not enabled")
//             return
//         }
        
//         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && 
//             ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
//             Log.e(TAG, "Bluetooth scan permission not granted")
//             return
//         }
        
//         try {
//             val scanSettings = ScanSettings.Builder()
//                 .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
//                 .build()
            
//             bluetoothAdapter?.bluetoothLeScanner?.startScan(null, scanSettings, scanCallback)
//             Log.i(TAG, "Started scanning for BLE devices")
//         } catch (e: Exception) {
//             Log.e(TAG, "Error starting scan: ${e.message}")
//         }
//     }
    
//     private fun stopScanning() {
//         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && 
//             ActivityCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
//             return
//         }
        
//         try {
//             bluetoothAdapter?.bluetoothLeScanner?.stopScan(scanCallback)
//             Log.i(TAG, "Stopped scanning")
//         } catch (e: Exception) {
//             Log.e(TAG, "Error stopping scan: ${e.message}")
//         }
//     }
    
//     override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
//         methodChannel.setMethodCallHandler(null)
//         eventChannel.setStreamHandler(null)
//         stopAdvertising()
//         stopScanning()
//     }
    
//     override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
//         eventSink = events
//     }
    
//     override fun onCancel(arguments: Any?) {
//         eventSink = null
//     }
    
//     override fun onAttachedToActivity(binding: ActivityPluginBinding) {
//         // Request permissions if needed
//     }
    
//     override fun onDetachedFromActivityForConfigChanges() {}
    
//     override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}
    
//     override fun onDetachedFromActivity() {}
// }