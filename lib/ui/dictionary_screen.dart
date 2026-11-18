import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../extras/replacements.dart';

/// Dictionnaire de remplacement : ajout, modification, suppression.
class DictionaryScreen extends StatelessWidget {
  const DictionaryScreen({super.key, required this.controller});

  final AppController controller;

  Future<void> _edit(BuildContext context, {int? index}) async {
    final s = controller.strings;
    final existing = index == null ? null : controller.replacements[index];
    final from = TextEditingController(text: existing?.from ?? '');
    final to = TextEditingController(text: existing?.to ?? '');
    var matchCase = existing?.matchCase ?? false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? s.t('add_rule') : s.t('edit_rule')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                  controller: from,
                  autofocus: true,
                  decoration: InputDecoration(labelText: s.t('rule_from'))),
              TextField(controller: to, decoration: InputDecoration(labelText: s.t('rule_to'))),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: matchCase,
                onChanged: (v) => setState(() => matchCase = v ?? false),
                title: Text(s.t('match_case')),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
          ],
        ),
      ),
    );
    final fromText = from.text.trim();
    final toText = to.text;
    from.dispose();
    to.dispose();
    if (saved != true || fromText.isEmpty) return;
    final rules = List<Replacement>.of(controller.replacements);
    final rule = Replacement(from: fromText, to: toText, matchCase: matchCase);
    if (index == null) {
      rules.add(rule);
    } else {
      rules[index] = rule;
    }
    controller.saveReplacements(rules);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.strings;
        final rules = controller.replacements;
        return Scaffold(
          appBar: AppBar(title: Text(s.t('dictionary'))),
          floatingActionButton: FloatingActionButton(
            tooltip: s.t('add_rule'),
            onPressed: () => _edit(context),
            child: const Icon(Icons.add),
          ),
          body: rules.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(s.t('dictionary_empty'), textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  itemCount: rules.length,
                  itemBuilder: (context, i) {
                    final r = rules[i];
                    return ListTile(
                      title: Text('${r.from}  →  ${r.to}'),
                      subtitle: r.matchCase ? Text(s.t('match_case')) : null,
                      onTap: () => _edit(context, index: i),
                      trailing: IconButton(
                        tooltip: s.t('delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          final next = List<Replacement>.of(rules)..removeAt(i);
                          controller.saveReplacements(next);
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
