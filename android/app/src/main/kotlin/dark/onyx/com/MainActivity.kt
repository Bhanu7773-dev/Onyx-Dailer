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

class MainActivity: FlutterActivity() {
    private val METHOD_CHANNEL = "dark.onyx.com/telecom_commands"
    private val EVENT_CHANNEL = "dark.onyx.com/telecom_events"
    private var eventSink: EventChannel.EventSink? = null
    private var toneGenerator: ToneGenerator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.navigationBarColor = 0x00000000 
        window.statusBarColor = 0x00000000 
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
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
                "makeCall" -> {
                    val number = call.argument<String>("number")
                    if (number != null) {
                        makeCall(number)
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
                    if (enabled) {
                        CallService.currentCall?.hold()
                    } else {
                        CallService.currentCall?.unhold()
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
                    CallService.currentCall?.let {
                        if (it.state == Call.STATE_RINGING) {
                            it.reject(false, null)
                        } else {
                            it.disconnect()
                        }
                    }
                    result.success(null)
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
                            val data = mapOf(
                                "state" to state,
                                "number" to (call.details.handle?.schemeSpecificPart ?: "Unknown")
                            )
                            eventSink?.success(data)
                        }
                    }
                    CallService.currentCall?.let {
                        val data = mapOf(
                            "state" to it.state,
                            "number" to (it.details.handle?.schemeSpecificPart ?: "Unknown")
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

    private fun makeCall(number: String) {
        val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val uri = Uri.fromParts("tel", number, null)
        val extras = Bundle()
        try {
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
