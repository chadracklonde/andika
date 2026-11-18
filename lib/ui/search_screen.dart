import 'dart:async';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../export/exporters.dart';
import '../export/search.dart';
import '../transcription/transcript.dart';
import 'result_screen.dart';

/// Recherche d'un mot, d'un nom ou d'un lieu dans toutes les transcriptions.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  AppController get c => widget.controller;
  final TextEditingController field = TextEditingController();
  Timer? _debounce;
  String query = '';
  List<HistoryHit> hits = <HistoryHit>[];

  /// Textes déjà lus : chaque transcription n'est lue qu'une fois par ouverture de l'écran.
  final Map<String, List<Segment>> _cache = <String, List<Segment>>{};

  static const int _maxHits = 200;

  @override
  void dispose() {
    _debounce?.cancel();
    field.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        query = text;
        hits = searchHistory(
          c.history,
          (id) => _cache.putIfAbsent(id, () => c.transcriptOf(id)),
          text,
          maxHits: _maxHits,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    final theme = Theme.of(context);
    final short = query.trim().length < 2;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: field,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: s.t('search_all_hint'), border: InputBorder.none),
          onChanged: _onChanged,
        ),
        actions: <Widget>[
          if (field.text.isNotEmpty)
            IconButton(
              tooltip: s.t('close'),
              icon: const Icon(Icons.close),
              onPressed: () {
                field.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: short
          ? Center(child: Text(s.t('search_all_start'), style: theme.textTheme.bodyLarge))
          : hits.isEmpty
              ? Center(child: Text(s.t('search_all_empty'), style: theme.textTheme.bodyLarge))
              : ListView.separated(
                  itemCount: hits.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      final limited = hits.length >= _maxHits;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          limited
                              ? s.t('search_all_limit', {'n': '$_maxHits'})
                              : s.t('search_all_count', {'n': '${hits.length}'}),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      );
                    }
                    final hit = hits[i - 1];
                    return ListTile(
                      title: Text(hit.job.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: hit.segmentIndex < 0
                          ? null
                          : Text.rich(
                              TextSpan(children: <InlineSpan>[
                                TextSpan(text: '${clockTime(hit.startMs)}  '),
                                TextSpan(text: hit.before),
                                TextSpan(
                                  text: hit.match,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    backgroundColor: theme.colorScheme.tertiaryContainer,
                                  ),
                                ),
                                TextSpan(text: hit.after),
                              ]),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ResultScreen(
                          controller: c,
                          jobId: hit.job.id,
                          initialQuery: query.trim(),
                          initialSegment: hit.segmentIndex < 0 ? 0 : hit.segmentIndex,
                        ),
                      )),
                    );
                  },
                ),
    );
  }
}
