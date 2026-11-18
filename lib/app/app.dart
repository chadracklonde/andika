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

  @override
  void initState() {
    super.initState();
    unawaited(controller.init().catchError((Object e) {
      if (mounted) setState(() => _initError = e);
    }));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
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
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E7B)),
            appBarTheme: const AppBarTheme(systemOverlayStyle: SystemUiOverlayStyle.dark),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1B5E7B), brightness: Brightness.dark),
          ),
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
      },
    );
  }
}
