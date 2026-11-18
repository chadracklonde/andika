import 'dart:convert';
import 'dart:io';

import '../transcription/segment_log.dart';
import '../transcription/transcript.dart';
import 'job.dart';

/// Historique des transcriptions, en fichiers dans le dossier privé de l'application :
///   jobs/<id>/job.json         fiche
///   jobs/<id>/segments.jsonl   journal brut de la transcription (reprise)
///   jobs/<id>/transcript.json  texte relu et corrigé
///   audio/<id>.wav             audio de travail (supprimable)
class JobStore {
  JobStore(this.filesDir);

  final String filesDir;

  Directory get _jobsDir => Directory('$filesDir/jobs');
  Directory _dir(String id) => Directory('${_jobsDir.path}/$id');
  File _jobFile(String id) => File('${_dir(id).path}/job.json');
  File _transcriptFile(String id) => File('${_dir(id).path}/transcript.json');

  String logPath(String id) => '${_dir(id).path}/segments.jsonl';
  String audioPath(String id) => '$filesDir/audio/$id.wav';

  SegmentLog log(String id) => SegmentLog(logPath(id));

  /// Identifiant unique, trié par date.
  String newId([DateTime? now]) {
    final t = (now ?? DateTime.now()).toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    var id = stamp;
    var n = 1;
    while (_dir(id).existsSync()) {
      id = '$stamp-$n';
      n++;
    }
    return id;
  }

  void save(Job job) {
    _dir(job.id).createSync(recursive: true);
    final tmp = File('${_jobFile(job.id).path}.tmp');
    tmp.writeAsStringSync(jsonEncode(job.toJson()), flush: true);
    tmp.renameSync(_jobFile(job.id).path); // écriture atomique
  }

  Job? load(String id) {
    final f = _jobFile(id);
    if (!f.existsSync()) return null;
    try {
      return Job.fromJson((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Toutes les transcriptions, la plus récente d'abord.
  List<Job> list() {
    if (!_jobsDir.existsSync()) return <Job>[];
    final jobs = <Job>[];
    for (final entity in _jobsDir.listSync()) {
      if (entity is! Directory) continue;
      final job = load(entity.uri.pathSegments.where((s) => s.isNotEmpty).last);
      if (job != null) jobs.add(job);
    }
    jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return jobs;
  }

  /// Au démarrage : une transcription restée « en cours » est en réalité interrompue.
  int markInterrupted() {
    var n = 0;
    for (final job in list()) {
      if (job.status == JobStatus.running) {
        save(job.copyWith(status: JobStatus.interrupted));
        n++;
      }
    }
    return n;
  }

  /// Texte à afficher : la version relue si elle existe, sinon le journal brut.
  List<Segment> loadTranscript(String id) {
    final f = _transcriptFile(id);
    if (f.existsSync()) {
      try {
        final list = jsonDecode(f.readAsStringSync()) as List<Object?>;
        return list.map((e) => Segment.fromJson((e as Map).cast<String, Object?>())).toList();
      } on FormatException {
        // fichier abîmé : on retombe sur le journal
      } on TypeError {
        // idem
      }
    }
    return log(id).allSegments();
  }

  void saveTranscript(String id, List<Segment> segments) {
    _dir(id).createSync(recursive: true);
    final tmp = File('${_transcriptFile(id).path}.tmp');
    tmp.writeAsStringSync(jsonEncode(segments.map((s) => s.toJson()).toList()), flush: true);
    tmp.renameSync(_transcriptFile(id).path);
  }

  /// Libère l'espace de l'audio en gardant le texte.
  void deleteAudio(String id) {
    final a = File(audioPath(id));
    if (a.existsSync()) a.deleteSync();
    final job = load(id);
    if (job != null && job.hasAudio) save(job.copyWith(hasAudio: false));
  }

  /// Supprime la transcription, son texte et son audio.
  void delete(String id) {
    final a = File(audioPath(id));
    if (a.existsSync()) a.deleteSync();
    final d = _dir(id);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  /// Espace occupé par l'audio de travail.
  int audioBytes() {
    final dir = Directory('$filesDir/audio');
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final e in dir.listSync()) {
      if (e is File) total += e.lengthSync();
    }
    return total;
  }
}
