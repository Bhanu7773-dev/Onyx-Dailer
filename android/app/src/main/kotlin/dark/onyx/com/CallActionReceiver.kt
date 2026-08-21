package dark.onyx.com

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telecom.Call
import android.telecom.VideoProfile
import android.util.Log

class CallActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_ANSWER = "dark.onyx.com.ACTION_ANSWER"
        const val ACTION_DECLINE = "dark.onyx.com.ACTION_DECLINE"
        const val ACTION_HANGUP = "dark.onyx.com.ACTION_HANGUP"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d("CallActionReceiver", "onReceive action: $action")

        val currentCall = CallService.currentCall

        when (action) {
            ACTION_ANSWER -> {
                try {
                    currentCall?.answer(VideoProfile.STATE_AUDIO_ONLY)
                } catch (e: Exception) {
                    Log.e("CallActionReceiver", "Failed to answer call: ${e.message}")
                }
                CallService.instance?.stopRinging()

                // Bring MainActivity to the front instantly (even on lock screen)
                val number = currentCall?.details?.handle?.schemeSpecificPart ?: ""
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    )
                    putExtra("incoming_call", true)
                    putExtra("incoming_number", number)
                    putExtra("incoming_state", currentCall?.state ?: Call.STATE_ACTIVE)
                }
                context.startActivity(launchIntent)
            }
            ACTION_DECLINE -> {
                try {
                    currentCall?.reject(false, null)
                } catch (e: Exception) {
                    try {
                        currentCall?.disconnect()
                    } catch (e2: Exception) {}
                }
                CallService.instance?.stopRinging()
                CallService.instance?.cancelAllNotifications()
            }
            ACTION_HANGUP -> {
                try {
                    currentCall?.disconnect()
                } catch (e: Exception) {
                    Log.e("CallActionReceiver", "Failed to hang up: ${e.message}")
                }
                CallService.instance?.cancelAllNotifications()
            }
        }
    }
}
