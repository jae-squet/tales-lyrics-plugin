package com.squet.talesplayer.lyrics

import android.os.Build
import com.squet.talesplayer.lyrics.whisper.WhisperPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Registers all channels needed by the lyrics feature.
 *
 * Add to your existing MainActivity.kt:
 *
 *   import com.squet.talesplayer.lyrics.LyricsPluginRegistrar
 *
 *   override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
 *       super.configureFlutterEngine(flutterEngine)
 *       LyricsPluginRegistrar.register(flutterEngine)
 *   }
 *
 *   override fun onDestroy() {
 *       super.onDestroy()
 *       LyricsPluginRegistrar.dispose()
 *   }
 */
object LyricsPluginRegistrar {

    private var whisperPlugin: WhisperPlugin? = null

    fun register(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val methodChannel   = MethodChannel(messenger, "com.squet.talesplayer.lyrics/whisper")
        val progressChannel = EventChannel(messenger, "com.squet.talesplayer.lyrics/whisper_progress")

        val deviceInfoChannel = MethodChannel(messenger, "com.squet.talesplayer.lyrics/device_info")
        deviceInfoChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPrimaryAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")
                else            -> result.notImplemented()
            }
        }

        val plugin = WhisperPlugin(methodChannel, progressChannel, deviceInfoChannel)
        whisperPlugin = plugin

        methodChannel.setMethodCallHandler(plugin)
        progressChannel.setStreamHandler(plugin)
    }

    fun dispose() {
        whisperPlugin?.dispose()
        whisperPlugin = null
    }
}
