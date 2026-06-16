// lib/lyrics/audio_visualizer.dart
// Animated waveform background used behind the lyrics text.
// Uses a sine-wave simulation — replace with real FFT data if desired.

import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class AudioVisualizer extends StatefulWidget {
  final Stream<Duration> positionStream;

  const AudioVisualizer({super.key, required this.positionStream});

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  double _energy = 0.4;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat();

    widget.positionStream.listen((_) {
      if (mounted) {
        setState(() => _energy = 0.25 + Random().nextDouble() * 0.55);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _WavePainter(_energy, _ctrl.value),
          size: Size.infinite,
        ),
      );
}

class _WavePainter extends CustomPainter {
  final double energy;
  final double tick;
  _WavePainter(this.energy, this.tick);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppConstants.primaryColor.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    const bars = 40;
    final bw   = size.width / bars;

    for (int i = 0; i < bars; i++) {
      final h = (sin(i * 0.4 + tick * 2 * pi + energy * 8) + 1) *
          0.5 *
          size.height *
          energy *
          0.6;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * bw, size.height - h, bw * 0.65, h),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.energy != energy || old.tick != tick;
}
