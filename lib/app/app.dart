import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(controller.init());
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
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
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
              : const Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}
