import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:andika/export/docx.dart';
import 'package:andika/export/exporters.dart';
import 'package:andika/transcription/transcript.dart';

/// Lecteur ZIP minimal pour vérifier l'archive : retourne nom -> contenu,
/// en contrôlant les en-têtes, les tailles et les CRC.
Map<String, Uint8List> readZip(Uint8List zip) {
  final d = ByteData.sublistView(zip);
  // Fin du répertoire central : dernier octets, sans commentaire.
  final eocd = zip.length - 22;
  expect(d.getUint32(eocd, Endian.little), 0x06054b50);
  final count = d.getUint16(eocd + 10, Endian.little);
  final centralSize = d.getUint32(eocd + 12, Endian.little);
  final centralOffset = d.getUint32(eocd + 16, Endian.little);
  expect(centralOffset + centralSize, eocd);
  final files = <String, Uint8List>{};
  var p = centralOffset;
  for (var i = 0; i < count; i++) {
    expect(d.getUint32(p, Endian.little), 0x02014b50);
    final method = d.getUint16(p + 10, Endian.little);
    final crc = d.getUint32(p + 16, Endian.little);
    final size = d.getUint32(p + 24, Endian.little);
    final nameLen = d.getUint16(p + 28, Endian.little);
    final extraLen = d.getUint16(p + 30, Endian.little);
    final commentLen = d.getUint16(p + 32, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    final name = utf8.decode(zip.sublist(p + 46, p + 46 + nameLen));
    expect(method, 0);
    // En-tête local cohérent avec le répertoire central.
    expect(d.getUint32(local, Endian.little), 0x04034b50);
    expect(d.getUint32(local + 14, Endian.little), crc);
    final localNameLen = d.getUint16(local + 26, Endian.little);
    final localExtra = d.getUint16(local + 28, Endian.little);
    final start = local + 30 + localNameLen + localExtra;
    final data = Uint8List.sublistView(zip, start, start + size);
    expect(crc32(data), crc, reason: name);
    files[name] = data;
    p += 46 + nameLen + extraLen + commentLen;
  }
  expect(p, centralOffset + centralSize);
  return files;
}

const segments = <Segment>[
  Segment(startMs: 0, endMs: 4000, text: 'Bonjour à tous & bienvenue.'),
  Segment(startMs: 4000, endMs: 9000, text: 'On parle du <Parc National> de la Lomami.'),
  Segment(startMs: 65000, endMs: 70000, text: '  Merci.  '),
];

void main() {
  test('CRC-32 : valeur de référence', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    expect(crc32(<int>[]), 0);
  });

  test('ZIP : entrées relues à l\'identique', () {
    final zip = buildZip(<MapEntry<String, Uint8List>>[
      MapEntry<String, Uint8List>('a.txt', Uint8List.fromList(utf8.encode('Bonjour'))),
      MapEntry<String, Uint8List>('dossier/é.txt', Uint8List.fromList(utf8.encode('Éléphant'))),
      MapEntry<String, Uint8List>('vide.txt', Uint8List(0)),
    ]);
    final files = readZip(zip);
    expect(files.keys, <String>['a.txt', 'dossier/é.txt', 'vide.txt']);
    expect(utf8.decode(files['dossier/é.txt']!), 'Éléphant');
    expect(files['vide.txt'], isEmpty);
  });

  test('XML : caractères spéciaux échappés, caractères interdits retirés', () {
    expect(xmlEscape('a & b < c > "d"'), 'a &amp; b &lt; c &gt; &quot;d&quot;');
    expect(xmlEscape('a\u0000b\u0008c\td'), 'abc\td');
    expect(xmlEscape('Été 😀'), 'Été 😀');
  });

  test('paragraphes : regroupés à la fin d\'une phrase', () {
    final long = <Segment>[
      for (var i = 0; i < 12; i++)
        Segment(startMs: i * 1000, endMs: i * 1000 + 900, text: 'Une phrase assez longue pour le test numéro $i.'),
    ];
    final paragraphs = groupParagraphs(long, target: 100);
    expect(paragraphs.length, greaterThan(1));
    expect(paragraphs.every((p) => p.endsWith('.')), isTrue);
    expect(paragraphs.join(' '), long.map((s) => s.text).join(' '));
    expect(groupParagraphs(const <Segment>[]), isEmpty);
  });

  test('DOCX : structure et contenu', () {
    final bytes = buildDocx(title: 'Entretien <Lomami>', segments: segments, subtitle: '18/11/2026 · 1 min');
    final files = readZip(bytes);
    expect(files.keys, containsAll(<String>[
      '[Content_Types].xml',
      '_rels/.rels',
      'word/document.xml',
      'word/_rels/document.xml.rels',
      'word/styles.xml',
    ]));
    final doc = utf8.decode(files['word/document.xml']!);
    expect(doc, contains('Entretien &lt;Lomami&gt;'));
    expect(doc, contains('Bonjour à tous &amp; bienvenue.'));
    expect(doc, contains('&lt;Parc National&gt;'));
    expect(doc, contains('w:pStyle w:val="Title"'));
    expect(doc, contains('w:pStyle w:val="Subtitle"'));
    expect(doc.startsWith('<?xml'), isTrue);
    expect(doc.endsWith('</w:document>'), isTrue);
    // Tout le contenu du fichier est du XML bien formé (balises équilibrées).
    for (final entry in files.entries) {
      final text = utf8.decode(entry.value);
      final opens = RegExp(r'<(?![/?!])[^>]*[^/]>').allMatches(text).length;
      final closes = RegExp(r'</[^>]+>').allMatches(text).length;
      expect(opens, closes, reason: entry.key);
    }
  });

  test('DOCX : horodatages, un paragraphe par segment', () {
    final doc = utf8.decode(
        readZip(buildDocx(title: 'T', segments: segments, timestamps: true))['word/document.xml']!);
    expect('<w:p>'.allMatches(doc).length, 1 + 3); // titre + 3 segments
    expect(doc, contains('[0:00] '));
    expect(doc, contains('[1:05] '));
    expect(doc, contains('>Merci.<')); // texte rogné
  });

  test('DOCX : texte vide, document tout de même valide', () {
    final files = readZip(buildDocx(title: 'Vide', segments: const <Segment>[]));
    expect(utf8.decode(files['word/document.xml']!), contains('Vide'));
  });

  test('export : formats, extensions et types', () {
    expect(exportExtension(ExportFormat.docx), 'docx');
    expect(exportMime(ExportFormat.docx), contains('wordprocessingml'));
    final txt = exportBytes(segments, ExportFormat.txt);
    expect(utf8.decode(txt), toPlainText(segments));
    final docx = exportBytes(segments, ExportFormat.docx, title: 'T');
    expect(docx.sublist(0, 2), <int>[0x50, 0x4B]); // « PK »
  });

  test('échantillon DOCX pour contrôle externe (CI)', () {
    final dir = Platform.environment['ANDIKA_SAMPLE_DIR'];
    if (dir == null || dir.isEmpty) return;
    Directory(dir).createSync(recursive: true);
    File('$dir/echantillon.docx').writeAsBytesSync(buildDocx(
      title: 'Entretien — Parc National de la Lomami',
      segments: <Segment>[
        for (var i = 0; i < 40; i++)
          Segment(
            startMs: i * 7000,
            endMs: i * 7000 + 6500,
            text: 'Segment numéro $i : le parc & ses « habitants » <test> déjà là.',
          ),
      ],
      subtitle: '18/11/2026 11:30 · 5 min',
    ));
    File('$dir/echantillon-horodate.docx').writeAsBytesSync(buildDocx(
      title: 'Horodaté',
      segments: segments,
      timestamps: true,
    ));
  });
}
