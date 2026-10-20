/// Une manche : une photo à deviner (cf. 04_rounds.sql).
class GameRound {
  const GameRound({
    required this.id,
    required this.index,
    required this.storagePath,
    required this.startedAt,
    required this.endsAt,
    required this.revealed,
    required this.ownerPlayerId,
  });

  final String id;
  final int index;
  final String storagePath;
  final DateTime? startedAt;
  final DateTime? endsAt;
  final bool revealed;

  /// Connu seulement après la révélation.
  final String? ownerPlayerId;

  /// Durée du chrono telle que fixée par le serveur.
  Duration get duration {
    final s = startedAt, e = endsAt;
    if (s == null || e == null) return const Duration(seconds: 15);
    final d = e.difference(s);
    return d.isNegative ? Duration.zero : d;
  }

  /// La photo appartient-elle à ce joueur ? (le chemin contient l'id du propriétaire)
  bool isOwnedBy(String playerId) => storagePath.contains('/$playerId/');

  factory GameRound.fromMap(Map<String, dynamic> map) => GameRound(
        id: map['id'] as String,
        index: (map['round_index'] as num).toInt(),
        storagePath: map['storage_path'] as String? ?? '',
        startedAt: DateTime.tryParse(map['started_at'] as String? ?? ''),
        endsAt: DateTime.tryParse(map['ends_at'] as String? ?? ''),
        revealed: map['revealed'] as bool? ?? false,
        ownerPlayerId: map['owner_player_id'] as String?,
      );
}

class Vote {
  const Vote({
    required this.roundId,
    required this.voterId,
    required this.guessId,
    required this.points,
  });

  final String roundId;
  final String voterId;
  final String guessId;
  final int points;

  factory Vote.fromMap(Map<String, dynamic> map) => Vote(
        roundId: map['round_id'] as String,
        voterId: map['voter_player_id'] as String,
        guessId: map['guessed_player_id'] as String,
        points: (map['points'] as num?)?.toInt() ?? 0,
      );
}
