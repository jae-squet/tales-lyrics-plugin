// lib/lyrics/lyrics_service.dart
//
// Implements the full lyrics resolution pipeline:
//
//   Open Song
//     ↓
//   Embedded tags? (ID3 USLT / SYLT)
//     ↓ yes → show
//     ↓ no
//   LRC file next to audio?
//     ↓ yes → show
//     ↓ no
//   Cached LRC on disk?
//     ↓ yes → show
//     ↓ no
//   Whisper pack installed?
//     ↓ no  → caller prompts download
//     ↓ yes
//   Generate LRC via Whisper
//     ↓
//   Save to cache
//     ↓
//   Show lyrics

import 'dart:io';
import 'package:flutter_audio_tagger/flutter_audio_tagger.dart'; // ID3 tag reading
import 'lyrics_model.dart';
import 'lyrics_pack_manager.dart';
import 'whisper_bridge.dart';

enum LyricsSource { embedded, lrcFile, cache, generated }

class LyricsResult {
  final List<LyricLine> lines;
  final LyricsSource    source;
  const LyricsResult({required this.lines, required this.source});
}

class LyricsService {
  final LyricsPackManager _packManager;
  final LyricsModel       _parser = LyricsModel();
  WhisperBridge?          _bridge;

  LyricsService(this._packManager);

  // ── Main pipeline ─────────────────────────────────────────────────────────

  /// Resolves lyrics for [audioPath].
  ///
  /// Returns null and sets [needsPackDownload] = true if the Whisper pack
  /// is not installed and no other source found lyrics.
  ///
  /// [onProgress] is called during generation (0.0 → 1.0).
  Future<LyricsResult?> resolve({
    required String audioPath,
    required String songId,
    bool allowGeneration = true,
    void Function(double progress, String message)? onProgress,
  }) async {
    // 1 ── Embedded tags ────────────────────────────────────────────────────
    final embedded = await _readEmbeddedLyrics(audioPath);
    if (embedded != null) {
      return LyricsResult(
        lines:  _parser.parse(embedded),
        source: LyricsSource.embedded,
      );
    }

    // 2 ── Sidecar .lrc file ────────────────────────────────────────────────
    final lrcFile = await _readSidecarLrc(audioPath);
    if (lrcFile != null) {
      return LyricsResult(
        lines:  _parser.parse(lrcFile),
        source: LyricsSource.lrcFile,
      );
    }

    // 3 ── Disk cache ───────────────────────────────────────────────────────
    final cached = await _packManager.readCachedLrc(songId);
    if (cached != null) {
      return LyricsResult(
        lines:  _parser.parse(cached),
        source: LyricsSource.cache,
      );
    }

    // 4 ── Generation via Whisper ───────────────────────────────────────────
    if (!allowGeneration) return null;

    final installed = await _packManager.isInstalled();
    if (!installed) return null; // caller must handle pack download

    final lrc = await _generateAndCache(
      audioPath:  audioPath,
      songId:     songId,
      onProgress: onProgress,
    );

    if (lrc == null) return null;
    return LyricsResult(
      lines:  _parser.parse(lrc),
      source: LyricsSource.generated,
    );
  }

  // ── Pack installed check (for provider) ──────────────────────────────────
  Future<bool> isPackInstalled() => _packManager.isInstalled();

  // ── Cleanup ───────────────────────────────────────────────────────────────
  Future<void> releaseWhisper() async {
    await _bridge?.release();
    _bridge = null;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

Future<String?> _readEmbeddedLyrics(String audioPath) async {
  try {
    final tagger = FlutterAudioTagger();
    final tag = await tagger.getAllTags(audioPath);

    final lyrics = tag?.lyrics;

    if (lyrics != null && lyrics.trim().isNotEmpty) {
      return lyrics;
    }
  } catch (_) {}

  return null;
}

  Future<String?> _readSidecarLrc(String audioPath) async {
    // Replace audio extension with .lrc
    final withoutExt = audioPath.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final lrcPath    = '$withoutExt.lrc';
    final file       = File(lrcPath);
    if (file.existsSync()) {
      final content = file.readAsStringSync();
      if (content.trim().isNotEmpty) return content;
    }
    return null;
  }

  Future<String?> _generateAndCache({
    required String audioPath,
    required String songId,
    void Function(double, String)? onProgress,
  }) async {
    try {
      onProgress?.call(0.0, 'Loading Whisper engine…');

      final so    = await _packManager.soPath;
      final model = await _packManager.modelPath;

      _bridge ??= WhisperBridge(soPath: so, modelPath: model);
      await _bridge!.load();

      final lrc = await _bridge!.transcribe(
        audioPath:  audioPath,
        onProgress: onProgress,
      );

      // Cache for future playback
      await _packManager.saveLrcCache(songId, lrc);

      return lrc;
    } catch (e) {
      return null;
    }
  }
}
