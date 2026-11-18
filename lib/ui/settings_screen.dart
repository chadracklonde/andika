import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/settings.dart';
import 'common.dart';
import 'dictionary_screen.dart';

/// Réglages de l'application.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.strings;
        final st = controller.settings;
        final installed = controller.models.installedModels();
        final audioBytes = controller.jobs.audioBytes();
        return Scaffold(
          appBar: AppBar(title: Text(s.t('settings'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              DropdownButtonFormField<String>(
                value: st.uiLanguage,
                decoration: InputDecoration(labelText: s.t('ui_language'), border: const OutlineInputBorder()),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'system', child: Text(s.t('ui_system'))),
                  const DropdownMenuItem<String>(value: 'fr', child: Text('Français')),
                  const DropdownMenuItem<String>(value: 'en', child: Text('English')),
                ],
                onChanged: (v) => controller.updateSettings(st.copyWith(uiLanguage: v)),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: st.transcriptionLanguage,
                decoration: InputDecoration(
                    labelText: s.t('default_audio_language'), border: const OutlineInputBorder()),
                items: <DropdownMenuItem<String>>[
                  for (final l in kTranscriptionLanguages)
                    DropdownMenuItem<String>(
                        value: l.code, child: Text(l.code == 'auto' ? s.t('auto_detect') : l.name)),
                ],
                onChanged: (v) => controller.updateSettings(st.copyWith(transcriptionLanguage: v)),
              ),
              if (isLimitedQuality(st.transcriptionLanguage))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.t('warn_limited_language')),
                ),
              const SizedBox(height: 16),
              if (installed.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: installed.any((m) => m.id == st.modelId) ? st.modelId : installed.first.id,
                  decoration: InputDecoration(
                      labelText: s.t('default_model'), border: const OutlineInputBorder()),
                  items: <DropdownMenuItem<String>>[
                    for (final m in installed) DropdownMenuItem<String>(value: m.id, child: Text(m.label)),
                  ],
                  onChanged: (v) => controller.updateSettings(st.copyWith(modelId: v)),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('skip_silence')),
                subtitle: Text(s.t('skip_silence_desc')),
                value: st.skipSilence,
                onChanged: (v) => controller.updateSettings(st.copyWith(skipSilence: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('export_timestamps')),
                value: st.exportTimestamps,
                onChanged: (v) => controller.updateSettings(st.copyWith(exportTimestamps: v)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.spellcheck),
                title: Text(s.t('dictionary')),
                subtitle: Text(s.t('dictionary_desc')),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => DictionaryScreen(controller: controller))),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storage_outlined),
                title: Text(s.t('storage')),
                subtitle: Text(s.t('storage_audio', {
                  'size': formatBytes(audioBytes, mb: s.t('unit_mb'), gb: s.t('unit_gb')),
                })),
              ),
            ],
          ),
        );
      },
    );
  }
}
