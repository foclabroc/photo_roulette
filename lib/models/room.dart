enum RoomStatus { lobby, picking, playing, finished }

RoomStatus _parseStatus(String? value) => RoomStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => RoomStatus.lobby,
    );

class Room {
  const Room({
    required this.id,
    required this.code,
    required this.hostId,
    required this.status,
    required this.photosPerPlayer,
    this.currentRound = -1,
    this.totalRounds = 0,
    this.voteSeconds = 15,
  });

  final String id;
  final String code;
  final String hostId;
  final RoomStatus status;
  final int photosPerPlayer;
  final int currentRound;
  final int totalRounds;
  final int voteSeconds;

  factory Room.fromMap(Map<String, dynamic> map) => Room(
        id: map['id'] as String,
        code: map['code'] as String,
        hostId: map['host_id'] as String,
        status: _parseStatus(map['status'] as String?),
        photosPerPlayer: (map['photos_per_player'] as num?)?.toInt() ?? 5,
        currentRound: (map['current_round'] as num?)?.toInt() ?? -1,
        totalRounds: (map['total_rounds'] as num?)?.toInt() ?? 0,
        voteSeconds: (map['vote_seconds'] as num?)?.toInt() ?? 15,
      );
}

class Player {
  const Player({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.name,
    required this.score,
    required this.ready,
  });

  final String id;
  final String roomId;
  final String userId;
  final String name;
  final int score;
  final bool ready;

  factory Player.fromMap(Map<String, dynamic> map) => Player(
        id: map['id'] as String,
        roomId: map['room_id'] as String,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        score: (map['score'] as num?)?.toInt() ?? 0,
        ready: map['ready'] as bool? ?? false,
      );
}

/// Ce que renvoient pr_create_room / pr_join_room.
class RoomSession {
  const RoomSession({
    required this.roomId,
    required this.playerId,
    required this.code,
  });

  final String roomId;
  final String playerId;
  final String code;

  factory RoomSession.fromMap(Map<String, dynamic> map) => RoomSession(
        roomId: map['room_id'] as String,
        playerId: map['player_id'] as String,
        code: map['code'] as String,
      );
}
