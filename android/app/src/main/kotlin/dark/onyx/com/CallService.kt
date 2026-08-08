package dark.onyx.com

import android.telecom.Call
import android.telecom.InCallService
import android.util.Log
import android.content.Intent

class CallService : InCallService() {

    companion object {
        private const val TAG = "CallService"
        var currentCall: Call? = null
        var listener: ((Call, Int) -> Unit)? = null
        var instance: CallService? = null
        
        // Protection flag to prevent repeated activity launches
        var isCallUiOpen = false
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onDestroy() {
        super.onDestroy()
        isCallUiOpen = false
    }

    private val callCallback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            super.onStateChanged(call, state)
            Log.d(TAG, "Call State Changed: $state")
            listener?.invoke(call, state)
        }
    }

    private fun createNotificationChannel() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                "incoming_calls",
                "Incoming Calls",
                android.app.NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows incoming call notifications"
                setSound(null, null)
                enableVibration(false)
            }
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        Log.d(TAG, "Call Added: ${call.state}")
        currentCall = call
        call.registerCallback(callCallback)
        
        if (call.state == Call.STATE_RINGING) {
            showIncomingCallNotification()
        }
        
        listener?.invoke(call, call.state)
    }

    private fun showIncomingCallNotification() {
        val numberString = currentCall?.details?.handle?.schemeSpecificPart ?: "Unknown"
        val stateInt = currentCall?.state ?: 2

        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                     Intent.FLAG_ACTIVITY_SINGLE_TOP or
                     Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("incoming_call", true)
            putExtra("incoming_number", numberString)
            putExtra("incoming_state", stateInt)
        }
        
        val pendingIntent = android.app.PendingIntent.getActivity(
            this, System.currentTimeMillis().toInt(), intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val notification = androidx.core.app.NotificationCompat.Builder(this, "incoming_calls")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("Incoming Call")
            .setContentText("Tap to answer")
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
            .setCategory(androidx.core.app.NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(android.app.NotificationManager::class.java)
        manager.notify(1001, notification)
        
        // Use singleton protection to avoid repeated launches
        if (!isCallUiOpen && !MainActivity.isAppVisible) {
            try {
                isCallUiOpen = true
                startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start activity directly: ${e.message}")
            }
        }
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        Log.d(TAG, "Call Removed")
        val manager = getSystemService(android.app.NotificationManager::class.java)
        manager.cancel(1001)
        
        call.unregisterCallback(callCallback)
        if (currentCall == call) {
            currentCall = null
        }
        listener?.invoke(call, Call.STATE_DISCONNECTED)
        
        // Reset flag if no active calls remain
        if (currentCall == null) {
            isCallUiOpen = false
        }
    }
}
