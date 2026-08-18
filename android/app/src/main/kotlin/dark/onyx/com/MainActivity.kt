package dark.onyx.com

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import android.content.ServiceConnection
import android.os.IBinder
import android.content.ComponentName
import dark.onyx.com.BuildConfig

class MainActivity: FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "dark.onyx.com/telecom_commands"
        private const val EVENT_CHANNEL = "dark.onyx.com/telecom_events"
        var isAppVisible = false
    }
    private var eventSink: EventChannel.EventSink? = null
    private var toneGenerator: ToneGenerator? = null
    private var callRecorderService: ICallRecorderService? = null
    private var pendingRecordingPath: String? = null

    private val serviceArgs by lazy {
        Shizuku.UserServiceArgs(ComponentName(packageName, CallRecorderService::class.java.name))
            .daemon(false)
            .processNameSuffix("recorder")
            .debuggable(BuildConfig.DEBUG)
            .version(1)
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            callRecorderService = ICallRecorderService.Stub.asInterface(service)
            android.util.Log.d("OnyxMainActivity", "Shizuku Service Connected")
            pendingRecordingPath?.let {
                try {
                    callRecorderService?.startRecording(it)
                    pendingRecordingPath = null
                } catch (e: Exception) {
                    android.util.Log.e("OnyxMainActivity", "Failed to start pending recording: ${e.message}")
                }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            callRecorderService = null
            android.util.Log.d("OnyxMainActivity", "Shizuku Service Disconnected")
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("incoming_call", false)) {
            turnScreenOnAndKeyguardOff()
        }
    }

    private fun turnScreenOnAndKeyguardOff() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(android.content.Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        if (intent.getBooleanExtra("incoming_call", false)) {
            turnScreenOnAndKeyguardOff()
        }

        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.navigationBarColor = 0x00000000 
        window.statusBarColor = 0x00000000 
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }

    override fun onStart() {
        super.onStart()
        isAppVisible = true
    }

    override fun onResume() {
        super.onResume()
        isAppVisible = true
    }

    override fun onPause() {
        super.onPause()
        isAppVisible = false
    }

    override fun onStop() {
        super.onStop()
        isAppVisible = false
    }

    private fun resolveContactName(number: String): String? {
        if (number == "Unknown") return null
        try {
            val uri = android.net.Uri.withAppendedPath(android.provider.ContactsContract.PhoneLookup.CONTENT_FILTER_URI, android.net.Uri.encode(number))
            val cursor = contentResolver.query(uri, arrayOf(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME)
                if (index != -1) {
                    val name = cursor.getString(index)
                    cursor.close()
                    return name
                }
                cursor.close()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_DTMF, 80)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestDefaultDialer" -> {
                    requestDefaultDialer()
                    result.success(null)
                }
                "getSimCards" -> {
                    val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                    if (checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        val accounts = telecomManager.callCapablePhoneAccounts
                        val sims = accounts.mapIndexed { index, handle ->
                            val account = telecomManager.getPhoneAccount(handle)
                            mapOf(
                                "id" to handle.id,
                                "label" to (account?.label?.toString() ?: "SIM ${index + 1}")
                            )
                        }
                        result.success(sims)
                    } else {
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                "makeCall" -> {
                    val number = call.argument<String>("number")
                    val simId = call.argument<String>("simId")
                    if (number != null) {
                        makeCall(number, simId)
                    }
                    result.success(null)
                }
                "answerCall" -> {
                    CallService.currentCall?.answer(VideoProfile.STATE_AUDIO_ONLY)
                    result.success(null)
                }
                "playDtmf" -> {
                    val digit = call.argument<String>("digit")?.firstOrNull()
                    if (digit != null) {
                        CallService.currentCall?.playDtmfTone(digit)
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            CallService.currentCall?.stopDtmfTone()
                        }, 200)
                    }
                    result.success(null)
                }
                "setSpeaker" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        CallService.instance?.setAudioRoute(CallAudioState.ROUTE_SPEAKER)
                    } else {
                        CallService.instance?.setAudioRoute(CallAudioState.ROUTE_EARPIECE)
                    }
                    result.success(null)
                }
                "setMuted" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    CallService.instance?.setMuted(enabled)
                    result.success(null)
                }
                "setHold" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    CallService.currentCall?.let {
                        if (enabled && it.state == Call.STATE_ACTIVE) {
                            it.hold()
                        } else if (!enabled && it.state == Call.STATE_HOLDING) {
                            it.unhold()
                        }
                    }
                    result.success(null)
                }
                "playLocalDtmf" -> {
                    val digit = call.argument<String>("digit")?.firstOrNull()
                    if (digit != null && toneGenerator != null) {
                        val toneType = when (digit) {
                            '0' -> ToneGenerator.TONE_DTMF_0
                            '1' -> ToneGenerator.TONE_DTMF_1
                            '2' -> ToneGenerator.TONE_DTMF_2
                            '3' -> ToneGenerator.TONE_DTMF_3
                            '4' -> ToneGenerator.TONE_DTMF_4
                            '5' -> ToneGenerator.TONE_DTMF_5
                            '6' -> ToneGenerator.TONE_DTMF_6
                            '7' -> ToneGenerator.TONE_DTMF_7
                            '8' -> ToneGenerator.TONE_DTMF_8
                            '9' -> ToneGenerator.TONE_DTMF_9
                            '*' -> ToneGenerator.TONE_DTMF_S
                            '#' -> ToneGenerator.TONE_DTMF_P
                            else -> -1
                        }
                        if (toneType != -1) {
                            toneGenerator?.startTone(toneType, 150)
                        }
                    }
                    result.success(null)
                }
                "endCall" -> {
                    val service = CallService.instance
                    val calls = service?.calls ?: emptyList()
                    if (calls.isNotEmpty()) {
                        calls.forEach { call ->
                            try {
                                if (call.state == Call.STATE_RINGING) {
                                    call.reject(false, null)
                                } else if (call.state != Call.STATE_DISCONNECTED && call.state != Call.STATE_DISCONNECTING) {
                                    call.disconnect()
                                }
                            } catch (e: Exception) {
                                android.util.Log.e("OnyxMainActivity", "Error ending call: ${e.message}")
                            }
                        }
                    } else {
                        CallService.currentCall?.let {
                            if (it.state == Call.STATE_RINGING) {
                                it.reject(false, null)
                            } else {
                                it.disconnect()
                            }
                        }
                    }
                    result.success(null)
                }
                "mergeCall" -> {
                    try {
                        val service = CallService.instance
                        val calls = service?.calls ?: emptyList()
                        val activeCalls = calls.filter { 
                            it.state != Call.STATE_DISCONNECTED && it.state != Call.STATE_DISCONNECTING 
                        }
                        if (activeCalls.size >= 2) {
                            val activeCall = activeCalls.firstOrNull { it.state == Call.STATE_ACTIVE } ?: activeCalls.firstOrNull()
                            val otherCall = activeCalls.firstOrNull { it != activeCall }
                            if (activeCall != null && otherCall != null) {
                                activeCall.conference(otherCall)
                            }
                        }
                        // Unhold any held calls after merge so the user and all participants can hear and talk
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            val updatedCalls = service?.calls ?: emptyList()
                            updatedCalls.forEach { c ->
                                if (c.state == Call.STATE_HOLDING) {
                                    try { c.unhold() } catch (e: Exception) {}
                                }
                            }
                            service?.setMuted(false)
                        }, 500)
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("OnyxMainActivity", "mergeCall failed: ${e.message}")
                        result.success(false)
                    }
                }
                "swapCall" -> {
                    try {
                        val service = CallService.instance
                        val calls = service?.calls ?: emptyList()
                        val heldCall = calls.firstOrNull { it.state == Call.STATE_HOLDING }
                        val activeCall = calls.firstOrNull { it.state == Call.STATE_ACTIVE }
                        if (heldCall != null && activeCall != null) {
                            activeCall.hold()
                            heldCall.unhold()
                        } else if (heldCall != null) {
                            heldCall.unhold()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("OnyxMainActivity", "swapCall failed: ${e.message}")
                        result.success(false)
                    }
                }
                "getCallInfo" -> {
                    val service = CallService.instance
                    val calls = service?.calls ?: emptyList()
                    val activeCalls = calls.filter { 
                        it.state != Call.STATE_DISCONNECTED && it.state != Call.STATE_DISCONNECTING 
                    }
                    val hasConference = activeCalls.any { 
                        it.details?.hasProperty(Call.Details.PROPERTY_CONFERENCE) == true || it.children.isNotEmpty()
                    }
                    val unmergedCount = if (hasConference) 1 else activeCalls.count { it.parent == null }
                    val isHolding = activeCalls.any { it.state == Call.STATE_HOLDING }

                    result.success(mapOf(
                        "count" to unmergedCount,
                        "isConference" to hasConference,
                        "isHolding" to isHolding
                    ))
                }
                "getCallCount" -> {
                    val service = CallService.instance
                    val count = service?.calls?.count { 
                        it.state != Call.STATE_DISCONNECTED && it.state != Call.STATE_DISCONNECTING 
                    } ?: 0
                    result.success(count)
                }
                "prepareShizukuService" -> {
                    try {
                        if (callRecorderService == null) {
                            android.util.Log.d("OnyxMainActivity", "Prewarm: Initiating Shizuku service bind")
                            Shizuku.bindUserService(serviceArgs, serviceConnection)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("OnyxMainActivity", "prepareShizukuService failed: ${e.message}")
                        result.success(false)
                    }
                }
                "startShizukuRecording" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            if (callRecorderService == null) {
                                pendingRecordingPath = filePath
                                android.util.Log.w("OnyxMainActivity", "Service not ready; binding and queueing: $filePath")
                                Shizuku.bindUserService(serviceArgs, serviceConnection)
                            } else {
                                callRecorderService?.startRecording(filePath)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("OnyxMainActivity", "startShizukuRecording failed: ${e.message}")
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "stopShizukuRecording" -> {
                    try {
                        callRecorderService?.stopRecording()
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("OnyxMainActivity", "stopShizukuRecording failed: ${e.message}")
                        result.success(false)
                    }
                }
                "isIncomingCallLaunch" -> {
                    val isIncoming = intent.getBooleanExtra("incoming_call", false)
                    intent.removeExtra("incoming_call") // Clear the extra so it doesn't trigger again on normal manual opens
                    if (isIncoming) {
                        val number = intent.getStringExtra("incoming_number") ?: "Unknown"
                        val state = intent.getIntExtra("incoming_state", 2)
                        
                        // Fast native contact lookup
                        val contactName = resolveContactName(number)
                        
                        val map = mapOf(
                            "isIncoming" to true,
                            "number" to number,
                            "state" to state,
                            "name" to contactName
                        )
                        result.success(map)
                    } else {
                        result.success(mapOf("isIncoming" to false))
                    }
                }
                "isShizukuServiceRunning" -> {
                    result.success(callRecorderService != null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    CallService.listener = { call, state ->
                        runOnUiThread {
                            val num = call.details.handle?.schemeSpecificPart ?: "Unknown"
                            val data = mapOf(
                                "state" to state,
                                "number" to num,
                                "name" to resolveContactName(num)
                            )
                            eventSink?.success(data)
                        }
                    }
                    CallService.currentCall?.let {
                        val num = it.details.handle?.schemeSpecificPart ?: "Unknown"
                        val data = mapOf(
                            "state" to it.state,
                            "number" to num,
                            "name" to resolveContactName(num)
                        )
                        eventSink?.success(data)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    CallService.listener = null
                }
            }
        )
    }

    private fun requestDefaultDialer() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (!roleManager.isRoleHeld(RoleManager.ROLE_DIALER)) {
                val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                startActivityForResult(intent, 1)
            }
        } else {
            val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
            intent.putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, packageName)
            startActivity(intent)
        }
    }

    private fun makeCall(number: String, simId: String?) {
        val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val uri = Uri.fromParts("tel", number, null)
        val extras = Bundle()
        
        try {
            // Check for permissions
            if (checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                var selectedAccount: android.telecom.PhoneAccountHandle? = null
                
                // If a specific sim is requested
                if (simId != null) {
                    val accounts = telecomManager.callCapablePhoneAccounts
                    selectedAccount = accounts.find { it.id == simId }
                }
                
                // If we have a selected account, use it
                if (selectedAccount != null) {
                    extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, selectedAccount)
                }
                // If simId is null or not found, do NOT put any EXTRA_PHONE_ACCOUNT_HANDLE
                // This forces Android to show the "Select SIM" popup (Ask Every Time)
                // UNLESS there is only one SIM
                else if (telecomManager.callCapablePhoneAccounts.size == 1) {
                    extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, telecomManager.callCapablePhoneAccounts[0])
                }
            }
            
            telecomManager.placeCall(uri, extras)
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        toneGenerator?.release()
        toneGenerator = null
        super.onDestroy()
    }
}
