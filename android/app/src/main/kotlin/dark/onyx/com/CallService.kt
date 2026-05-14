package dark.onyx.com

import android.telecom.Call
import android.telecom.InCallService
import android.util.Log

class CallService : InCallService() {

    companion object {
        private const val TAG = "CallService"
        var currentCall: Call? = null
        var listener: ((Call, Int) -> Unit)? = null
        var instance: CallService? = null
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    private val callCallback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            super.onStateChanged(call, state)
            Log.d(TAG, "Call State Changed: $state")
            listener?.invoke(call, state)
        }
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        Log.d(TAG, "Call Added: ${call.state}")
        currentCall = call
        call.registerCallback(callCallback)
        listener?.invoke(call, call.state)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        Log.d(TAG, "Call Removed")
        call.unregisterCallback(callCallback)
        if (currentCall == call) {
            currentCall = null
        }
        listener?.invoke(call, Call.STATE_DISCONNECTED)
    }
}
