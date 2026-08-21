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
        private const val REQUEST_PICK_IMAGE = 1001
        var isAppVisible = false
    }
    private var pendingImageResult: MethodChannel.Result? = null
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
            val call = CallService.currentCall
            if (call != null) {
                val num = call.details?.handle?.schemeSpecificPart ?: intent.getStringExtra("incoming_number") ?: "Unknown"
                val connectTime = call.details?.connectTimeMillis ?: 0L
                val elapsedSeconds = if (connectTime > 0L && call.state == Call.STATE_ACTIVE) {
                    Math.max(0, ((System.currentTimeMillis() - connectTime) / 1000).toInt())
                } else 0
                val data = mapOf(
                    "state" to call.state,
                    "number" to num,
                    "name" to resolveContactName(num),
                    "connectTime" to connectTime,
                    "elapsedSeconds" to elapsedSeconds
                )
                runOnUiThread {
                    eventSink?.success(data)
                }
            }
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

    override fun onKeyDown(keyCode: Int, event: android.view.KeyEvent?): Boolean {
        if (keyCode == android.view.KeyEvent.KEYCODE_VOLUME_DOWN ||
            keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP ||
            keyCode == android.view.KeyEvent.KEYCODE_VOLUME_MUTE) {
            if (CallService.currentCall?.state == Call.STATE_RINGING) {
                CallService.instance?.silenceRinger()
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_IMAGE) {
            if (resultCode == RESULT_OK && data?.data != null) {
                try {
                    val bytes = contentResolver.openInputStream(data.data!!)?.use { it.readBytes() }
                    pendingImageResult?.success(bytes)
                } catch (e: Exception) {
                    android.util.Log.e("OnyxMainActivity", "Failed to read image bytes: ${e.message}")
                    pendingImageResult?.success(null)
                }
            } else {
                pendingImageResult?.success(null)
            }
            pendingImageResult = null
        }
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
                    val call = CallService.currentCall
                    val isIncoming = intent.getBooleanExtra("incoming_call", false) || (call != null && (call.state == Call.STATE_RINGING || call.state == Call.STATE_ACTIVE || call.state == Call.STATE_DIALING || call.state == Call.STATE_CONNECTING))
                    intent.removeExtra("incoming_call") // Clear the extra so it doesn't trigger again on normal manual opens
                    if (isIncoming) {
                        val number = intent.getStringExtra("incoming_number") ?: call?.details?.handle?.schemeSpecificPart ?: "Unknown"
                        val state = if (intent.hasExtra("incoming_state")) intent.getIntExtra("incoming_state", 2) else (call?.state ?: 2)
                        val contactName = intent.getStringExtra("incoming_name") ?: resolveContactName(number)
                        val connectTime = call?.details?.connectTimeMillis ?: 0L
                        val elapsedSeconds = if (connectTime > 0L && state == Call.STATE_ACTIVE) {
                            Math.max(0, ((System.currentTimeMillis() - connectTime) / 1000).toInt())
                        } else 0
                        
                        val map = mapOf(
                            "isIncoming" to true,
                            "number" to number,
                            "state" to state,
                            "name" to contactName,
                            "connectTime" to connectTime,
                            "elapsedSeconds" to elapsedSeconds
                        )
                        result.success(map)
                    } else {
                        result.success(mapOf("isIncoming" to false))
                    }
                }
                "getUserProfileAvatar" -> {
                    val avatarBytes = getUserProfilePhoto()
                    result.success(avatarBytes)
                }
                "pickGalleryImage" -> {
                    pendingImageResult = result
                    try {
                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            type = "image/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                        }
                        startActivityForResult(Intent.createChooser(intent, "Select Profile Picture"), REQUEST_PICK_IMAGE)
                    } catch (e: Exception) {
                        android.util.Log.e("OnyxMainActivity", "Launch gallery error: ${e.message}")
                        pendingImageResult?.success(null)
                        pendingImageResult = null
                    }
                }
                "handleSecretCode" -> {
                    val code = call.argument<String>("code") ?: ""
                    val resultData = handleSecretCode(code)
                    result.success(resultData)
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
                            val connectTime = call.details?.connectTimeMillis ?: 0L
                            val elapsedSeconds = if (connectTime > 0L && state == Call.STATE_ACTIVE) {
                                Math.max(0, ((System.currentTimeMillis() - connectTime) / 1000).toInt())
                            } else 0
                            val data = mapOf(
                                "state" to state,
                                "number" to num,
                                "name" to resolveContactName(num),
                                "connectTime" to connectTime,
                                "elapsedSeconds" to elapsedSeconds
                            )
                            eventSink?.success(data)
                        }
                    }
                    CallService.currentCall?.let {
                        val num = it.details.handle?.schemeSpecificPart ?: "Unknown"
                        val connectTime = it.details?.connectTimeMillis ?: 0L
                        val elapsedSeconds = if (connectTime > 0L && it.state == Call.STATE_ACTIVE) {
                            Math.max(0, ((System.currentTimeMillis() - connectTime) / 1000).toInt())
                        } else 0
                        val data = mapOf(
                            "state" to it.state,
                            "number" to num,
                            "name" to resolveContactName(num),
                            "connectTime" to connectTime,
                            "elapsedSeconds" to elapsedSeconds
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

    private fun getUserProfilePhoto(): ByteArray? {
        // 1. Direct ContactsContract.Profile.CONTENT_URI photo
        try {
            val uri = Uri.withAppendedPath(android.provider.ContactsContract.Profile.CONTENT_URI, android.provider.ContactsContract.Contacts.Photo.CONTENT_DIRECTORY)
            contentResolver.query(
                uri,
                arrayOf(android.provider.ContactsContract.Contacts.Photo.PHOTO),
                null, null, null
            )?.use {
                if (it.moveToFirst()) {
                    val blob = it.getBlob(0)
                    if (blob != null && blob.isNotEmpty()) return blob
                }
            }
        } catch (e: Exception) {
            android.util.Log.d("OnyxMainActivity", "Profile photo query: ${e.message}")
        }

        // 2. Profile Raw Contacts Data
        try {
            val rawUri = Uri.withAppendedPath(android.provider.ContactsContract.Profile.CONTENT_RAW_CONTACTS_URI, "data")
            contentResolver.query(
                rawUri,
                arrayOf(android.provider.ContactsContract.CommonDataKinds.Photo.PHOTO),
                "${android.provider.ContactsContract.Data.MIMETYPE} = ?",
                arrayOf(android.provider.ContactsContract.CommonDataKinds.Photo.CONTENT_ITEM_TYPE),
                null
            )?.use {
                if (it.moveToFirst()) {
                    val blob = it.getBlob(0)
                    if (blob != null && blob.isNotEmpty()) return blob
                }
            }
        } catch (e: Exception) {
            android.util.Log.d("OnyxMainActivity", "Raw profile photo query: ${e.message}")
        }

        // 3. Contacts named 'Me', 'Owner', 'Myself'
        try {
            val projection = arrayOf(
                android.provider.ContactsContract.CommonDataKinds.Photo.PHOTO,
                android.provider.ContactsContract.CommonDataKinds.Photo.DISPLAY_NAME
            )
            val selection = "${android.provider.ContactsContract.Data.MIMETYPE} = ? AND (" +
                    "${android.provider.ContactsContract.CommonDataKinds.Photo.DISPLAY_NAME} LIKE 'Me%' OR " +
                    "${android.provider.ContactsContract.CommonDataKinds.Photo.DISPLAY_NAME} LIKE 'My%' OR " +
                    "${android.provider.ContactsContract.CommonDataKinds.Photo.DISPLAY_NAME} LIKE 'Owner%')"
            contentResolver.query(
                android.provider.ContactsContract.Data.CONTENT_URI,
                projection,
                selection,
                arrayOf(android.provider.ContactsContract.CommonDataKinds.Photo.CONTENT_ITEM_TYPE),
                null
            )?.use {
                if (it.moveToFirst()) {
                    val blob = it.getBlob(0)
                    if (blob != null && blob.isNotEmpty()) return blob
                }
            }
        } catch (e: Exception) {
            android.util.Log.d("OnyxMainActivity", "Named profile search: ${e.message}")
        }

        return null
    }

    private fun handleSecretCode(code: String): Map<String, Any> {
        val response = mutableMapOf<String, Any>("handled" to false)
        try {
            // 1. Handle *#06# (IMEI)
            if (code == "*#06#" || code == "*#06") {
                val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
                val imeis = mutableListOf<String>()
                if (checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val imei1 = telephonyManager.getImei(0)
                            if (!imei1.isNullOrEmpty()) imeis.add("IMEI 1: $imei1")
                            val imei2 = telephonyManager.getImei(1)
                            if (!imei2.isNullOrEmpty()) imeis.add("IMEI 2: $imei2")
                        } catch (e: Exception) {}
                    }
                    if (imeis.isEmpty()) {
                        try {
                            val deviceId = telephonyManager.deviceId
                            if (!deviceId.isNullOrEmpty()) imeis.add("IMEI: $deviceId")
                        } catch (e: Exception) {}
                    }
                }
                if (imeis.isEmpty()) {
                    imeis.add("IMEI information requires Phone permission")
                }
                response["handled"] = true
                response["type"] = "imei"
                response["info"] = imeis.joinToString("\n")
                return response
            }

            // 2. Extract secret code digits from *#*#<code>#*#* or *#<code>#
            var secretCode: String? = null
            if (code.startsWith("*#*#") && code.endsWith("#*#*") && code.length >= 9) {
                val inner = code.substring(4, code.length - 4)
                if (inner.isNotEmpty() && !inner.contains("*") && !inner.contains("#")) {
                    secretCode = inner
                }
            } else if (code.startsWith("*#") && code.endsWith("#") && code.length >= 4 && !code.startsWith("*#*#")) {
                val inner = code.substring(2, code.length - 1)
                if (inner.isNotEmpty() && !inner.contains("*") && !inner.contains("#")) {
                    secretCode = inner
                }
            }

            if (!secretCode.isNullOrEmpty()) {
                val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager

                // 1. Android Official API for Default Dialer (API 26+)
                // Runs inside com.android.phone system process which has all permissions for TestingSettings, RadioInfo & OEM secret codes
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        telephonyManager.sendDialerSpecialCode(secretCode)
                        android.util.Log.d("OnyxMainActivity", "sendDialerSpecialCode successfully dispatched for $secretCode")
                        response["handled"] = true
                        response["type"] = "special_code"
                        return response
                    } catch (e: Exception) {
                        android.util.Log.e("OnyxMainActivity", "sendDialerSpecialCode error: ${e.message}")
                    }
                }

                var launchedActivity = false

                // 2. Fallback: If 4636 (INFO), try direct activity launches
                if (secretCode == "4636" || secretCode.equals("INFO", ignoreCase = true)) {
                    val candidates = listOf(
                        Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.RadioInfo")),
                        Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.TestingSettings")),
                        Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.Settings\$RadioInfoActivity")),
                        Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.Settings\$TestingSettingsActivity")),
                        Intent().setComponent(ComponentName("com.android.phone", "com.android.phone.TestingSettings")),
                        Intent().setComponent(ComponentName("com.android.phone", "com.android.phone.RadioInfo")),
                        Intent("android.settings.TESTING_SETTINGS"),
                        Intent("android.intent.action.MAIN").addCategory("android.intent.category.TESTING_SETTINGS")
                    )

                    for (intent in candidates) {
                        try {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            launchedActivity = true
                            break
                        } catch (e: Exception) {
                            android.util.Log.d("OnyxMainActivity", "TestingSettings candidate failed: ${e.message}")
                        }
                    }

                    // If normal startActivity was blocked (e.g. unexported component), try root
                    if (!launchedActivity) {
                        try {
                            val cmds = arrayOf(
                                "am start -n com.android.settings/.RadioInfo",
                                "am start -n com.android.settings/.TestingSettings",
                                "am start -n com.android.settings/.Settings\\\$RadioInfoActivity",
                                "am start -n com.android.settings/.Settings\\\$TestingSettingsActivity",
                                "am start -n com.android.phone/.TestingSettings"
                            ).joinToString(" || ")
                            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", cmds))
                            val exit = process.waitFor()
                            if (exit == 0) launchedActivity = true
                        } catch (e: Exception) {
                            android.util.Log.d("OnyxMainActivity", "Root activity start failed: ${e.message}")
                        }
                    }
                }

                // 2. Broadcast SECRET_CODE intent to system and OEM receivers
                try {
                    val secretUri = Uri.parse("android_secret_code://$secretCode")
                    val secretIntent = Intent("android.provider.Telephony.SECRET_CODE", secretUri)

                    // Find and trigger explicit broadcast receivers (bypasses Android 8+ background limits)
                    val receivers = packageManager.queryBroadcastReceivers(secretIntent, 0)
                    for (resolveInfo in receivers) {
                        try {
                            val explicitIntent = Intent(secretIntent).apply {
                                component = ComponentName(resolveInfo.activityInfo.packageName, resolveInfo.activityInfo.name)
                                flags = Intent.FLAG_RECEIVER_FOREGROUND or Intent.FLAG_INCLUDE_STOPPED_PACKAGES
                            }
                            sendBroadcast(explicitIntent)
                        } catch (e: Exception) {}
                    }

                    secretIntent.addFlags(Intent.FLAG_RECEIVER_FOREGROUND or Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
                    sendBroadcast(secretIntent)
                } catch (e: Exception) {
                    android.util.Log.e("OnyxMainActivity", "Broadcast secret code failed: ${e.message}")
                }

                // Root broadcast fallback for OEM engineer modes
                try {
                    Runtime.getRuntime().exec(arrayOf("su", "-c", "am broadcast -a android.provider.Telephony.SECRET_CODE -d android_secret_code://$secretCode"))
                } catch (e: Exception) {}

                response["handled"] = true
                response["type"] = if (launchedActivity) "activity" else "broadcast"
                return response
            }
        } catch (e: Exception) {
            android.util.Log.e("OnyxMainActivity", "handleSecretCode error: ${e.message}")
        }
        return response
    }
}
