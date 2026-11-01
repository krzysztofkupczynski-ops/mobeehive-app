import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api.dart';
import 'db.dart';
import 'settings.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pl');
  await Db.instance.open();
  await Api.instance.load();
  await Settings.load();
  runApp(const MobeehiveApp());
  SyncService.instance.run();
}

class MobeehiveApp extends StatelessWidget {
  const MobeehiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    const honey = Color(0xFFE8A317);
    return MaterialApp(
      title: 'Mobeehive',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: honey),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: honey, brightness: Brightness.dark),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: Api.instance.loggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
