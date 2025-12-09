package com.rootquotient.ble_operations
import android.Manifest
import android.app.*
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.ParcelUuid
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import java.util.*

class BluetoothForegroundService : Service() {
    private val TAG = "BluetoothFgService"
    private val NOTIFICATION_CHANNEL_ID = "BLE_FOREGROUND_CHANNEL"
    private val NOTIFICATION_ID = 2001
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var isAdvertising = false
    private lateinit var notificationManager: NotificationManager
    
    companion object {
        const val ACTION_START = "com.rootquotient.ble_operations.action.START"
        const val ACTION_STOP = "com.rootquotient.ble_operations.action.STOP"
        const val EXTRA_UUID = "extra_uuid"
    }
    override fun onCreate() {
        super.onCreate()
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as android.bluetooth.BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "BLE Foreground",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "BLE advertising running in background"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

private fun buildNotification(contentText: String): Notification {
    val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)
    val openPending = if (openAppIntent != null) {
        PendingIntent.getActivity(
            this, 0, openAppIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            else PendingIntent.FLAG_UPDATE_CURRENT
        )
    } else null
    val stopIntent = Intent(this, BluetoothForegroundService::class.java).apply {
        action = ACTION_STOP
    }
    val stopPendingIntent = PendingIntent.getService(
        this, 1, stopIntent,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        else PendingIntent.FLAG_UPDATE_CURRENT
    )
    val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
        .setContentTitle("BLE Background Advertising")
        .setContentText(contentText)
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setOngoing(true)
        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        .setAutoCancel(false)
        .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
    openPending?.let { builder.setContentIntent(it) }
    val notification = builder.build()
    notification.flags = notification.flags or Notification.FLAG_ONGOING_EVENT or Notification.FLAG_NO_CLEAR
    return notification
}

    private fun startAdvertising(uuidStr: String?) {
        if (bluetoothAdapter?.isEnabled != true) {
            Log.e(TAG, "Bluetooth not enabled. Cannot advertise.")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Missing BLUETOOTH_ADVERTISE permission")
            return
        }
        val advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        if (advertiser == null) {
            Log.e(TAG, "Device doesn't support BLE advertising")
            return
        }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(false)
            .setTimeout(0)
            .build()
        val dataBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
        if (!uuidStr.isNullOrEmpty()) {
            try {
                dataBuilder.addServiceUuid(ParcelUuid(UUID.fromString(uuidStr)))
            } catch (e: Exception) {
                val mData = uuidStr.take(20).toByteArray()
                dataBuilder.addManufacturerData(0x004C, mData)
            }
        } else {
            dataBuilder.addManufacturerData(0x0059, "BLE_TEST".toByteArray())
        }
        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                super.onStartSuccess(settingsInEffect)
                isAdvertising = true
                Log.i(TAG, "ForegroundService: Advertising started")
                val notif = buildNotification("BLE advertising active")
                val prefs = getSharedPreferences("ble_prefs", Context.MODE_PRIVATE)
                prefs.edit().putString("last_uuid", uuidStr).apply()
                notificationManager.notify(NOTIFICATION_ID, notif)
            }
            override fun onStartFailure(errorCode: Int) {
                super.onStartFailure(errorCode)
                isAdvertising = false
                Log.e(TAG, "ForegroundService: Advertising failed: $errorCode")
                notificationManager.cancel(NOTIFICATION_ID)
                stopForeground(true)
                stopSelf()
            }
        }
        try {
            advertiser.startAdvertising(settings, dataBuilder.build(), advertiseCallback)
            Log.i(TAG, "ForegroundService: request to start advertising sent")
        } catch (e: Exception) {
            Log.e(TAG, "ForegroundService: startAdvertising threw", e)
            notificationManager.cancel(NOTIFICATION_ID)
            stopForeground(true)
            stopSelf()
        }
    }

private fun stopAdvertising() {
    try {
        val advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        if (advertiser != null && advertiseCallback != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED
            ) {
                Log.e(TAG, "Missing BLUETOOTH_ADVERTISE permission, cannot stop advertising")
                return
            }
            advertiser.stopAdvertising(advertiseCallback)
        }
    } catch (e: Exception) {
        Log.e(TAG, "ForegroundService: stopAdvertising error", e)
    } finally {
        advertiseCallback = null
        isAdvertising = false
        notificationManager.cancel(NOTIFICATION_ID)
    }
}


override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val action = intent?.action
    val uuid = intent?.getStringExtra(EXTRA_UUID)
    when (action) {
    ACTION_START -> {
        val initialNotification = buildNotification("Preparing BLE advertising...")
        startForeground(NOTIFICATION_ID, initialNotification)
        if (!isAdvertising) {
            startAdvertising(uuid)
            val prefs = getSharedPreferences("ble_prefs", Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean("background_mode_enabled", true)
                .apply()
            val intentEnabled = Intent("com.rootquotient.ble_operations.BACKGROUND_MODE_ENABLED")
            intentEnabled.setPackage(packageName)
            sendBroadcast(intentEnabled)
        }
        return START_REDELIVER_INTENT
    }
        ACTION_STOP -> {
            stopAdvertising()
            stopForeground(true)
            stopSelf()
            val prefs = getSharedPreferences("ble_prefs", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("background_mode_enabled", false).apply()
            val intentDisabled = Intent("com.rootquotient.ble_operations.BACKGROUND_MODE_DISABLED")
            intentDisabled.setPackage(packageName)
            sendBroadcast(intentDisabled)
            return START_NOT_STICKY
        }
        else -> {
            val initialNotification = buildNotification("Preparing BLE advertising...")
            startForeground(NOTIFICATION_ID, initialNotification)
            startAdvertising(uuid)
            return START_STICKY
        }
    }
}

    override fun onDestroy() {
        stopAdvertising()
        stopForeground(true)
        val intentDisabled = Intent("com.rootquotient.ble_operations.BACKGROUND_MODE_DISABLED")
        intentDisabled.setPackage(packageName)
        sendBroadcast(intentDisabled)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
