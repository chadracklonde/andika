import 'dart:io';
import 'dart:typed_data';

/// Lecture d'un fichier WAV PCM 16 bits mono 16 kHz écrit par Andika
/// (en-tête fixe de 44 octets, voir WavWriter.kt).
class WavReader {
  WavReader._(this.path, this._file, this.sampleCount);

  static const int headerSize = 44;
  static const int sampleRate = 16000;

  final String path;
  final RandomAccessFile _file;

  /// Nombre d'échantillons (un par 1/16 000 de seconde).
  final int sampleCount;

  int get durationMs => sampleCount * 1000 ~/ sampleRate;

  /// Ouvre et vérifie l'en-tête. Lève [FormatException] si le fichier n'est pas
  /// un WAV 16 kHz mono 16 bits.
  static WavReader open(String path) {
    final file = File(path).openSync();
    try {
      final header = Uint8List(headerSize);
      final read = file.readIntoSync(header);
      if (read < headerSize) {
        throw const FormatException('Fichier audio trop court');
      }
      final info = parseHeader(header);
      final length = file.lengthSync();
      // Un fichier tronqué (arrêt brutal) : on se limite à ce qui est présent.
      final available = (length - headerSize) ~/ 2;
      final count = info < available ? info : available;
      return WavReader._(path, file, count < 0 ? 0 : count);
    } catch (_) {
      file.closeSync();
      rethrow;
    }
  }

  /// Vérifie un en-tête de 44 octets et retourne le nombre d'échantillons annoncé.
  static int parseHeader(Uint8List header) {
    if (header.length < headerSize) {
      throw const FormatException('En-tête WAV incomplet');
    }
    final data = ByteData.sublistView(header);
    String tag(int offset) => String.fromCharCodes(header.sublist(offset, offset + 4));
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE' || tag(12) != 'fmt ' || tag(36) != 'data') {
      throw const FormatException('Ce fichier n\'est pas un WAV Andika');
    }
    final format = data.getUint16(20, Endian.little);
    final channels = data.getUint16(22, Endian.little);
    final rate = data.getUint32(24, Endian.little);
    final bits = data.getUint16(34, Endian.little);
    if (format != 1 || channels != 1 || rate != sampleRate || bits != 16) {
      throw const FormatException('Format WAV inattendu (16 kHz, mono, 16 bits requis)');
    }
    return data.getUint32(40, Endian.little) ~/ 2;
  }

  /// Construit un en-tête de 44 octets pour [sampleCount] échantillons (utile aux tests).
  static Uint8List buildHeader(int sampleCount) {
    final bytes = Uint8List(headerSize);
    final data = ByteData.sublistView(bytes);
    void put(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes[offset + i] = text.codeUnitAt(i);
      }
    }

    final dataBytes = sampleCount * 2;
    put(0, 'RIFF');
    data.setUint32(4, 36 + dataBytes, Endian.little);
    put(8, 'WAVE');
    put(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    put(36, 'data');
    data.setUint32(40, dataBytes, Endian.little);
    return bytes;
  }

  /// Lit [count] échantillons à partir de [start] (moins s'il n'y en a plus assez).
  Int16List read(int start, int count) {
    if (start < 0 || start >= sampleCount || count <= 0) return Int16List(0);
    final wanted = (start + count > sampleCount) ? sampleCount - start : count;
    _file.setPositionSync(headerSize + start * 2);
    final bytes = Uint8List(wanted * 2);
    final got = _file.readIntoSync(bytes);
    final samples = got ~/ 2;
    return Int16List.view(bytes.buffer, 0, samples);
  }

  void close() => _file.closeSync();
}
