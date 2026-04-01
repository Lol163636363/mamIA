import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/setup_page.dart';
import 'pages/chat_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final wakeWord = prefs.getString('wake_word');

  runApp(MamAIApp(initialWakeWord: wakeWord));
}

class MamAIApp extends StatelessWidget {
  final String? initialWakeWord;
  const MamAIApp({super.key, this.initialWakeWord});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mamAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
          secondary: Color(0xFF7B2FFF),
        ),
      ),
      // Si pas de mot-clé enregistré → écran de setup, sinon → chat
      home: initialWakeWord == null
          ? const SetupPage()
          : ChatPage(wakeWord: initialWakeWord!),
    );
  }
}
