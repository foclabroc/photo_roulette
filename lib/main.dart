import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'update_check.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // En release, Flutter affiche une zone vide en cas d'erreur de rendu :
  // on affiche le message à la place, pour pouvoir diagnostiquer.
  ErrorWidget.builder = (details) => _ErrorText(details.exceptionAsString());
  // On affiche tout de suite (plus d'écran noir pendant l'initialisation).
  runApp(const PhotoRouletteApp());
}

class PhotoRouletteApp extends StatefulWidget {
  const PhotoRouletteApp({super.key});

  @override
  State<PhotoRouletteApp> createState() => _PhotoRouletteAppState();
}

class _PhotoRouletteAppState extends State<PhotoRouletteApp> {
  Future<void>? _init;

  @override
  void initState() {
    super.initState();
    if (AppConfig.isConfigured) _init = _initSupabase();
  }

  static bool _ready = false;

  Future<void> _initSupabase() async {
    if (_ready) return; // déjà initialisé lors d'un essai précédent
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    ).timeout(const Duration(seconds: 15));
    _ready = true;
  }

  void _retry() => setState(() => _init = _initSupabase());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo Roulette',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: !AppConfig.isConfigured
          ? const _MissingConfigScreen()
          : FutureBuilder<void>(
              future: _init,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const _Splash();
                }
                if (snap.hasError) {
                  return _StartupError(error: '${snap.error}', onRetry: _retry);
                }
                return const UpdateGate(child: HomeScreen());
              },
            ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.photo_library_rounded, size: 72, color: kAccent),
          SizedBox(height: 24),
          CircularProgressIndicator(),
        ]),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 64, color: kAccent),
              const SizedBox(height: 16),
              const Text('Connexion au serveur impossible',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SelectableText(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF3A0D16),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text('Erreur : $message',
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Configuration Supabase manquante.\n\n'
            'Lance l\'appli avec --dart-define=SUPABASE_URL=... '
            'et --dart-define=SUPABASE_ANON_KEY=...',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
