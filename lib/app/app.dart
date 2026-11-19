import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../ui/home_screen.dart';
import 'controller.dart';

/// Application Andika.
class AndikaApp extends StatefulWidget {
  const AndikaApp({super.key});

  @override
  State<AndikaApp> createState() => _AndikaAppState();
}

class _AndikaAppState extends State<AndikaApp> {
  final AppController controller = AppController();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Object? _initError;

  // Thèmes créés une seule fois : un thème neuf à chaque reconstruction ferait
  // redessiner toute l'application.
  late final ThemeData _light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E7B)),
    appBarTheme: const AppBarTheme(systemOverlayStyle: SystemUiOverlayStyle.dark),
  );
  late final ThemeData _dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E7B), brightness: Brightness.dark),
  );

  // Seuls ces deux états changent la structure de l'application ; le reste
  // (progression, niveau du micro...) est suivi par les écrans eux-mêmes.
  bool _lastReady = false;
  String _lastLang = 'fr';

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    unawaited(controller.init().catchError((Object e) {
      if (mounted) setState(() => _initError = e);
    }));
  }

  void _onControllerChanged() {
    final lang = controller.ready ? controller.strings.languageCode : 'fr';
    if (lang != _lastLang || controller.ready != _lastReady) {
      _lastLang = lang;
      _lastReady = controller.ready;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = controller.ready ? controller.strings.languageCode : 'fr';
    return MaterialApp(
      title: 'Andika',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      supportedLocales: const <Locale>[Locale('fr'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _light,
      darkTheme: _dark,
      home: controller.ready
          ? HomeScreen(controller: controller)
          : Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Andika', style: TextStyle(fontSize: 28)),
                    const SizedBox(height: 16),
                    if (_initError == null)
                      const CircularProgressIndicator()
                    else
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('$_initError', textAlign: TextAlign.center),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
