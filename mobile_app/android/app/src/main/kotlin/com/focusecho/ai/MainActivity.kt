package com.focusecho.ai

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var ambience: android.media.MediaPlayer? = null

    override fun onDestroy() {
        ambience?.release()
        ambience = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        PermissionBridge(this).register(flutterEngine)
        BatteryBridge(this).register(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "focus_echo/distraction_stream")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    distractionEventSink = events
                    // Stage records remain durable until Dart acknowledges SQLite insertion.
                    if (events != null) FocusDetectionService.flushBufferedEvents(this@MainActivity)
                }

                override fun onCancel(arguments: Any?) {
                    distractionEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "focus_echo/session")
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                when (call.method) {
                    "reopenTask" -> {
                        val target = call.arguments as? String
                        val launch = target?.let { packageManager.getLaunchIntentForPackage(it) }
                        if (launch == null) result.success(false)
                        else try {
                            startActivity(launch)
                            result.success(true)
                        } catch (_: SecurityException) { result.success(false) }
                    }
                    "studioAmbience" -> {
                        val volume = (call.arguments as? Number)?.toFloat()?.coerceIn(0f, 1f) ?: 0f
                        try {
                            if (volume == 0f) {
                                ambience?.release()
                                ambience = null
                            } else {
                                val player = ambience ?: android.media.MediaPlayer().also {
                                    ambience = it
                                    val key = io.flutter.FlutterInjector.instance().flutterLoader()
                                        .getLookupKeyForAsset("assets/audio/soft_noise.wav")
                                    assets.openFd(key).use { fd ->
                                        it.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                                    }
                                    it.isLooping = true
                                    it.prepare()
                                }
                                player.setVolume(volume, volume)
                                if (!player.isPlaying) player.start()
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            ambience?.release()
                            ambience = null
                            result.error("audio_unavailable", "Ambient audio unavailable", null)
                        }
                    }
                    "ackDistractionEvent" -> {
                        val deliveryId = call.arguments as? String
                        result.success(
                            deliveryId != null && FocusDetectionService
                                .acknowledgeBufferedEvent(this, deliveryId),
                        )
                    }
                    "listLaunchableApps" -> {
                        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        result.success(packageManager.queryIntentActivities(query, 0)
                            .associate { it.activityInfo.packageName to it.loadLabel(packageManager).toString() })
                    }
                    "overlayPermission" -> result.success(android.provider.Settings.canDrawOverlays(this))
                    "openOverlayPermission" -> {
                        startActivity(Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:" + packageName)))
                        result.success(null)
                    }
                    "startSession" -> {
                        val intent = Intent(this, FocusDetectionService::class.java).apply {
                            action = FocusDetectionService.START_ACTION
                        }
                        startForegroundService(intent)
                        prefs.edit().putBoolean("flutter.session_active", true).apply()
                        result.success(true)
                    }
                    "stopSession" -> {
                        val intent = Intent(this, FocusDetectionService::class.java).apply {
                            action = FocusDetectionService.STOP_ACTION
                        }
                        stopService(intent)
                        prefs.edit().putBoolean("flutter.session_active", false).apply()
                        result.success(true)
                    }
                    "getSessionStatus" -> result.success(prefs.getBoolean("flutter.session_active", false))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "focus_echo/firebase_config")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isFirebaseConfigured" -> result.success(isFirebaseConfigured())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isFirebaseConfigured(): Boolean {
        val googleAppIdRes = resources.getIdentifier("google_app_id", "string", packageName)
        val senderIdRes = resources.getIdentifier("gcm_defaultSenderId", "string", packageName)
        val projectIdRes = resources.getIdentifier("project_id", "string", packageName)

        if (googleAppIdRes == 0 || senderIdRes == 0 || projectIdRes == 0) {
            return false
        }

        val googleAppId = getString(googleAppIdRes)
        val senderId = getString(senderIdRes)
        val projectId = getString(projectIdRes)

        return googleAppId.isNotBlank() && senderId.isNotBlank() && projectId.isNotBlank()
    }

    companion object {
        @JvmStatic
        var distractionEventSink: EventChannel.EventSink? = null
    }
}
