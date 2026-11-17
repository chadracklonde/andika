import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'wav_file.dart';

/// Un frame d'énergie = 100 ms d'audio.
const int kFrameSamples = 1600;

/// Durée minimale d'un morceau (10 s) et maximale (28 s : Whisper traite 30 s à la fois).
const int kMinChunkFrames = 100;
const int kMaxChunkFrames = 280;

/// Un morceau d'audio à transcrire, en échantillons (16 000 par seconde).
class AudioChunk {
  const AudioChunk({required this.index, required this.startSample, required this.endSample});

  /// Rang du morceau dans le plan (0, 1, 2...).
  final int index;
  final int startSample;
  final int endSample;

  int get sampleCount => endSample - startSample;
  int get startMs => startSample * 1000 ~/ WavReader.sampleRate;
  int get endMs => endSample * 1000 ~/ WavReader.sampleRate;
  int get durationMs => endMs - startMs;

  @override
  String toString() => 'AudioChunk($index, $startMs–$endMs ms)';
}

/// Plan de découpage d'un enregistrement.
class ChunkPlan {
  const ChunkPlan({required this.chunks, required this.silenceThreshold, required this.totalSamples});

  final List<AudioChunk> chunks;

  /// Niveau (RMS, échelle 16 bits) sous lequel un frame est considéré comme du silence.
  final double silenceThreshold;
  final int totalSamples;
}

/// Calcule l'énergie (RMS) de chaque frame de 100 ms à partir d'échantillons.
Float32List energyFromSamples(Int16List samples) {
  final frames = (samples.length + kFrameSamples - 1) ~/ kFrameSamples;
  final rms = Float32List(frames);
  for (var f = 0; f < frames; f++) {
    final start = f * kFrameSamples;
    final end = math.min(start + kFrameSamples, samples.length);
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      final v = samples[i].toDouble();
      sum += v * v;
    }
    rms[f] = math.sqrt(sum / (end - start));
  }
  return rms;
}

/// Parcourt un fichier WAV par blocs et calcule l'énergie par frame.
Float32List energyFromWav(WavReader reader) {
  final frames = (reader.sampleCount + kFrameSamples - 1) ~/ kFrameSamples;
  final rms = Float32List(frames);
  const framesPerBlock = 160; // 16 s par lecture
  var frame = 0;
  while (frame < frames) {
    final blockFrames = math.min(framesPerBlock, frames - frame);
    final samples = reader.read(frame * kFrameSamples, blockFrames * kFrameSamples);
    final partial = energyFromSamples(samples);
    for (var i = 0; i < partial.length && frame + i < frames; i++) {
      rms[frame + i] = partial[i];
    }
    frame += blockFrames;
  }
  return rms;
}

/// Seuil de silence adapté à l'enregistrement : au-dessus du bruit de fond,
/// en dessous de la parole.
double silenceThreshold(Float32List rms) {
  if (rms.isEmpty) return 50;
  final sorted = List<double>.from(rms)..sort();
  final p10 = sorted[(sorted.length * 0.10).floor()];
  final median = sorted[sorted.length ~/ 2];
  var threshold = p10 * 2.5;
  if (threshold < 50) threshold = 50;
  final cap = median * 0.4;
  if (cap > 50 && threshold > cap) threshold = cap;
  return threshold;
}

/// Découpe l'enregistrement en morceaux de 10 à 28 secondes, en coupant autant que
/// possible dans un silence. Si [skipSilence] est vrai, les morceaux entièrement
/// silencieux sont ignorés (leurs temps restent corrects, car chaque morceau
/// garde sa position dans l'enregistrement d'origine).
ChunkPlan planChunks(
  Float32List rms,
  int totalSamples, {
  bool skipSilence = false,
  int minFrames = kMinChunkFrames,
  int maxFrames = kMaxChunkFrames,
}) {
  final threshold = silenceThreshold(rms);
  if (totalSamples <= 0 || rms.isEmpty) {
    return ChunkPlan(chunks: const <AudioChunk>[], silenceThreshold: threshold, totalSamples: 0);
  }
  final bounds = <int>[0]; // positions de coupe, en échantillons
  var startFrame = 0;
  while (rms.length - startFrame > maxFrames) {
    var best = startFrame + minFrames;
    var bestValue = rms[best];
    for (var f = startFrame + minFrames; f <= startFrame + maxFrames; f++) {
      if (rms[f] <= bestValue) {
        best = f;
        bestValue = rms[f];
      }
    }
    bounds.add(best * kFrameSamples + kFrameSamples ~/ 2);
    startFrame = best;
  }
  bounds.add(totalSamples);

  final chunks = <AudioChunk>[];
  for (var i = 0; i + 1 < bounds.length; i++) {
    final start = bounds[i];
    final end = bounds[i + 1];
    if (end <= start) continue;
    if (skipSilence && _isSilent(rms, start, end, threshold)) continue;
    chunks.add(AudioChunk(index: chunks.length, startSample: start, endSample: end));
  }
  return ChunkPlan(chunks: chunks, silenceThreshold: threshold, totalSamples: totalSamples);
}

bool _isSilent(Float32List rms, int startSample, int endSample, double threshold) {
  final first = startSample ~/ kFrameSamples;
  final last = math.min(rms.length, (endSample + kFrameSamples - 1) ~/ kFrameSamples);
  final total = last - first;
  if (total <= 0) return true;
  var active = 0;
  for (var f = first; f < last; f++) {
    if (rms[f] >= threshold) active++;
  }
  return active / total < 0.02;
}

/// Calcule le plan d'un fichier WAV dans un isolate séparé (lecture du fichier entier).
Future<ChunkPlan> planChunksForWav(String wavPath, {bool skipSilence = false}) {
  return Isolate.run<ChunkPlan>(() {
    final reader = WavReader.open(wavPath);
    try {
      final rms = energyFromWav(reader);
      return planChunks(rms, reader.sampleCount, skipSilence: skipSilence);
    } finally {
      reader.close();
    }
  });
}
