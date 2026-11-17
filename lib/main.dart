import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'data.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const CloudBox());
  await store.init();
}

ThemeData _theme(bool dark) {
  final b = dark ? Brightness.dark : Brightness.light;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F5FD1), brightness: b),
    splashFactory: InkRipple.splashFactory,
    dividerColor: dark ? const Color(0xFF282F38) : const Color(0xFFE1E4E9),
  );
}

class CloudBox extends StatelessWidget {
  const CloudBox({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, __) => MaterialApp(
          title: 'Cloud Box',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: messenger,
          themeMode: store.mode,
          theme: _theme(false),
          darkTheme: _theme(true),
          builder: (c, child) {
            Pal.dark = Theme.of(c).brightness == Brightness.dark;
            return child!;
          },
          home: !store.ready ? Scaffold(backgroundColor: Pal.surf) : (store.signedIn ? const Shell() : const Welcome()),
        ),
      );
}
