import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../models/model_catalog.dart';
import 'common.dart';

/// Liste des modèles : téléchargement, suppression, choix du modèle par défaut.
class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.strings;
        final ram = controller.totalRamBytes;
        final recommended = recommendedModel(ram);
        return Scaffold(
          appBar: AppBar(title: Text(s.t('models'))),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(s.t('models_intro')),
              ),
              for (final m in kModelCatalog)
                _ModelCard(controller: controller, model: m, recommended: m.id == recommended.id),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(s.t('models_used', {
                  'size': formatBytes(controller.models.usedBytes(),
                      mb: s.t('unit_mb'), gb: s.t('unit_gb')),
                })),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.controller, required this.model, required this.recommended});

  final AppController controller;
  final WhisperModel model;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final s = controller.strings;
    final installed = controller.models.isInstalled(model);
    final download = controller.downloads[model.id];
    final fit = modelFit(model, controller.totalRamBytes);
    final isDefault = controller.settings.modelId == model.id;
    final size = formatBytes(model.approxBytes, mb: s.t('unit_mb'), gb: s.t('unit_gb'));
    final partial = controller.models.partialBytes(model);

    Widget trailing;
    if (download != null && download.errorKey == null) {
      trailing = TextButton(
        onPressed: () => controller.cancelModelDownload(model),
        child: Text(s.t('cancel')),
      );
    } else if (installed) {
      trailing = IconButton(
        tooltip: s.t('delete'),
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          final ok = await confirm(context, controller,
              title: s.t('delete_model'),
              message: s.t('delete_model_msg', {'name': model.label}),
              action: s.t('delete'));
          if (ok) controller.deleteModel(model);
        },
      );
    } else {
      trailing = FilledButton.tonal(
        onPressed: fit == ModelFit.tooHeavy ? null : () => controller.downloadModel(model),
        child: Text(partial > 0 ? s.t('resume') : s.t('download')),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${model.label} · $size${recommended ? ' · ${s.t('recommended')}' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                trailing,
              ],
            ),
            Text('${s.t('speed_label')} ${'●' * model.speedRating}${'○' * (5 - model.speedRating)}  '
                '${s.t('quality_label')} ${'●' * model.qualityRating}${'○' * (5 - model.qualityRating)}'),
            if (model.quantized) Text(s.t('model_light_note')),
            if (model.experimental) Text(s.t('model_experimental_note')),
            if (fit == ModelFit.tight) Text(s.t('warn_model_tight')),
            if (fit == ModelFit.tooHeavy) Text(s.t('warn_model_too_heavy')),
            if (download != null && download.errorKey == null) ...<Widget>[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: download.verifying ? null : download.fraction),
              Text(download.verifying
                  ? s.t('verifying')
                  : s.t('downloading', {'n': '${((download.fraction ?? 0) * 100).floor()}'})),
            ],
            if (download?.errorKey != null)
              Text(s.t(download!.errorKey!), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (installed)
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: true,
                groupValue: isDefault,
                onChanged: (_) =>
                    controller.updateSettings(controller.settings.copyWith(modelId: model.id)),
                title: Text(s.t('use_by_default')),
              ),
          ],
        ),
      ),
    );
  }
}
