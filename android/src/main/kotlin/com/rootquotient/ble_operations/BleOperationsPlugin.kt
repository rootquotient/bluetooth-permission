package com.rootquotient.ble_operations

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.*

class BleOperationsPlugin : FlutterPlugin, EventChannel.StreamHandler, ActivityAware {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var activity: android.app.Activity? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var isAdvertising = false
    private var isScanning = false
    private val scannedDevices = mutableMapOf<String, Map<String, Any>>()
    private var currentAdvertisingUUID: String? = null
    private var backgroundModeEnabled: Boolean = false
    private lateinit var scanHandlerThread: HandlerThread
    private lateinit var scanHandler: Handler
    private lateinit var backgroundStopReceiver: BroadcastReceiver
    private var notificationManager: NotificationManager? = null
    private val TAG = "BleOperationsPlugin"
    private val NOTIFICATION_CHANNEL_ID = "BLE_BACKGROUND_CHANNEL"

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "ble_advertiser_scanner")
        eventChannel = EventChannel(binding.binaryMessenger, "ble_advertiser_scan_results")
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    val uuid = call.argument<String>("serviceUuid")
                    if (uuid != null) startAdvertising(uuid)
                    result.success(true)
                }
                "stopAdvertising" -> { stopAdvertising(); result.success(true) }
                "startScanning" -> { startScanning(); result.success(true) }
                "stopScanning" -> { stopScanning(); result.success(true) }
                "isBluetoothEnabled" -> result.success(bluetoothAdapter?.isEnabled ?: false)
                "isAdvertising" -> result.success(isAdvertising)
                "isScanning" -> result.success(isScanning)
                "getScannedDevices" -> result.success(scannedDevices.values.toList())
                "clearScannedDevices" -> { scannedDevices.clear(); result.success(true) }
                "enableBackgroundMode" -> {
                    val uuid = call.argument<String>("serviceUuid")
                    enableBackgroundMode(uuid)
                    result.success(true)
                }
                "disableBackgroundMode" -> { disableBackgroundMode(); result.success(true) }
                "isBackgroundModeEnabled" -> {
                    val prefs = context?.getSharedPreferences("ble_prefs", Context.MODE_PRIVATE)
                    if (prefs == null) {
                        result.success(false)
                    } else {
                        result.success(prefs.getBoolean("background_mode_enabled", false))
                    }
                }
                "requestBluetoothPermissions" -> {
                    requestBluetoothPermissions()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        eventChannel.setStreamHandler(this)
        val bluetoothManager = context?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: return
        bluetoothAdapter = bluetoothManager.adapter
        scanHandlerThread = HandlerThread("BLEScanThread")
        scanHandlerThread.start()
        scanHandler = Handler(scanHandlerThread.looper)
        backgroundStopReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.rootquotient.ble_operations.BACKGROUND_MODE_DISABLED") {
                    setBackgroundModeEnabled(false)
                    runOnMainThread {
                        methodChannel.invokeMethod("onBackgroundModeDisabled", null)
                    }
                }
            }
        }

        val filter = IntentFilter("com.rootquotient.ble_operations.BACKGROUND_MODE_DISABLED")
        context?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                it.registerReceiver(backgroundStopReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                it.registerReceiver(backgroundStopReceiver, filter)
            }
        } ?: Log.w(TAG, "Context is null, cannot register receiver")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopAdvertising()
        stopScanning()
        try {
            context?.unregisterReceiver(backgroundStopReceiver)
        } catch (e: Exception) {
            Log.w(TAG, "Receiver already unregistered or not registered", e)
        }
        scanHandlerThread.quitSafely()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        context = null
        activity = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun setBackgroundModeEnabled(enabled: Boolean) {
        backgroundModeEnabled = enabled
        val prefs = context?.getSharedPreferences("ble_prefs", Context.MODE_PRIVATE) ?: return
        prefs.edit().putBoolean("background_mode_enabled", enabled).apply()
    }

