package dark.onyx.com

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.ContactsContract
import android.telecom.Call
import android.telecom.InCallService
import android.util.Log
import android.view.KeyEvent
import androidx.core.app.NotificationCompat

class CallService : InCallService() {

    companion object {
        private const val TAG = "CallService"
        const val CHANNEL_INCOMING = "incoming_calls"
        const val CHANNEL_ONGOING = "ongoing_calls"
        const val NOTIFICATION_ID_INCOMING = 1001
        const val NOTIFICATION_ID_ONGOING = 1002

        var currentCall: Call? = null
        var listener: ((Call, Int) -> Unit)? = null
        var instance: CallService? = null
        var isCallUiOpen = false
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var isRinging = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannels()

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
        cancelAllNotifications()
        isCallUiOpen = false
        if (instance == this) instance = null
    }

    override fun onSilenceRinger() {
        super.onSilenceRinger()
        Log.d(TAG, "onSilenceRinger received from Android system")
        silenceRinger()
    }

    fun silenceRinger() {
        Log.d(TAG, "silenceRinger triggered")
        stopRinging()
    }

    private val callCallback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            super.onStateChanged(call, state)
            Log.d(TAG, "Call State Changed: $state")

            when (state) {
                Call.STATE_RINGING -> {
                    startRinging()
                    showIncomingCallNotification(call)
                }
                Call.STATE_DIALING, Call.STATE_CONNECTING -> {
                    stopRinging()
                    cancelNotification(NOTIFICATION_ID_INCOMING)
                    showOngoingCallNotification(call, "Calling...")
                }
                Call.STATE_ACTIVE -> {
                    stopRinging()
                    cancelNotification(NOTIFICATION_ID_INCOMING)
                    showOngoingCallNotification(call, "Ongoing Call")
                }
                Call.STATE_HOLDING -> {
                    stopRinging()
                    cancelNotification(NOTIFICATION_ID_INCOMING)
                    showOngoingCallNotification(call, "Call on Hold")
                }
                Call.STATE_DISCONNECTED, Call.STATE_DISCONNECTING -> {
                    stopRinging()
                    cancelAllNotifications()
                }
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

    fun startRinging() {
        if (isRinging) return
        isRinging = true

        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        Log.d(TAG, "Ringer mode: ${audioManager.ringerMode}")

        if (audioManager.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            try {
                val ringtoneUri = RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_RINGTONE)
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
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start ringtone: ${e.message}")
                mediaPlayer?.release()
                mediaPlayer = null
            }
        }

        if (audioManager.ringerMode != AudioManager.RINGER_MODE_SILENT) {
            try {
                val pattern = longArrayOf(0, 1000, 1000, 1000, 1000)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val effect = VibrationEffect.createWaveform(pattern, 0)
                    val attributes = android.os.VibrationAttributes.Builder()
                        .setUsage(android.os.VibrationAttributes.USAGE_RINGTONE)
                        .build()
                    vibrator?.vibrate(effect, attributes)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(pattern, 0)
                    val audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    vibrator?.vibrate(effect, audioAttributes)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(pattern, 0)
                }
                Log.d(TAG, "Vibration started successfully with USAGE_RINGTONE")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start vibration: ${e.message}")
            }
        }
    }

    fun stopRinging() {
        if (!isRinging) return
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop ringing: ${e.message}")
        }

        isRinging = false
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Incoming Calls Channel (High Priority Heads-Up)
            val incomingChannel = NotificationChannel(
                CHANNEL_INCOMING,
                "Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows heads-up notifications for incoming calls"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(incomingChannel)

            // Ongoing Calls Channel
            val ongoingChannel = NotificationChannel(
                CHANNEL_ONGOING,
                "Ongoing Calls",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows persistent notifications for active and outgoing calls"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(ongoingChannel)
        }
    }

    private fun getCallerNameOrNumber(call: Call?): Pair<String, String> {
        if (call == null) return Pair("Unknown", "Unknown")
        val number = call.details?.handle?.schemeSpecificPart ?: "Unknown"
        var contactName: String? = null

        // 1. FIRST Priority: Check saved local contacts via PhoneLookup
        if (number != "Unknown" && number.isNotEmpty()) {
            try {
                val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
                contentResolver.query(
                    uri,
                    arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                    null,
                    null,
                    null
                )?.use {
                    if (it.moveToFirst()) {
                        val found = it.getString(0)
                        if (!found.isNullOrBlank()) {
                            contactName = found
                        }
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "PhoneLookup error: ${e.message}")
            }

            // Fallback: If not found with exact formatted string, try normalized phone query
            if (contactName == null) {
                val cleanDigits = number.replace(Regex("[^0-9]"), "")
                if (cleanDigits.length >= 7) {
                    try {
                        val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(cleanDigits))
                        contentResolver.query(
                            uri,
                            arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                            null,
                            null,
                            null
                        )?.use {
                            if (it.moveToFirst()) {
                                val found = it.getString(0)
                                if (!found.isNullOrBlank()) {
                                    contactName = found
                                }
                            }
                        }
                    } catch (e: Exception) {}
                }
            }
        }

        // 2. SECOND Priority: If NOT in saved contacts, fallback to Telecom carrier/government SIM owner name
        if (contactName.isNullOrBlank()) {
            val contactDisplayName = call.details?.contactDisplayName
            val callerDisplayName = call.details?.callerDisplayName
            if (!contactDisplayName.isNullOrBlank()) {
                contactName = contactDisplayName
            } else if (!callerDisplayName.isNullOrBlank()) {
                contactName = callerDisplayName
            }
        }

        return Pair(contactName ?: number, number)
    }

    private fun showIncomingCallNotification(call: Call) {
        val (name, number) = getCallerNameOrNumber(call)
        val stateInt = call.state

        // Intent to launch MainActivity when user taps notification body
        // Uses REORDER_TO_FRONT + NEW_TASK for instant launch even on lock screen
        val contentIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
            putExtra("incoming_call", true)
            putExtra("incoming_number", number)
            putExtra("incoming_name", name)
            putExtra("incoming_state", stateInt)
        }

        val pendingContentIntent = PendingIntent.getActivity(
            this, 101, contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action: Answer (answers call and opens CallScreen)
        val answerIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_ANSWER
        }
        val pendingAnswerIntent = PendingIntent.getBroadcast(
            this, 102, answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action: Decline (hangs up call without opening app)
        val declineIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_DECLINE
        }
        val pendingDeclineIntent = PendingIntent.getBroadcast(
            this, 103, declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_INCOMING)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle(name)
            .setContentText(if (name != number) "Incoming Call • $number" else "Incoming Call")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingContentIntent)
            .setFullScreenIntent(pendingContentIntent, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", pendingDeclineIntent)
            .addAction(android.R.drawable.ic_menu_call, "Answer", pendingAnswerIntent)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID_INCOMING, notification)
    }

    private fun showOngoingCallNotification(call: Call, statusText: String) {
        val (name, number) = getCallerNameOrNumber(call)

        val contentIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
            putExtra("incoming_call", true)
            putExtra("incoming_number", number)
            putExtra("incoming_name", name)
            putExtra("incoming_state", call.state)
        }

        val pendingContentIntent = PendingIntent.getActivity(
            this, 201, contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action: Hang Up
        val hangupIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_HANGUP
        }
        val pendingHangupIntent = PendingIntent.getBroadcast(
            this, 202, hangupIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ONGOING)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle(name)
            .setContentText("$statusText • $number")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingContentIntent)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Hang Up", pendingHangupIntent)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID_ONGOING, notification)
    }

    fun cancelNotification(id: Int) {
        try {
            val manager = getSystemService(NotificationManager::class.java)
            manager.cancel(id)
        } catch (e: Exception) {
            Log.e(TAG, "Cancel notification error: ${e.message}")
        }
    }

    fun cancelAllNotifications() {
        try {
            val manager = getSystemService(NotificationManager::class.java)
            manager.cancel(NOTIFICATION_ID_INCOMING)
            manager.cancel(NOTIFICATION_ID_ONGOING)
        } catch (e: Exception) {
            Log.e(TAG, "Cancel all notifications error: ${e.message}")
        }
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        Log.d(TAG, "Call Added: state=${call.state}")
        currentCall = call
        call.registerCallback(callCallback)

        when (call.state) {
            Call.STATE_RINGING -> {
                startRinging()
                showIncomingCallNotification(call)

                // Direct Activity Launch: If the app UI is not already open,
                // immediately launch the call screen (like system dialers do).
                // This wakes the device, shows over lock screen, and bypasses cold-start delays.
                if (!MainActivity.isAppVisible) {
                    val (name, number) = getCallerNameOrNumber(call)
                    val launchIntent = Intent(this, MainActivity::class.java).apply {
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                        )
                        putExtra("incoming_call", true)
                        putExtra("incoming_number", number)
                        putExtra("incoming_name", name)
                        putExtra("incoming_state", call.state)
                    }
                    startActivity(launchIntent)
                }
            }
            Call.STATE_DIALING, Call.STATE_CONNECTING -> {
                showOngoingCallNotification(call, "Calling...")
            }
            Call.STATE_ACTIVE -> {
                showOngoingCallNotification(call, "Ongoing Call")
            }
            else -> {
                showOngoingCallNotification(call, "In Call")
            }
        }

        listener?.invoke(call, call.state)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        Log.d(TAG, "Call Removed: ${call.details?.handle?.schemeSpecificPart}")
        stopRinging()
        cancelAllNotifications()

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

        if (currentCall == null) {
            isCallUiOpen = false
        }
    }
}
