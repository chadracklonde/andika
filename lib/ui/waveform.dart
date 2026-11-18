import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Onde sonore défilante : la tête de lecture reste au centre, l'enregistré passe à gauche,
/// la règle des secondes court sur toute la largeur.
class RecordingWaveform extends StatelessWidget {
  const RecordingWaveform({
    super.key,
    required this.levels,
    required this.levelsOffset,
    required this.elapsedMs,
    required this.bucketMs,
    this.markers = const <int>[],
    this.height = 260,
  });

  final List<double> levels;
  final int levelsOffset;
  final int elapsedMs;
  final int bucketMs;
  final List<int> markers;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: WaveformPainter(
            levels: levels,
            levelsOffset: levelsOffset,
            elapsedMs: elapsedMs,
            bucketMs: bucketMs,
            markers: markers,
            background: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            bar: const Color(0xFFE8473F),
            tick: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            label: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.levels,
    required this.levelsOffset,
    required this.elapsedMs,
    required this.bucketMs,
    required this.markers,
    required this.background,
    required this.bar,
    required this.tick,
    required this.label,
  });

  final List<double> levels;
  final int levelsOffset;
  final int elapsedMs;
  final int bucketMs;
  final List<int> markers;
  final Color background;
  final Color bar;
  final Color tick;
  final Color label;

  /// Largeur d'une seconde à l'écran.
  static const double pxPerSecond = 96;
  static const double _axisHeight = 34;

  /// Abscisse d'un instant (en ms), la tête de lecture étant au centre.
  static double xAt(int ms, int nowMs, double width) => width / 2 + (ms - nowMs) * pxPerSecond / 1000;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final plotH = size.height - _axisHeight;
    canvas.drawRect(Offset.zero & Size(w, plotH), Paint()..color = background);

    // Barres : une par tranche, de la plus récente vers la gauche.
    final barPaint = Paint()
      ..color = bar
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final mid = plotH / 2;
    for (var i = levels.length - 1; i >= 0; i--) {
      final t = (levelsOffset + i) * bucketMs;
      final x = xAt(t, elapsedMs, w);
      if (x > w / 2) continue;
      if (x < -4) break;
      final half = math.max(1.5, math.sqrt(levels[i]) * plotH * 0.46);
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), barPaint);
    }

    // Règle : un trait tous les 250 ms, une graduation chaque seconde.
    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 1;
    final firstMs = (elapsedMs - (w / 2) * 1000 / pxPerSecond).floor();
    final lastMs = (elapsedMs + (w / 2) * 1000 / pxPerSecond).ceil();
    for (var t = (math.max(0, firstMs) ~/ 250) * 250; t <= lastMs; t += 250) {
      final x = xAt(t, elapsedMs, w);
      final whole = t % 1000 == 0;
      canvas.drawLine(
        Offset(x, plotH),
        Offset(x, plotH + (whole ? 12 : 6)),
        tickPaint,
      );
      if (whole && t % 1000 == 0) {
        final sec = t ~/ 1000;
        final text = '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
        final tp = TextPainter(
          text: TextSpan(text: text, style: TextStyle(color: label, fontSize: 12)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, plotH + 14));
      }
    }

    // Repères : un drapeau orange sur la ligne du temps.
    final flag = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 2;
    for (final m in markers) {
      final x = xAt(m, elapsedMs, w);
      if (x < -12 || x > w + 12) continue;
      canvas.drawLine(Offset(x, 6), Offset(x, plotH), flag);
      canvas.drawPath(
        Path()
          ..moveTo(x, 6)
          ..lineTo(x + 14, 12)
          ..lineTo(x, 18)
          ..close(),
        Paint()..color = const Color(0xFFF59E0B),
      );
    }

    // Tête de lecture.
    final head = Paint()
      ..color = bar
      ..strokeWidth = 2;
    canvas.drawLine(Offset(w / 2, 6), Offset(w / 2, plotH + 6), head);
    canvas.drawCircle(Offset(w / 2, 6), 4, Paint()..color = bar);
    canvas.drawCircle(Offset(w / 2, plotH + 6), 4, Paint()..color = bar);
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.elapsedMs != elapsedMs ||
      old.levels.length != levels.length ||
      old.levelsOffset != levelsOffset ||
      old.markers.length != markers.length ||
      old.background != background;
}