private fun requestBluetoothPermissions() {
    val permissions = mutableListOf<String>()

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        permissions.add(Manifest.permission.BLUETOOTH_SCAN)
        permissions.add(Manifest.permission.BLUETOOTH_ADVERTISE)
        permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
    } else {
        permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
        permissions.add(Manifest.permission.ACCESS_COARSE_LOCATION)
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        permissions.add(Manifest.permission.POST_NOTIFICATIONS)
    }

    val ctx = context ?: return
    val missing = permissions.filter {
        ActivityCompat.checkSelfPermission(ctx, it) != PackageManager.PERMISSION_GRANTED
    }
    if (missing.isNotEmpty()) {
        activity?.let {
            ActivityCompat.requestPermissions(it, missing.toTypedArray(), 1)
        } ?: Log.w(TAG, "No Activity attached — cannot request permissions")
    }
}


    private fun setupNotificationChannel() {
        notificationManager = context?.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "BLE Background Operations",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notifications for BLE scanning and advertising in background"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun runOnMainThread(action: () -> Unit) {
        val mainLooper = context?.mainLooper ?: return
        val mainHandler = Handler(mainLooper)
        mainHandler.post { action() }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.i(TAG, "BLE Advertising started successfully")
            isAdvertising = true
            runOnMainThread {
                methodChannel.invokeMethod("onAdvertisingStarted", mapOf("uuid" to (currentAdvertisingUUID ?: "")))
            }
        }
        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "BLE Advertising failed: $errorCode")
            isAdvertising = false
            runOnMainThread {
                methodChannel.invokeMethod("onAdvertisingError", mapOf("error" to "Failed with code: $errorCode"))
            }
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            scanHandler.post {
                val device = result.device
                val rssi = result.rssi
                val scanRecord = result.scanRecord

                val ctx = context
                val deviceName: String = if (
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    ctx != null &&
                    ActivityCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
                ) {
                    "Unknown Device"
                } else {
                    device.name ?: "Unknown Device"
                }
                val deviceAddress: String = if (
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    ctx != null &&
                    ActivityCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
                ) {
                    "00:00:00:00:00:00"
                } else {
                    device.address ?: "00:00:00:00:00:00"
                }

                val deviceInfo = mutableMapOf<String, Any>(
                    "id" to deviceAddress,
                    "name" to deviceName,
                    "rssi" to rssi,
                    "timestamp" to (System.currentTimeMillis() / 1000.0),
                    "isBeacon" to false
                )

                val serviceUuids = mutableListOf<String>()
                scanRecord?.serviceUuids?.forEach { parcelUuid ->
                    serviceUuids.add(parcelUuid.uuid.toString())
                }
                deviceInfo["serviceUUIDs"] = serviceUuids

                val manufacturerData = scanRecord?.manufacturerSpecificData
                if (manufacturerData != null && manufacturerData.size() > 0) {
                    val manufacturerId = manufacturerData.keyAt(0)
                    val data = manufacturerData.get(manufacturerId)
                    deviceInfo["manufacturerId"] = manufacturerId
                    if (data != null) {
                        deviceInfo["manufacturerHex"] = data.joinToString("") { "%02x".format(it) }
                        deviceInfo["manufacturerData"] = data.toList()
                    }
                }

                val previousInfo = scannedDevices[deviceAddress]
                if (previousInfo != null) {
                    val prevRssi = previousInfo["rssi"] as? Int
                    val prevManuHex = previousInfo["manufacturerHex"] as? String
                    val prevServiceUUIDs = previousInfo["serviceUUIDs"] as? List<*>

                    val isSame =
                        prevRssi == rssi &&
                        prevManuHex == deviceInfo["manufacturerHex"] &&
                        prevServiceUUIDs == serviceUuids
                    if (isSame) {
                        val updatedInfo = previousInfo.toMutableMap()
                        updatedInfo["timestamp"] = (System.currentTimeMillis() / 1000.0)
                        scannedDevices[deviceAddress] = updatedInfo
                        runOnMainThread {
                            Log.d(TAG, "Device timestamp updated: $updatedInfo")
                            eventSink?.success(updatedInfo)
                            try {
                                methodChannel.invokeMethod("onDeviceUpdated", updatedInfo)
                            } catch (e: Exception) {
                                Log.e(TAG, "Error invoking onDeviceUpdated: $e")
                            }
                        }
                        return@post
                    }
                }

                scannedDevices[deviceAddress] = deviceInfo
                runOnMainThread {
                    Log.d(TAG, "Sending NEW/CHANGED device to Flutter: $deviceInfo")
                    eventSink?.success(deviceInfo)
                    try {
                        methodChannel.invokeMethod("onDeviceDiscovered", deviceInfo)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error invoking onDeviceDiscovered: $e")
                    }
                }
                Log.i(TAG, "Device found: $deviceName ($deviceAddress) RSSI: $rssi")
            }
        }
        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "Scan failed: $errorCode")
            isScanning = false
            runOnMainThread {
                methodChannel.invokeMethod("onScanningStopped", null)
            }
        }
    }

    private fun startAdvertising(uuidStr: String) {
        if (backgroundModeEnabled) {
        val logMessage = "Background advertising is running. Stopping it before starting foreground advertising."
        Log.i(TAG, logMessage)
        runOnMainThread {
            methodChannel.invokeMethod("logMessage", mapOf("message" to logMessage))
        }
            disableBackgroundMode()
            runOnMainThread {
                methodChannel.invokeMethod("notifyUser", mapOf(
                    "message" to "Only one advertising mode can be active at a time. Switching to foreground advertising."
                ))
            }
        }
        if (bluetoothAdapter?.isEnabled != true) {
            Log.e(TAG, "Bluetooth not enabled")
            return
        }
        val ctx = context ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ActivityCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Missing BLUETOOTH_ADVERTISE permission")
            return
        }
    currentAdvertisingUUID = uuidStr 
    val settings = AdvertiseSettings.Builder()
        .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
        .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
        .setConnectable(false)
        .setTimeout(0)
        .build()
    try {
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(ParcelUuid(UUID.fromString(uuidStr)))
            .build()
        bluetoothAdapter?.bluetoothLeAdvertiser?.startAdvertising(settings, data, advertiseCallback)
        Log.i(TAG, "Starting advertising with UUID: $uuidStr")
    } catch (e: Exception) {
        Log.e(TAG, "Failed to start advertising with service UUID, trying manufacturer data", e)
        try {
            val manufacturerData = uuidStr.take(20).toByteArray()
            val fallbackData = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addManufacturerData(0x004C, manufacturerData)
                .build()
            bluetoothAdapter?.bluetoothLeAdvertiser?.startAdvertising(settings, fallbackData, advertiseCallback)
            Log.i(TAG, "Started advertising with manufacturer data fallback")
        } catch (e2: Exception) {
            Log.e(TAG, "All advertising methods failed", e2)
            isAdvertising = false
            currentAdvertisingUUID = null
            runOnMainThread {
                methodChannel.invokeMethod("onAdvertisingError", mapOf("error" to "Failed to start advertising: ${e2.message}"))
            }
        }
    }
}


        private fun stopAdvertising() {
            val ctx = context ?: run {
                Log.e(TAG, "Context is null, cannot stop advertising")
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                ActivityCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED
            ) {
                Log.e(TAG, "Missing BLUETOOTH_ADVERTISE permission")
                return
            }
            bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
            isAdvertising = false
            currentAdvertisingUUID = null
            Log.i(TAG, "Stopped advertising")
            runOnMainThread {
                methodChannel.invokeMethod("onAdvertisingStopped", null)
            }
        }


    private fun enableBackgroundMode(providedUuid: String?) {
        try {
            if (backgroundModeEnabled) {
                Log.i(TAG, "Background mode already enabled — skipping.")
                return
            }
            val uuidToUse = providedUuid
                ?: currentAdvertisingUUID
                ?: UUID.randomUUID().toString()
            if (isAdvertising) {
                stopAdvertising()
            }
            setBackgroundModeEnabled(true)
            val ctx = context ?: return
            val svcIntent = Intent(ctx, BluetoothForegroundService::class.java).apply {
                action = BluetoothForegroundService.ACTION_START
                putExtra(BluetoothForegroundService.EXTRA_UUID, uuidToUse)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(svcIntent)
            } else {
                ctx.startService(svcIntent)
            }
            val prefs = ctx.getSharedPreferences("ble_prefs", Context.MODE_PRIVATE)
            prefs.edit().putString("last_uuid", uuidToUse).apply()
            Log.i(TAG, "Background mode enabled — service started with UUID: $uuidToUse")
            runOnMainThread {
                methodChannel.invokeMethod("onBackgroundModeEnabled", mapOf("uuid" to uuidToUse))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error enabling background mode: $e")
            setBackgroundModeEnabled(false)
            runOnMainThread {
                methodChannel.invokeMethod("onBackgroundModeDisabled", null)
            }
        }
    }

    private fun disableBackgroundMode() {
        try {
            setBackgroundModeEnabled(false)
            val ctx = context ?: return
            val svcIntent = Intent(ctx, BluetoothForegroundService::class.java).apply {
                action = BluetoothForegroundService.ACTION_STOP
            }
            ctx.stopService(svcIntent)
            Log.i(TAG, "Background mode disabled - service stopped")
            runOnMainThread {
                methodChannel.invokeMethod("onBackgroundModeDisabled", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error disabling background mode: $e")
        }
    }

       private fun startScanning() {
        val ctx = context ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ActivityCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Missing BLUETOOTH_SCAN permission")
            return
        }
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
            .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
            .setReportDelay(0)
            .build()
        scannedDevices.clear()
        bluetoothAdapter?.bluetoothLeScanner?.startScan(null, settings, scanCallback)
        isScanning = true
        Log.i(TAG, "Started scanning - EventSink ready: ${eventSink != null}")
        runOnMainThread {
            methodChannel.invokeMethod("onScanningStarted", null)
        }
    }

    private fun stopScanning() {
        val ctx = context ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ActivityCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Missing BLUETOOTH_SCAN permission")
            return
        }
        bluetoothAdapter?.bluetoothLeScanner?.flushPendingScanResults(scanCallback)
        bluetoothAdapter?.bluetoothLeScanner?.stopScan(scanCallback)
        isScanning = false
        Log.i(TAG, "Stopped scanning")
        runOnMainThread {
            methodChannel.invokeMethod("onScanningStopped", null)
        }
    }
}
