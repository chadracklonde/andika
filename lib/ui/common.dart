import 'package:flutter/material.dart';

import '../app/controller.dart';

/// Taille lisible d'un fichier (« 142 Mo »).
String formatBytes(int bytes, {String mb = 'Mo', String gb = 'Go'}) {
  if (bytes >= 1000 * 1000 * 1000) {
    return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(1)} $gb';
  }
  return '${(bytes / (1000 * 1000)).round()} $mb';
}

/// Durée lisible : « 1 h 05 », « 12 min », « 45 s ».
String formatDuration(int ms) {
  final totalSeconds = ms ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')}';
  if (m > 0) return '$m min';
  return '$s s';
}

String formatDate(DateTime utc) {
  final d = utc.toLocal();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
}

/// Affiche un message court en bas de l'écran.
void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Demande une confirmation ; retourne vrai si l'utilisateur accepte.
Future<bool> confirm(
  BuildContext context,
  AppController c, {
  required String title,
  required String message,
  required String action,
}) async {
  final s = c.strings;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return result ?? false;
}
