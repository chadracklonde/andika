import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/settings.dart';
import '../models/model_catalog.dart';
import '../platform/platform_bridge.dart';
import '../recorder/recording.dart';
import '../transcription/battery_advice.dart';
import 'common.dart';
import 'models_screen.dart';
import 'progress_screen.dart';

/// Choix du fichier, de la langue et du modèle, puis lancement.
class NewTranscriptionScreen extends StatefulWidget {
  const NewTranscriptionScreen({super.key, required this.controller, this.initialFile, this.recording});

  final AppController controller;
  final PickedFile? initialFile;

  /// Enregistrement du dictaphone à transcrire (à la place d'un fichier importé).
  final Recording? recording;

  @override
  State<NewTranscriptionScreen> createState() => _NewTranscriptionScreenState();
}

class _NewTranscriptionScreenState extends State<NewTranscriptionScreen> {
  AppController get c => widget.controller;
  PickedFile? file;
  late String language;
  late String modelId;
  bool starting = false;

  @override
  void initState() {
    super.initState();
    file = widget.initialFile;
    language = c.settings.transcriptionLanguage;
    modelId = c.settings.modelId;
    final installed = c.models.installedModels();
    if (installed.isNotEmpty && !installed.any((m) => m.id == modelId)) {
      modelId = installed.first.id;
    }
  }

  Future<void> _pick() async {
    final picked = await c.pickAudio();
    if (picked != null && mounted) setState(() => file = picked);
  }

  Future<void> _start() async {
    final s = c.strings;
    final chosen = file;
    final model = modelById(modelId);
    final rec = widget.recording;
    if ((chosen == null && rec == null) || model == null || starting) return;
    setState(() => starting = true);
    try {
      var proceed = true;
      try {
        final battery = await PlatformBridge.instance.getBatteryInfo();
        final warnings = batteryWarnings(battery, audioMinutes: kLongJobMinutes);
        if (warnings.isNotEmpty && mounted) {
          final lines = warnings
              .map((w) => w == BatteryWarning.lowBattery ? s.t('warn_low_battery') : s.t('warn_power_save'))
              .join('\n\n');
          proceed = await confirm(context, c,
              title: s.t('battery_title'), message: lines, action: s.t('continue_anyway'));
        }
        if (proceed && !await PlatformBridge.instance.notificationsAllowed()) {
          await PlatformBridge.instance.requestNotifications();
        }
      } on PlatformFailure {
        // Ces contrôles sont un confort : on lance quand même.
      }
      if (!proceed || !mounted) return;
      if (c.busy) {
        // Une transcription tourne déjà : on met celle-ci en file d'attente.
        final title = rec != null ? rec.title : AppController.titleFromFileName(chosen!.name);
        c.enqueue(QueuedItem(
          title: title,
          language: language,
          modelId: model.id,
          file: rec == null ? chosen : null,
          recording: rec,
        ));
        if (mounted) {
          toast(context, s.t('queue_added'));
          Navigator.of(context).pop();
        }
        return;
      }
      final id = rec != null
          ? await c.startFromRecording(rec, language: language, model: model)
          : await c.startFromFile(chosen!, language: language, model: model);
      if (!mounted) return;
      // Même en cas d'échec d'import, l'écran de progression affiche l'erreur.
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ProgressScreen(controller: c, openResultWhenDone: id != null),
      ));
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    final installed = c.models.installedModels();
    final model = modelById(modelId);
    final fit = model == null ? ModelFit.good : modelFit(model, c.totalRamBytes);
    final canStart = (file != null || widget.recording != null) &&
        model != null &&
        c.models.isInstalled(model) &&
        fit != ModelFit.tooHeavy &&
        !starting;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.recording != null ? s.t('rec_transcribe_title') : s.t('new_transcription'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (widget.recording != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.mic_none),
                title: Text(widget.recording!.title),
                subtitle: Text(formatDuration(widget.recording!.durationMs)),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.audio_file_outlined),
                title: Text(file?.name ?? s.t('no_file')),
                subtitle: file == null || file!.size < 0
                    ? null
                    : Text(formatBytes(file!.size, mb: s.t('unit_mb'), gb: s.t('unit_gb'))),
                trailing: TextButton(
                  onPressed: _pick,
                  child: Text(file == null ? s.t('choose_file') : s.t('change_file')),
                ),
              ),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: language,
            decoration: InputDecoration(labelText: s.t('audio_language'), border: const OutlineInputBorder()),
            items: <DropdownMenuItem<String>>[
              for (final l in kTranscriptionLanguages)
                DropdownMenuItem<String>(
                  value: l.code,
                  child: Text(l.code == 'auto' ? s.t('auto_detect') : l.name),
                ),
            ],
            onChanged: (v) => setState(() => language = v ?? 'auto'),
          ),
          if (isLimitedQuality(language))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _Notice(icon: Icons.info_outline, text: s.t('warn_limited_language')),
            ),
          const SizedBox(height: 16),
          if (installed.isEmpty) ...<Widget>[
            _Notice(icon: Icons.download_outlined, text: s.t('no_model_installed')),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () async {
                await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => ModelsScreen(controller: c)));
                if (mounted) setState(() {});
              },
              child: Text(s.t('get_model')),
            ),
          ] else
            DropdownButtonFormField<String>(
              value: modelId,
              decoration: InputDecoration(labelText: s.t('model'), border: const OutlineInputBorder()),
              items: <DropdownMenuItem<String>>[
                for (final m in installed) DropdownMenuItem<String>(value: m.id, child: Text(m.label)),
              ],
              onChanged: (v) => setState(() => modelId = v ?? modelId),
            ),
          if (fit == ModelFit.tight)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _Notice(icon: Icons.memory, text: s.t('warn_model_tight')),
            ),
          if (fit == ModelFit.tooHeavy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _Notice(icon: Icons.block, text: s.t('warn_model_too_heavy')),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: canStart ? _start : null,
            icon: Icon(c.busy ? Icons.playlist_add : Icons.play_arrow),
            label: Text(c.busy ? s.t('queue_add') : s.t('start')),
          ),
          const SizedBox(height: 24),
          Text(s.t('tips_title'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final key in const <String>['tip_1', 'tip_2', 'tip_3', 'tip_4'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${s.t(key)}'),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
