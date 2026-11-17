import 'package:flutter/material.dart';

/// Application Andika. L'écran d'accueil sera remplacé au lot L9.
class AndikaApp extends StatelessWidget {
  const AndikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Andika',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E7B)),
      ),
      home: const Scaffold(
        body: Center(child: Text('Andika')),
      ),
    );
  }
}
