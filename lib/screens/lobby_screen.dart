import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/room.dart';
import '../services/room_service.dart';
import '../theme.dart';
import '../utils/last_room.dart';
import 'picking_view.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.session});

  final RoomSession session;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with WidgetsBindingObserver {
  final _service = RoomService.instance();
  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<List<Player>>? _playersSub;
  Timer? _retryTimer;
  int _retryDelay = 2;

  Room? _room;
  bool _roomLoaded = false;
  List<Player> _players = const [];
  bool _leaving = false;
  bool _reconnecting = false;

  bool get _isHost => _room != null && _room!.hostId == _service.userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
  }

  /// (Ré)ouvre les flux Realtime du salon et des joueurs.
  void _subscribe() {
    _retryTimer?.cancel();
    _roomSub?.cancel();
    _playersSub?.cancel();

    _roomSub = _service.watchRoom(widget.session.roomId).listen(
          _onRoom,
          onError: _onStreamError,
        );
    _playersSub = _service.watchPlayers(widget.session.roomId).listen(
      (players) {
        if (!mounted) return;
        _onConnected();
        setState(() => _players = players);
        // Exclu par l'hôte ?
        if (_roomLoaded && !players.any((p) => p.id == widget.session.playerId)) {
          _exit('Tu as été retiré du salon.');
        }
      },
      onError: _onStreamError,
    );
  }

  void _onConnected() {
    _retryDelay = 2;
    if (_reconnecting) setState(() => _reconnecting = false);
  }

  /// Coupure (onglet en arrière-plan, changement de réseau…) : on réessaie
  /// avec un délai croissant (2 s, 4 s, 8 s, puis 15 s max).
  void _onStreamError(Object _) {
    if (!mounted || _leaving) return;
    if (!_reconnecting) setState(() => _reconnecting = true);
    if (_retryTimer?.isActive ?? false) return;
    _retryTimer = Timer(Duration(seconds: _retryDelay), _subscribe);
    _retryDelay = _retryDelay * 2 > 15 ? 15 : _retryDelay * 2;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour au premier plan : on rafraîchit tout de suite.
    if (state == AppLifecycleState.resumed && !_leaving) _subscribe();
  }

  void _onRoom(Room? room) {
    if (!mounted) return;
    _onConnected();
    if (room == null) {
      if (_roomLoaded) _exit('Le salon a été fermé par l\'hôte.');
      return;
    }
    setState(() {
      _room = room;
      _roomLoaded = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _roomSub?.cancel();
    _playersSub?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _exit(String message) {
    if (_leaving || !mounted) return;
    _leaving = true;
    LastRoomStore.clear();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmAndLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter le salon ?'),
        content: Text(_isHost
            ? 'Tu es l\'hôte : la partie sera fermée pour tout le monde.'
            : 'Tes photos seront effacées. Tu pourras revenir avec le code tant que la partie n\'a pas commencé.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Rester')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Quitter')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _leaving = true;
    await LastRoomStore.clear();
    try {
      await _service.leaveRoom(widget.session, isHost: _isHost);
    } catch (_) {
      // On quitte l'écran quoi qu'il arrive.
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.session.code));
    _snack('Code copié !');
  }

  Future<void> _start() async {
    try {
      await _service.startGame(widget.session.roomId);
    } catch (e) {
      _snack('Impossible de lancer : $e');
    }
  }

  Future<void> _changePhotos(int delta) async {
    final room = _room;
    if (room == null) return;
    final next = (room.photosPerPlayer + delta).clamp(1, 20);
    if (next == room.photosPerPlayer) return;
    try {
      await _service.setPhotosPerPlayer(room.id, next);
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = _room;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmAndLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Salon'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _confirmAndLeave,
          ),
          bottom: _reconnecting
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(30),
                  child: Container(
                    width: double.infinity,
                    height: 30,
                    alignment: Alignment.center,
                    color: theme.colorScheme.errorContainer,
                    child: Text(
                      'Connexion perdue, reconnexion…',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                )
              : null,
        ),
        body: room == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: switch (room.status) {
                      RoomStatus.lobby => _buildLobby(theme, room),
                      RoomStatus.picking => PickingView(
                          session: widget.session,
                          room: room,
                          players: _players,
                          isHost: _isHost,
                          service: _service,
                        ),
                      _ => const Center(
                          child: _InfoBanner('Les manches arrivent bientôt…'),
                        ),
                    },
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLobby(ThemeData theme, Room room) {
    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CodeCard(code: widget.session.code, onCopy: _copyCode),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                          child: Text(
                            'Joueurs (${_players.length}/${AppConfig.maxPlayers})',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _players.length,
                            itemBuilder: (_, i) => _PlayerTile(
                              player: _players[i],
                              isHost: _players[i].userId == room.hostId,
                              isMe: _players[i].id == widget.session.playerId,
                              onKick: _isHost &&
                                      _players[i].userId != room.hostId
                                  ? () => _service.kickPlayer(_players[i].id)
                                  : null,
                            ),
                          ),
                        ),
                        _BottomBar(
                          isHost: _isHost,
                          room: room,
                          playerCount: _players.length,
                          onStart: _start,
                          onChangePhotos: _changePhotos,
                        ),
                      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onCopy,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(children: [
            Text('Code du salon', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              code,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 10,
                color: kAccent,
              ),
            ),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.copy_rounded, size: 16),
              const SizedBox(width: 6),
              Text('Toucher pour copier', style: theme.textTheme.bodySmall),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onPrimaryContainer)),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.player,
    required this.isHost,
    required this.isMe,
    this.onKick,
  });

  final Player player;
  final bool isHost;
  final bool isMe;
  final VoidCallback? onKick;

  @override
  Widget build(BuildContext context) {
    final initial = player.name.isEmpty ? '?' : player.name[0].toUpperCase();
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(initial)),
        title: Text(isMe ? '${player.name} (toi)' : player.name),
        subtitle: isHost ? const Text('Hôte') : null,
        trailing: isHost
            ? const Icon(Icons.star_rounded, color: Colors.amber)
            : onKick == null
                ? null
                : IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.person_remove_rounded),
                    onPressed: onKick,
                  ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isHost,
    required this.room,
    required this.playerCount,
    required this.onStart,
    required this.onChangePhotos,
  });

  final bool isHost;
  final Room room;
  final int playerCount;
  final VoidCallback onStart;
  final ValueChanged<int> onChangePhotos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inLobby = room.status == RoomStatus.lobby;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Photos par joueur', style: theme.textTheme.bodyLarge),
          const SizedBox(width: 8),
          if (isHost && inLobby)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded),
              onPressed: () => onChangePhotos(-1),
            ),
          Text('${room.photosPerPlayer}',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (isHost && inLobby)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => onChangePhotos(1),
            ),
        ]),
        const SizedBox(height: 8),
        if (!inLobby)
          const SizedBox.shrink()
        else if (isHost)
          FilledButton.icon(
            onPressed: playerCount >= AppConfig.minPlayers ? onStart : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(playerCount >= AppConfig.minPlayers
                ? 'Lancer la partie'
                : 'En attente de joueurs…'),
          )
        else
          Text("En attente du lancement par l'hôte…",
              style: theme.textTheme.bodyLarge),
      ]),
    );
  }
}
