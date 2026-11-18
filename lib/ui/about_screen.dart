import 'package:flutter/material.dart';

import '../app/controller.dart';

/// À propos : version, confidentialité et licences.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.strings;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('about'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Andika', style: Theme.of(context).textTheme.headlineMedium),
          Text(s.t('about_tagline')),
          const SizedBox(height: 16),
          Text(s.t('privacy_title'), style: Theme.of(context).textTheme.titleMedium),
          Text(s.t('privacy_text')),
          const SizedBox(height: 16),
          Text(s.t('credits_title'), style: Theme.of(context).textTheme.titleMedium),
          Text(s.t('credits_text')),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Andika',
              applicationVersion: '0.1.0',
            ),
            child: Text(s.t('licenses')),
          ),
        ],
      ),
    );
  }
}
