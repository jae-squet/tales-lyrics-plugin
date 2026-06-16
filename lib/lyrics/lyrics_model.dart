// lib/lyrics/lyrics_model.dart
// Core data classes + LRC parsers (standard line-level & word-level).

class Word {
  final String text;
  final Duration time;
  const Word(this.text, this.time);
}

class LyricLine {
  final List<Word> words;
  const LyricLine(this.words);

  Duration get startTime => words.isNotEmpty ? words.first.time : Duration.zero;

  /// Flat text for non-word-highlight display
  String get plainText => words.map((w) => w.text).join(' ');
}

enum LrcFormat { wordLevel, standard, unknown }

class LyricsModel {
  // ── Auto-detect and parse ─────────────────────────────────────────────────
  List<LyricLine> parse(String raw) {
    final fmt = _detectFormat(raw);
    switch (fmt) {
      case LrcFormat.wordLevel:
        return parseWordLrc(raw);
      case LrcFormat.standard:
        return parseLrc(raw);
      case LrcFormat.unknown:
        return [];
    }
  }

  LrcFormat _detectFormat(String raw) {
    // Word-level LRC has multiple timestamps on one line
    final multiTs = RegExp(r'\[\d{2}:\d{2}\.\d{2,3}\].*\[\d{2}:\d{2}\.\d{2,3}\]');
    if (multiTs.hasMatch(raw)) return LrcFormat.wordLevel;
    final singleTs = RegExp(r'\[\d{2}:\d{2}\.\d{2,3}\]');
    if (singleTs.hasMatch(raw)) return LrcFormat.standard;
    return LrcFormat.unknown;
  }

  // ── Word-level LRC: [mm:ss.xx]word [mm:ss.xx]word … ─────────────────────
  List<LyricLine> parseWordLrc(String raw) {
    final lines  = raw.split(RegExp(r'\r?\n'));
    final result = <LyricLine>[];
    final wordRx = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]([^\[]+)');

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final matches = wordRx.allMatches(line);
      final words   = <Word>[];

      for (final m in matches) {
        final text = m.group(4)!.trim();
        if (text.isEmpty) continue;
        words.add(Word(text, _parseTime(m.group(1)!, m.group(2)!, m.group(3)!)));
      }

      if (words.isNotEmpty) result.add(LyricLine(words));
    }
    return result;
  }

  // ── Standard LRC: [mm:ss.xx] Whole line ──────────────────────────────────
  List<LyricLine> parseLrc(String raw) {
    final lines  = raw.split(RegExp(r'\r?\n'));
    final result = <LyricLine>[];
    final lineRx = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

    for (final line in lines) {
      final m    = lineRx.firstMatch(line.trim());
      if (m == null) continue;
      final text = m.group(4)!.trim();
      if (text.isEmpty) continue;
      final time = _parseTime(m.group(1)!, m.group(2)!, m.group(3)!);
      result.add(LyricLine([Word(text, time)]));
    }
    return result;
  }

  // ── Active-line/word helpers ──────────────────────────────────────────────
  int getActiveLine(List<LyricLine> lines, Duration position) {
    for (int i = lines.length - 1; i >= 0; i--) {
      if (position >= lines[i].startTime) return i;
    }
    return 0;
  }

  int getActiveWord(List<LyricLine> lines, Duration position, int lineIndex) {
    if (lineIndex >= lines.length) return 0;
    final words = lines[lineIndex].words;
    for (int i = words.length - 1; i >= 0; i--) {
      if (position >= words[i].time) return i;
    }
    return 0;
  }

  // ── Private ───────────────────────────────────────────────────────────────
  Duration _parseTime(String mm, String ss, String frac) {
    final ms = frac.length == 2 ? int.parse(frac) * 10 : int.parse(frac);
    return Duration(
      minutes:      int.parse(mm),
      seconds:      int.parse(ss),
      milliseconds: ms,
    );
  }
}
