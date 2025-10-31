package com.rootquotient.ble_operations
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class AppRestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i("AppRestartReceiver", "Received broadcast: ${intent.action}")
        val prefs = context.getSharedPreferences("ble_prefs", Context.MODE_PRIVATE)
        val lastUuid = prefs.getString("last_uuid", null)
        val wasBackgroundEnabled = prefs.getBoolean("background_mode_enabled", false)
        if (lastUuid.isNullOrEmpty() || !wasBackgroundEnabled) {
            Log.w("AppRestartReceiver", "Background advertising not enabled before reboot. Skipping restart.")
            return
        }
        val serviceIntent = Intent(context, BluetoothForegroundService::class.java).apply {
            action = BluetoothForegroundService.ACTION_START
            putExtra(BluetoothForegroundService.EXTRA_UUID, lastUuid)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
        Log.i("AppRestartReceiver", "Restarted BLE advertising with UUID: $lastUuid")
        val intentEnabled = Intent("com.rootquotient.ble_operations.BACKGROUND_MODE_ENABLED")
        context.sendBroadcast(intentEnabled)
    }
}
