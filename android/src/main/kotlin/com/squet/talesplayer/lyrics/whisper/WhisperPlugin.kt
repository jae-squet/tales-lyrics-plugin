package com.squet.talesplayer.lyrics.whisper

import android.os.Build
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File

/**
 * Handles MethodChannel calls from [WhisperBridge] on the Dart side.
 *
 * Channels:
 *   com.squet.talesplayer.lyrics/whisper          → loadLibrary, transcribe, release
 *   com.squet.talesplayer.lyrics/whisper_progress → EventChannel for transcription progress
 *   com.squet.talesplayer.lyrics/device_info      → getPrimaryAbi
 */
class WhisperPlugin(
    private val methodChannel: MethodChannel,
    private val progressChannel: EventChannel,
    private val deviceInfoChannel: MethodChannel,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var progressSink: EventChannel.EventSink? = null
    private var isLibraryLoaded = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadLibrary" -> handleLoadLibrary(call, result)
            "transcribe"  -> handleTranscribe(call, result)
            "release"     -> handleRelease(result)
            else          -> result.notImplemented()
        }
    }

    private fun handleLoadLibrary(call: MethodCall, result: MethodChannel.Result) {
        val soPath    = call.argument<String>("soPath")    ?: return result.error("ARG", "soPath missing", null)
        val modelPath = call.argument<String>("modelPath") ?: return result.error("ARG", "modelPath missing", null)

        scope.launch {
            try {
                if (!File(soPath).exists())    error("Native library not found: $soPath")
                if (!File(modelPath).exists()) error("Model file not found: $modelPath")

                System.load(soPath)
                isLibraryLoaded = true
                nativeInit(modelPath)

                withContext(Dispatchers.Main) { result.success(null) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("LOAD_FAILED", e.message, null) }
            }
        }
    }

    private fun handleTranscribe(call: MethodCall, result: MethodChannel.Result) {
        val audioPath = call.argument<String>("audioPath") ?: return result.error("ARG", "audioPath missing", null)

        if (!isLibraryLoaded) return result.error("NOT_LOADED", "Call loadLibrary first", null)
        if (!File(audioPath).exists()) return result.error("FILE", "Audio not found: $audioPath", null)

        scope.launch {
            try {
                val lrc = nativeTranscribe(audioPath) { progress, message ->
                    scope.launch(Dispatchers.Main) {
                        progressSink?.success(mapOf("progress" to progress, "message" to message))
                    }
                }
                withContext(Dispatchers.Main) { result.success(lrc) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("TRANSCRIBE_FAILED", e.message, null) }
            }
        }
    }

    private fun handleRelease(result: MethodChannel.Result) {
        scope.launch {
            try {
                nativeRelease()
                isLibraryLoaded = false
                withContext(Dispatchers.Main) { result.success(null) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("RELEASE_FAILED", e.message, null) }
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        progressSink = events
    }

    override fun onCancel(arguments: Any?) {
        progressSink = null
    }

    fun dispose() {
        scope.cancel()
        progressSink = null
    }

    private external fun nativeInit(modelPath: String)
    private external fun nativeTranscribe(
        audioPath: String,
        onProgress: (progress: Float, message: String) -> Unit,
    ): String
    private external fun nativeRelease()
}
