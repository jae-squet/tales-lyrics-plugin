// lib/lyrics/lyrics_provider.dart
//
// ChangeNotifier that drives the entire lyrics pipeline.
// Consumed by LyricsScreen and the toggle button in AudioPlayerScreen.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'lyrics_model.dart';
import 'lyrics_service.dart';
import 'lyrics_pack_manager.dart';
import 'lyrics_state.dart';

class LyricsProvider extends ChangeNotifier {
  final LyricsPackManager _packManager = LyricsPackManager();
  late final LyricsService _service    = LyricsService(_packManager);

  // ── Public state ──────────────────────────────────────────────────────────
  LyricsState     state         = LyricsState.idle;
  List<LyricLine> lines         = [];
  LyricsSource?   source;
  int             activeLine    = 0;
  int             activeWord    = 0;
  String          errorMessage  = '';

  // Download progress (0.0 – 1.0)
  double downloadProgress  = 0.0;
  int    downloadReceived  = 0; // bytes
  int    downloadTotal     = 0; // bytes
  String downloadPhase     = '';

  // Generation progress (0.0 – 1.0)
  double generationProgress = 0.0;
  String generationMessage  = '';

  // ── Internal ──────────────────────────────────────────────────────────────
  String?      _currentSongId;
  String?      _currentAudioPath;
  bool         _lyricsEnabled = false;
  CancelToken? _cancelToken;
  StreamSubscription<Duration>? _positionSub;
  final LyricsModel _model = LyricsModel();

  // ── Lyrics toggle ─────────────────────────────────────────────────────────

  bool get lyricsEnabled => _lyricsEnabled;

  /// Call when user taps the lyrics toggle button.
  Future<void> toggleLyrics({
    required String audioPath,
    required String songId,
  }) async {
    if (_lyricsEnabled &&
        _currentSongId == songId &&
        state == LyricsState.showing) {
      // Turn off
      _lyricsEnabled = false;
      state          = LyricsState.idle;
      lines          = [];
      notifyListeners();
      return;
    }

    _lyricsEnabled      = true;
    _currentSongId      = songId;
    _currentAudioPath   = audioPath;
    await _runPipeline(audioPath: audioPath, songId: songId);
  }

  /// Call when the song changes while lyrics are enabled.
  Future<void> onSongChanged({
    required String audioPath,
    required String songId,
  }) async {
    if (!_lyricsEnabled) return;
    _currentSongId    = songId;
    _currentAudioPath = audioPath;
    lines             = [];
    activeLine        = 0;
    activeWord        = 0;
    await _runPipeline(audioPath: audioPath, songId: songId);
  }

  // ── Pack download (called after user confirms) ────────────────────────────

  Future<void> downloadPack() async {
    _cancelToken = CancelToken();
    _setState(LyricsState.downloadingPack);
    downloadProgress = 0.0;
    downloadReceived = 0;
    downloadTotal    = 0;

    try {
      await _packManager.downloadAndInstall(
        cancelToken: _cancelToken,
        onProgress:  (received, total, phase) {
          downloadReceived = received;
          downloadTotal    = total;
          downloadProgress = total > 0 ? received / total : 0.0;
          downloadPhase    = phase;
          notifyListeners();
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _setState(LyricsState.noPack);
        return;
      }
      _setError('Download failed: ${e.message}');
      return;
    } catch (e) {
      _setError('Install failed: $e');
      return;
    }

    // Installation succeeded — continue pipeline
    _setState(LyricsState.installingPack);
    await Future.delayed(const Duration(milliseconds: 300));

    if (_currentAudioPath != null && _currentSongId != null) {
      await _runPipeline(
        audioPath: _currentAudioPath!,
        songId:    _currentSongId!,
      );
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
    _setState(LyricsState.noPack);
  }

  // ── Position sync (call from AudioPlayerScreen) ───────────────────────────

  void onPosition(Duration position) {
    if (state != LyricsState.showing || lines.isEmpty) return;
    final newLine = _model.getActiveLine(lines, position);
    final newWord = _model.getActiveWord(lines, position, newLine);
    if (newLine != activeLine || newWord != activeWord) {
      activeLine = newLine;
      activeWord = newWord;
      notifyListeners();
    }
  }

  // ── Pipeline ──────────────────────────────────────────────────────────────

  Future<void> _runPipeline({
    required String audioPath,
    required String songId,
  }) async {
    _setState(LyricsState.checking);

    // Check pack first so we can fast-path the prompt
    final packInstalled = await _packManager.isInstalled();

    final result = await _service.resolve(
      audioPath:       audioPath,
      songId:          songId,
      allowGeneration: packInstalled,
      onProgress:      (p, msg) {
        generationProgress = p;
        generationMessage  = msg;
        if (state != LyricsState.generating) {
          state = LyricsState.generating;
        }
        notifyListeners();
      },
    );

    if (result != null) {
      lines      = result.lines;
      source     = result.source;
      activeLine = 0;
      activeWord = 0;
      _setState(LyricsState.showing);
      return;
    }

    // No lyrics found from any source
    if (!packInstalled) {
      _setState(LyricsState.noPack);
    } else {
      _setState(LyricsState.notFound);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setState(LyricsState s) {
    state = s;
    notifyListeners();
  }

  void _setError(String msg) {
    errorMessage = msg;
    state        = LyricsState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _service.releaseWhisper();
    super.dispose();
  }
}
