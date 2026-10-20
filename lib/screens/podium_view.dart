import 'package:flutter/material.dart';

import '../models/room.dart';
import '../services/photo_cache.dart';
import '../services/room_service.dart';
import '../theme.dart';

/// Phase « finished » : podium final. L'hôte efface les photos du Storage dès l'arrivée.
class PodiumView extends StatefulWidget {
  const PodiumView({
    super.key,
    required this.session,
    required this.room,
    required this.players,
    required this.isHost,
    required this.service,
    required this.onLeave,
  });

  final RoomSession session;
  final Room room;
  final List<Player> players;
  final bool isHost;
  final RoomService service;
  final VoidCallback onLeave;

  @override
  State<PodiumView> createState() => _PodiumViewState();
}

class _PodiumViewState extends State<PodiumView> {
  @override
  void initState() {
    super.initState();
    PhotoCache.clear();
    // Les photos ne servent plus : on libère le stockage tout de suite.
    if (widget.isHost) {
      widget.service.deleteRoomFiles(widget.room.id).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ranking = [...widget.players]..sort((a, b) => b.score.compareTo(a.score));
    const medals = ['🥇', '🥈', '🥉'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Icon(Icons.emoji_events_rounded, size: 64, color: Colors.amber),
        Text('Podium',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: ranking.length,
            itemBuilder: (_, i) {
              final p = ranking[i];
              final top = i < 3;
              final me = p.id == widget.session.playerId;
              return Card(
                color: i == 0 ? kAccent.withValues(alpha: 0.25) : null,
                child: ListTile(
                  leading: Text(top ? medals[i] : '${i + 1}.',
                      style: TextStyle(fontSize: top ? 28 : 18)),
                  title: Text(me ? '${p.name} (toi)' : p.name,
                      style: TextStyle(
                          fontSize: top ? 18 : 16,
                          fontWeight: top ? FontWeight.w800 : FontWeight.w500)),
                  trailing: Text('${p.score} pts',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: widget.onLeave,
            icon: const Icon(Icons.home_rounded),
            label: Text(widget.isHost ? 'Fermer le salon' : 'Quitter'),
          ),
        ),
      ],
    );
  }
}
