import 'dart:convert';
import 'dart:typed_data';

import '../transcription/transcript.dart';
import 'exporters.dart';

/// Export Word (.docx) en Dart pur : un DOCX est une archive ZIP de fichiers XML.
/// L'archive est écrite sans compression (méthode « stored »), ce qui évite toute
/// dépendance et reste valide pour Word, LibreOffice et Google Docs.

// --- ZIP ----------------------------------------------------------------------

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// Somme de contrôle CRC-32 (celle des fichiers ZIP).
int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Date DOS fixe (1er janvier 2026) : l'archive est identique d'un export à l'autre.
const int _dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1;
const int _dosTime = 0;

/// Construit une archive ZIP sans compression. Les entrées gardent l'ordre donné.
Uint8List buildZip(List<MapEntry<String, Uint8List>> entries) {
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;

  void u16(BytesBuilder b, int v) => b.add(<int>[v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) =>
      b.add(<int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  for (final entry in entries) {
    final name = utf8.encode(entry.key);
    final data = entry.value;
    final crc = crc32(data);
    // En-tête local
    u32(out, 0x04034b50);
    u16(out, 20); // version nécessaire
    u16(out, 0x0800); // noms en UTF-8
    u16(out, 0); // stored
    u16(out, _dosTime);
    u16(out, _dosDate);
    u32(out, crc);
    u32(out, data.length);
    u32(out, data.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(data);
    // Répertoire central
    u32(central, 0x02014b50);
    u16(central, 20); // créé par
    u16(central, 20); // version nécessaire
    u16(central, 0x0800);
    u16(central, 0);
    u16(central, _dosTime);
    u16(central, _dosDate);
    u32(central, crc);
    u32(central, data.length);
    u32(central, data.length);
    u16(central, name.length);
    u16(central, 0); // extra
    u16(central, 0); // commentaire
    u16(central, 0); // disque
    u16(central, 0); // attributs internes
    u32(central, 0); // attributs externes
    u32(central, offset);
    central.add(name);
    offset += 30 + name.length + data.length;
  }
  final centralBytes = central.toBytes();
  out.add(centralBytes);
  // Fin du répertoire central
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, entries.length);
  u16(out, entries.length);
  u32(out, centralBytes.length);
  u32(out, offset);
  u16(out, 0);
  return out.toBytes();
}

// --- XML ----------------------------------------------------------------------

/// Échappe le texte pour XML et retire les caractères que XML 1.0 interdit.
String xmlEscape(String text) {
  final b = StringBuffer();
  for (final r in text.runes) {
    final ok = r == 0x9 ||
        r == 0xA ||
        r == 0xD ||
        (r >= 0x20 && r <= 0xD7FF) ||
        (r >= 0xE000 && r <= 0xFFFD) ||
        (r >= 0x10000 && r <= 0x10FFFF);
    if (!ok) continue;
    switch (r) {
      case 0x26:
        b.write('&amp;');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x22:
        b.write('&quot;');
      default:
        b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// Regroupe les segments en paragraphes lisibles : on change de paragraphe à la fin
/// d'une phrase une fois qu'environ [target] caractères sont accumulés.
List<String> groupParagraphs(List<Segment> segments, {int target = 400}) {
  final paragraphs = <String>[];
  var current = StringBuffer();
  for (final seg in segments) {
    final text = seg.text.trim();
    if (text.isEmpty) continue;
    if (current.isNotEmpty) current.write(' ');
    current.write(text);
    final soFar = current.toString();
    if (soFar.length >= target && RegExp(r'[.!?…»]$').hasMatch(text)) {
      paragraphs.add(soFar);
      current = StringBuffer();
    }
  }
  if (current.isNotEmpty) paragraphs.add(current.toString());
  return paragraphs;
}

String _run(String text, {bool bold = false}) =>
    '<w:r>${bold ? '<w:rPr><w:b/></w:rPr>' : ''}<w:t xml:space="preserve">${xmlEscape(text)}</w:t></w:r>';

String _paragraph(String runs, {String? style}) =>
    '<w:p>${style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>'}$runs</w:p>';

String _documentXml({
  required String title,
  required List<Segment> segments,
  required bool timestamps,
  String subtitle = '',
}) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>')
    ..write(_paragraph(_run(title), style: 'Title'));
  if (subtitle.trim().isNotEmpty) {
    b.write(_paragraph(_run(subtitle), style: 'Subtitle'));
  }
  if (timestamps) {
    for (final seg in segments) {
      final text = seg.text.trim();
      if (text.isEmpty) continue;
      b.write(_paragraph('${_run('[${clockTime(seg.startMs)}] ', bold: true)}${_run(text)}'));
    }
  } else {
    for (final p in groupParagraphs(segments)) {
      b.write(_paragraph(_run(p)));
    }
  }
  // Page A4, marges de 2,5 cm.
  b.write('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" '
      'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>');
  b.write('</w:body></w:document>');
  return b.toString();
}

const String _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>';

const String _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/></Relationships>';

const String _documentRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
    'Target="styles.xml"/></Relationships>';

const String _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri" w:eastAsia="Calibri"/>'
    '<w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="fr-FR"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
    '</w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/>'
    '<w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="120"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/>'
    '<w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="240"/></w:pPr>'
    '<w:rPr><w:i/><w:color w:val="595959"/></w:rPr></w:style>'
    '</w:styles>';

/// Document Word de la transcription : titre, ligne d'information facultative,
/// puis le texte (paragraphes, ou un paragraphe horodaté par segment).
Uint8List buildDocx({
  required String title,
  required List<Segment> segments,
  bool timestamps = false,
  String subtitle = '',
}) {
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
  return buildZip(<MapEntry<String, Uint8List>>[
    MapEntry<String, Uint8List>('[Content_Types].xml', bytes(_contentTypes)),
    MapEntry<String, Uint8List>('_rels/.rels', bytes(_rootRels)),
    MapEntry<String, Uint8List>(
      'word/document.xml',
      bytes(_documentXml(title: title, segments: segments, timestamps: timestamps, subtitle: subtitle)),
    ),
    MapEntry<String, Uint8List>('word/_rels/document.xml.rels', bytes(_documentRels)),
    MapEntry<String, Uint8List>('word/styles.xml', bytes(_styles)),
  ]);
}
