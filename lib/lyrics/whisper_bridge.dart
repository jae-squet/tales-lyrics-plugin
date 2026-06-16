// lib/lyrics/whisper_bridge.dart
//
// Loads the downloaded libwhisper_jni.so at runtime via a MethodChannel.
// The Android-side code (WhisperPlugin.kt) receives the .so path, loads it
// with System.load(), and calls the native transcribe() function.
//
// This file stays in the APK but is ~0 KB — it only contains the Dart glue.
// The actual 5 MB native binary lives outside the APK in the lyrics_pack dir.

import 'dart:async';
import 'package:flutter/services.dart';

class WhisperBridge {
  static const MethodChannel _channel =
      MethodChannel('com.squet.talesplayer.lyrics/whisper');

  final String soPath;
  final String modelPath;

  WhisperBridge({required this.soPath, required this.modelPath});

  /// Load the native library.  Must be called once before [transcribe].
  Future<void> load() async {
    await _channel.invokeMethod<void>('loadLibrary', {
      'soPath':    soPath,
      'modelPath': modelPath,
    });
  }

  /// Transcribe [audioPath] and return a word-level LRC string.
  ///
  /// [onProgress] receives progress 0.0 → 1.0.
  /// This is a long-running call — it runs on a background isolate on the
  /// Android side via a WorkManager / Coroutine so it won't block the UI.
  Future<String> transcribe({
    required String audioPath,
    void Function(double progress, String message)? onProgress,
  }) async {
    // Progress events come through an EventChannel
    const EventChannel progressChannel =
        EventChannel('com.squet.talesplayer.lyrics/whisper_progress');

    final progressSub = progressChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final p   = (event['progress'] as num?)?.toDouble() ?? 0.0;
        final msg = event['message'] as String? ?? '';
        onProgress?.call(p, msg);
      }
    });

    try {
      final lrc = await _channel.invokeMethod<String>('transcribe', {
        'audioPath': audioPath,
        'modelPath': modelPath,
      });

      if (lrc == null || lrc.trim().isEmpty) {
        throw Exception('Whisper returned empty transcription.');
      }
      return lrc;
    } finally {
      await progressSub.cancel();
    }
  }

  /// Free the native model from memory (call when done).
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
  }
}
