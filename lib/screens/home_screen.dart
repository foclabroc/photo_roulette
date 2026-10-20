import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/room.dart';
import '../services/room_service.dart';
import '../theme.dart';
import '../utils/last_room.dart';
import '../utils/room_code.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _prefName = 'player_name';

  final _service = RoomService.instance();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  RoomSession? _resume;

  @override
  void initState() {
    super.initState();
    _loadName();
    _startup();
  }

  Future<void> _startup() async {
    // Ménage silencieux des photos des vieux salons laissés ouverts,
    // puis recherche d'une partie en cours à reprendre.
    await _service.cleanupStale();
    await _checkResume();
  }

  /// Partie mémorisée sur l'appareil encore accessible ? (plantage, onglet fermé…)
  Future<void> _checkResume() async {
    final roomId = await LastRoomStore.read();
    RoomSession? session;
    if (roomId != null) {
      session = await _service.rejoinRoom(roomId);
      if (session == null) await LastRoomStore.clear();
    }
    if (mounted) setState(() => _resume = session);
  }

  Future<void> _openLobby(RoomSession session) async {
    await LastRoomStore.save(session.roomId);
    if (!mounted) return;
    setState(() => _resume = null);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LobbyScreen(session: session)),
    );
    await _checkResume();
  }

  Future<void> _resumeGame() async {
    final session = _resume;
    if (session == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _openLobby(session);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefName);
    if (saved != null && mounted) _nameCtrl.text = saved;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String? _checkName() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('Choisis un pseudo.');
      return null;
    }
    return name;
  }

  Future<void> _create() async {
    final name = _checkName();
    if (name == null) return;
    await _run(() => _service.createRoom(name), name);
  }

  Future<void> _join() async {
    final name = _checkName();
    if (name == null) return;
    final code = normalizeRoomCode(_codeCtrl.text);
    if (!isValidRoomCode(code)) {
      _showError('Le code fait ${AppConfig.codeLength} caractères.');
      return;
    }
    await _run(() => _service.joinRoom(code, name), name);
  }

  Future<void> _run(Future<RoomSession> Function() action, String name) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefName, name);
      final session = await action();
      if (!mounted) return;
      await _openLobby(session);
    } on RoomException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.photo_library_rounded,
                      size: 72, color: kAccent),
                  const SizedBox(height: 12),
                  Text(
                    'Photo Roulette',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'À qui est cette photo ?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 36),
                  if (_resume != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Partie en cours · ${_resume!.code}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _busy ? null : _resumeGame,
                              icon: const Icon(Icons.replay_rounded),
                              label: const Text('Reprendre la partie'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  TextField(
                    controller: _nameCtrl,
                    enabled: !_busy,
                    maxLength: 20,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Ton pseudo',
                      prefixIcon: Icon(Icons.person_rounded),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Créer une partie'),
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('ou rejoindre',
                          style: theme.textTheme.labelLarge),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _codeCtrl,
                    enabled: !_busy,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [RoomCodeFormatter()],
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(hintText: 'CODE'),
                    onSubmitted: (_) => _join(),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _join,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Rejoindre'),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
