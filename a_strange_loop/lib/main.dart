import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:a_strange_loop/firebase_options.dart';
import 'package:a_strange_loop/providers/chat_state.dart';
import 'package:a_strange_loop/screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: firebaseOptions);
  } catch (e) {
    runApp(ErrorApp(error: 'Firebase: $e'));
    return;
  }

  final chatState = ChatState();
  try {
    await chatState.seedBrainIfNeeded();
  } catch (e) {
    // ignore: avoid_print
    print('Seed skipped (brain may already exist): $e');
  }

  runApp(ASLApp(chatState: chatState));
}

class ASLApp extends StatelessWidget {
  final ChatState chatState;

  const ASLApp({super.key, required this.chatState});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: chatState,
      child: MaterialApp(
        title: 'A Strange Loop',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C63FF),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C63FF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const ChatScreen(),
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String error;
  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A Strange Loop',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Failed to start: $error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.red)),
          ),
        ),
      ),
    );
  }
}
