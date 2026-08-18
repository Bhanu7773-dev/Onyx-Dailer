package dark.onyx.com

import android.telecom.Call
import android.telecom.InCallService
import android.util.Log
import android.content.Intent
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

class CallService : InCallService() {

    companion object {
        private const val TAG = "CallService"
        var currentCall: Call? = null
        var listener: ((Call, Int) -> Unit)? = null
        var instance: CallService? = null
        
        // Protection flag to prevent repeated activity launches
        var isCallUiOpen = false
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var isRinging = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(VibratorManager::class.java)
            vm?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRinging()
        isCallUiOpen = false
    }

    private val callCallback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            super.onStateChanged(call, state)
            Log.d(TAG, "Call State Changed: $state")

            // Stop ringing when call is answered, disconnected, or no longer ringing
            if (state != Call.STATE_RINGING) {
                stopRinging()
            }

            if (state == Call.STATE_DISCONNECTED) {
                val hasOtherActiveCalls = calls.any {
                    it != call && it.state != Call.STATE_DISCONNECTED && it.state != Call.STATE_DISCONNECTING
                }
                if (hasOtherActiveCalls) {
                    Log.d(TAG, "Ignoring transient disconnected callback; another call is still active")
                    return
                }
            }

            listener?.invoke(call, state)
        }
    }

    private fun startRinging() {
        if (isRinging) return
        isRinging = true

        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        Log.d(TAG, "Ringer mode: ${audioManager.ringerMode}, Ring volume: ${audioManager.getStreamVolume(AudioManager.STREAM_RING)}")

        // Play ringtone using MediaPlayer (more reliable than Ringtone API)
        if (audioManager.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            try {
                val ringtoneUri = RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_RINGTONE)
                Log.d(TAG, "Ringtone URI: $ringtoneUri")
                
                if (ringtoneUri != null) {
                    mediaPlayer = MediaPlayer().apply {
                        setDataSource(this@CallService, ringtoneUri)
                        setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .setLegacyStreamType(AudioManager.STREAM_RING)
                                .build()
                        )
                        isLooping = true
                        prepare()
                        start()
                    }
                    Log.d(TAG, "MediaPlayer ringtone started successfully")
                } else {
                    Log.w(TAG, "No default ringtone URI found")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start ringtone: ${e.message}", e)
                mediaPlayer?.release()
                mediaPlayer = null
            }
        }

        // Vibrate in normal and vibrate modes (not silent)
        if (audioManager.ringerMode != AudioManager.RINGER_MODE_SILENT) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val pattern = longArrayOf(0, 800, 600, 800, 600)
                    vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(longArrayOf(0, 800, 600, 800, 600), 0)
                }
                Log.d(TAG, "Vibration started")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start vibration: ${e.message}")
            }
        }
    }

    private fun stopRinging() {
        if (!isRinging) return
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
            vibrator?.cancel()
            Log.d(TAG, "Ringtone and vibration stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop ringing: ${e.message}")
        }
        isRinging = false
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
            startRinging()
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
        stopRinging()

        val manager = getSystemService(android.app.NotificationManager::class.java)
        manager.cancel(1001)
        
        call.unregisterCallback(callCallback)
        if (currentCall == call) {
            currentCall = null
        }

        val nextCall = calls.firstOrNull { it.state != Call.STATE_DISCONNECTED && it.state != Call.STATE_DISCONNECTING }
        if (nextCall != null) {
            currentCall = nextCall
            listener?.invoke(nextCall, nextCall.state)
        } else {
            listener?.invoke(call, Call.STATE_DISCONNECTED)
        }
        
        // Reset flag if no active calls remain
        if (currentCall == null) {
            isCallUiOpen = false
        }
    }
}
