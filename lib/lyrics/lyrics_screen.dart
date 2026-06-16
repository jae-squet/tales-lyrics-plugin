// lib/lyrics/lyrics_screen.dart
//
// Full-screen lyrics overlay shown when the user enables lyrics.
// Driven entirely by LyricsProvider — no local state for pipeline logic.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import 'lyrics_provider.dart';
import 'lyrics_state.dart';
import 'audio_visualizer.dart';

class LyricsScreen extends StatefulWidget {
  final Stream<Duration> positionStream;
  final bool isDark;

  const LyricsScreen({
    super.key,
    required this.positionStream,
    required this.isDark,
  });

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final ScrollController _scroll = ScrollController();
  int _lastActiveLine = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll(int activeLine) {
    if (_lastActiveLine == activeLine) return;
    _lastActiveLine = activeLine;
    if (!_scroll.hasClients) return;
    final target = (activeLine * 72.0) - (MediaQuery.of(context).size.height * 0.3);
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LyricsProvider>(
      builder: (context, provider, _) {
        // Sync position to provider
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (provider.state == LyricsState.showing) {
            _autoScroll(provider.activeLine);
          }
        });

        return _buildBody(context, provider);
      },
    );
  }

  Widget _buildBody(BuildContext context, LyricsProvider provider) {
    switch (provider.state) {
      case LyricsState.idle:
        return const SizedBox.shrink();

      case LyricsState.checking:
        return _centeredMessage(
          icon: Icons.manage_search_rounded,
          title: 'Finding lyrics…',
          subtitle: 'Checking embedded tags, LRC files, and cache',
        );

      case LyricsState.noPack:
        return _downloadPrompt(context, provider);

      case LyricsState.downloadingPack:
        return _downloadProgress(provider);

      case LyricsState.installingPack:
        return _centeredMessage(
          icon: Icons.settings_rounded,
          title: 'Installing plugin…',
          subtitle: 'Almost ready',
        );

      case LyricsState.generating:
        return _generatingView(provider);

      case LyricsState.showing:
        return _lyricsView(provider);

      case LyricsState.notFound:
        return _centeredMessage(
          icon: Icons.lyrics_outlined,
          title: 'No lyrics found',
          subtitle: 'Lyrics could not be generated for this song',
        );

      case LyricsState.error:
        return _errorView(provider.errorMessage);
    }
  }

  // ── Download prompt ───────────────────────────────────────────────────────

  Widget _downloadPrompt(BuildContext context, LyricsProvider provider) {
    final isDark = widget.isDark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                gradient: AppConstants.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.primaryColor.withOpacity(0.4),
                    blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: const Icon(Icons.lyrics_rounded, size: 38, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              'Offline Lyrics Plugin',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'Generate perfectly synced lyrics for any song — fully offline, '
              'no internet needed after setup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            // Size info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppConstants.primaryColor.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.download_rounded,
                    color: AppConstants.primaryColor, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('One-time download  •  ~147 MB',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      'Whisper base model + native engine\nStored offline — never re-downloaded',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 11, height: 1.4)),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => provider.downloadPack(),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                ).copyWith(
                  backgroundColor: WidgetStateProperty.all(Colors.transparent),
                  overlayColor: WidgetStateProperty.all(
                    Colors.white.withOpacity(0.1)),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: AppConstants.brandGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: const Text(
                      'Download Lyrics Plugin',
                      style: TextStyle(
                        color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.read<LyricsProvider>().cancelDownload(),
              child: Text('Not now',
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Download progress ─────────────────────────────────────────────────────

  Widget _downloadProgress(LyricsProvider provider) {
    final mb       = (provider.downloadReceived / (1024 * 1024));
    final totalMb  = (provider.downloadTotal   / (1024 * 1024));
    final isDark   = widget.isDark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72, height: 72,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value:       provider.downloadProgress,
                  strokeWidth: 5,
                  valueColor:  const AlwaysStoppedAnimation(
                    AppConstants.primaryColor),
                  backgroundColor: AppConstants.primaryColor.withOpacity(0.15),
                ),
                Text(
                  '${(provider.downloadProgress * 100).toInt()}%',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Text(
              provider.downloadPhase,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${mb.toStringAsFixed(1)} MB  /  ${totalMb.toStringAsFixed(0)} MB',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 13),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value:           provider.downloadProgress,
                minHeight:       6,
                backgroundColor: AppConstants.primaryColor.withOpacity(0.15),
                valueColor:      const AlwaysStoppedAnimation(
                  AppConstants.primaryColor),
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => provider.cancelDownload(),
              icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
              label: const Text('Cancel',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Generating view ───────────────────────────────────────────────────────

  Widget _generatingView(LyricsProvider provider) {
    final isDark = widget.isDark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (b) => AppConstants.brandGradient.createShader(b),
              child: const Icon(Icons.graphic_eq_rounded,
                  size: 56, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              'Generating lyrics…',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              provider.generationMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 13),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value:           provider.generationProgress > 0
                    ? provider.generationProgress : null,
                minHeight:       6,
                backgroundColor: AppConstants.primaryColor.withOpacity(0.15),
                valueColor:      const AlwaysStoppedAnimation(
                  AppConstants.primaryColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Using local AI — no internet needed',
              style: TextStyle(
                color: isDark ? Colors.white30 : Colors.black26,
                fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ── Lyrics display ────────────────────────────────────────────────────────

  Widget _lyricsView(LyricsProvider provider) {
    final isDark = widget.isDark;
    return Stack(
      children: [
        // Animated waveform background
        Positioned.fill(
          child: AudioVisualizer(positionStream: widget.positionStream),
        ),

        // Gradient fade at top and bottom
        Positioned.fill(child: IgnorePointer(child: Column(children: [
          Container(height: 60,
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [
                (isDark ? AppConstants.darkBg : AppConstants.lightBg),
                Colors.transparent,
              ]))),
          const Spacer(),
          Container(height: 80,
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [
                (isDark ? AppConstants.darkBg : AppConstants.lightBg),
                Colors.transparent,
              ]))),
        ]))),

        // Lyrics list
        ListView.builder(
          controller:  _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
          itemCount:   provider.lines.length,
          itemBuilder: (context, i) {
            final line       = provider.lines[i];
            final isActive   = i == provider.activeLine;
            final isPast     = i < provider.activeLine;

            // Word-level highlighting (only for word-level LRC)
            final isWordLevel = line.words.length > 1;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 300),
              padding: EdgeInsets.symmetric(vertical: isActive ? 14 : 8),
              child: isWordLevel
                  ? _wordLevelLine(
                      line.words.map((w) => w.text).toList(),
                      isActive ? provider.activeWord : -1,
                      isActive, isPast, isDark)
                  : _plainLine(
                      line.plainText, isActive, isPast, isDark),
            );
          },
        ),
      ],
    );
  }

  Widget _wordLevelLine(
    List<String> words, int activeWord, bool isActive, bool isPast, bool isDark,
  ) {
    return Wrap(
      children: List.generate(words.length, (w) {
        final isActiveWord = isActive && w == activeWord;
        final isPastWord   = isActive
            ? w < activeWord
            : isPast;

        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize:   isActiveWord ? 26 : (isActive ? 22 : 18),
            fontWeight: isActiveWord ? FontWeight.w900
                : (isActive ? FontWeight.w600 : FontWeight.w400),
            color: isActiveWord
                ? Colors.white
                : isPastWord
                    ? AppConstants.primaryColor.withOpacity(0.8)
                    : (isDark ? Colors.white38 : Colors.black26),
            shadows: isActiveWord
                ? [Shadow(
                    blurRadius: 20,
                    color: AppConstants.primaryColor.withOpacity(0.8))]
                : null,
            height: 1.6,
          ),
          child: Text('${words[w]} '),
        );
      }),
    );
  }

  Widget _plainLine(String text, bool isActive, bool isPast, bool isDark) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 250),
      style: TextStyle(
        fontSize:   isActive ? 24 : 18,
        fontWeight: isActive ? FontWeight.w800 : FontWeight.w400,
        color: isActive
            ? Colors.white
            : isPast
                ? AppConstants.primaryColor.withOpacity(0.7)
                : (isDark ? Colors.white30 : Colors.black26),
        shadows: isActive
            ? [Shadow(
                blurRadius: 24,
                color: AppConstants.primaryColor.withOpacity(0.9))]
            : null,
        height: 1.5,
      ),
      child: Text(text),
    );
  }

  // ── Generic states ────────────────────────────────────────────────────────

  Widget _centeredMessage({
    required IconData icon,
    required String   title,
    required String   subtitle,
  }) {
    final isDark = widget.isDark;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48,
            color: AppConstants.primaryColor.withOpacity(0.6)),
        const SizedBox(height: 16),
        Text(title,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 13)),
      ]),
    );
  }

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          const Text('Something went wrong',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
      ),
    );
  }
}
