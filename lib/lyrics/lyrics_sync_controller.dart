// lib/lyrics/lyrics_sync_controller.dart
//
// Lightweight controller that maps a position stream to (line, word) indices.
// Kept separate so it can be unit-tested without a provider.

import 'dart:async';
import 'lyrics_model.dart';

class LyricsSyncController {
  final List<LyricLine> lines;
  final LyricsModel _model = LyricsModel();

  LyricsSyncController(this.lines);

  final StreamController<({int line, int word})> _controller =
      StreamController.broadcast();

  Stream<({int line, int word})> get stream => _controller.stream;

  StreamSubscription<Duration>? _sub;

  void start(Stream<Duration> positionStream) {
    _sub = positionStream.listen((position) {
      final line = _model.getActiveLine(lines, position);
      final word = _model.getActiveWord(lines, position, line);
      _controller.add((line: line, word: word));
    });
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
