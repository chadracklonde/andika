import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../audio/chunk_planner.dart';
import '../audio/wav_file.dart';
import '../engine/native_lib.dart';
import '../engine/whisper_engine.dart';
import 'segment_log.dart';
import 'transcript.dart';

/// Demande envoyée au worker.
class WorkerRequest {
  WorkerRequest({
    required this.wavPath,
    required this.logPath,
    required this.options,
    required this.events,
  });

  final String wavPath;
  final String logPath;
  final TranscriptionOptions options;
  final SendPort events;
}

/// Messages du worker vers l'application (types simples, transmissibles).
/// `{'type': 'loaded', 'address': int}`
/// `{'type': 'plan', 'total': int, 'done': int}`
/// `{'type': 'chunk', 'index': int, 'done': int, 'total': int, 'positionMs': int}`
/// `{'type': 'done'}` · `{'type': 'cancelled'}` · `{'type': 'error', 'message': String}`
void transcriptionWorkerMain(WorkerRequest request) {
  final out = request.events;
  WhisperEngine? engine;
  WavReader? reader;
  try {
    engine = WhisperEngine.load(request.options.modelPath);
    out.send(<String, Object?>{'type': 'loaded', 'address': engine.address});
    engine.resetCancel();

    reader = WavReader.open(request.wavPath);
    final rms = energyFromWav(reader);
    final plan = planChunks(rms, reader.sampleCount, skipSilence: request.options.skipSilence);
    final log = SegmentLog(request.logPath);
    final already = log.completedChunks();
    var done = already.length;
    out.send(<String, Object?>{'type': 'plan', 'total': plan.chunks.length, 'done': done});

    for (final chunk in plan.chunks) {
      if (already.contains(chunk.index)) continue;
      final Int16List pcm = reader.read(chunk.startSample, chunk.sampleCount);
      final result = engine.transcribe(
        pcm,
        language: request.options.language,
        threads: request.options.threads,
      );
      if (result.cancelled) {
        out.send(<String, Object?>{'type': 'cancelled'});
        return;
      }
      final offset = chunk.startMs;
      final segments = result.segments
          .map((s) => Segment(startMs: offset + s.startMs, endMs: offset + s.endMs, text: s.text))
          .toList();
      log.append(ChunkRecord(index: chunk.index, language: result.language, segments: segments));
      done++;
      out.send(<String, Object?>{
        'type': 'chunk',
        'index': chunk.index,
        'done': done,
        'total': plan.chunks.length,
        'positionMs': chunk.endMs,
      });
    }
    out.send(<String, Object?>{'type': 'done'});
  } on EngineException catch (e) {
    out.send(<String, Object?>{'type': 'error', 'message': e.message});
  } on FormatException catch (e) {
    out.send(<String, Object?>{'type': 'error', 'message': e.message});
  } catch (e) {
    out.send(<String, Object?>{'type': 'error', 'message': e.toString()});
  } finally {
    reader?.close();
    engine?.dispose();
  }
}
