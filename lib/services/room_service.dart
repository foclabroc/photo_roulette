import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/photo.dart';
import '../models/room.dart';
import '../models/round.dart';

class RoomException implements Exception {
  const RoomException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RoomService {
  RoomService(this._client);

  factory RoomService.instance() => RoomService(Supabase.instance.client);

  final SupabaseClient _client;

  String? get userId => _client.auth.currentUser?.id;

  /// Connexion anonyme (à activer dans Supabase > Authentication).
  Future<void> ensureSignedIn() async {
    if (_client.auth.currentSession == null) {
      await _client.auth.signInAnonymously();
    }
  }

  Future<RoomSession> createRoom(String name) =>
      _callRoomRpc('pr_create_room', {'p_name': name});

  Future<RoomSession> joinRoom(String code, String name) =>
      _callRoomRpc('pr_join_room', {'p_code': code, 'p_name': name});

  /// Reprise d'une partie mémorisée sur l'appareil (cf. 03_rejoin.sql).
  /// Renvoie null si la partie n'existe plus ou n'est plus accessible.
  Future<RoomSession?> rejoinRoom(String roomId) async {
    if (_client.auth.currentSession == null) return null;
    try {
      return await _callRoomRpc('pr_rejoin_room', {'p_room': roomId});
    } catch (_) {
      return null;
    }
  }

  Future<RoomSession> _callRoomRpc(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      await ensureSignedIn();
      final res = await _client.rpc(fn, params: params);
      return RoomSession.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw RoomException(_translate(e.message));
    } on AuthException catch (e) {
      throw RoomException('Connexion impossible : ${e.message}');
    }
  }

  Stream<Room?> watchRoom(String roomId) => _client
      .from('pr_rooms')
      .stream(primaryKey: ['id'])
      .eq('id', roomId)
      .map((rows) => rows.isEmpty ? null : Room.fromMap(rows.first));

  Stream<List<Player>> watchPlayers(String roomId) => _client
      .from('pr_players')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .order('joined_at', ascending: true)
      .map((rows) {
        // Le flux Realtime peut renvoyer deux fois la même ligne
        // (chargement initial + événement reçu juste après) : on dédoublonne par id.
        final byId = <String, Player>{};
        for (final row in rows) {
          final player = Player.fromMap(row);
          byId[player.id] = player;
        }
        return byId.values.toList();
      });

  /// L'hôte qui part ferme le salon (et efface toutes les photos) ;
  /// un joueur qui part efface ses photos puis retire sa ligne.
  Future<void> leaveRoom(RoomSession session, {required bool isHost}) async {
    if (isHost) {
      await _ignoreErrors(() => deleteRoomFiles(session.roomId));
      await _client.from('pr_rooms').delete().eq('id', session.roomId);
    } else {
      await _ignoreErrors(() => _deletePlayerFiles(session.playerId));
      await _client.from('pr_players').delete().eq('id', session.playerId);
    }
  }

  Future<void> kickPlayer(String playerId) async {
    await _ignoreErrors(() => _deletePlayerFiles(playerId));
    await _client.from('pr_players').delete().eq('id', playerId);
  }

  /// Un échec d'effacement ne doit pas empêcher de quitter / fermer le salon :
  /// le ménage des vieux salons (cleanupStale) rattrapera les restes.
  Future<void> _ignoreErrors(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  // ---------- Nettoyage des fichiers ----------

  /// Efface tous les fichiers d'un salon (hôte uniquement, cf. 02_cleanup.sql).
  /// À appeler aussi en fin de partie, après le podium.
  Future<void> deleteRoomFiles(String roomId) async {
    final rows = await _client
        .from('pr_photos')
        .select('storage_path')
        .eq('room_id', roomId);
    await _removePaths(rows.map((r) => r['storage_path'] as String));
  }

  Future<void> _deletePlayerFiles(String playerId) async {
    final rows = await _client
        .from('pr_photos')
        .select('storage_path')
        .eq('owner_player_id', playerId);
    await _removePaths(rows.map((r) => r['storage_path'] as String));
  }

  /// Ménage des vieux salons (plus de 6 h) laissés ouverts : mes photos,
  /// celles des salons dont je suis l'hôte, puis les salons eux-mêmes.
  /// Ne bloque jamais l'appli : toute erreur est ignorée.
  Future<void> cleanupStale() async {
    // Jamais connecté sur cet appareil : rien à nettoyer (et pas de compte anonyme créé pour rien).
    if (_client.auth.currentSession == null) return;
    try {
      final res = await _client.rpc('pr_my_stale_photo_paths');
      final paths = (res as List).map((p) => p.toString());
      await _removePaths(paths);
      await _client.rpc('pr_delete_my_stale_rooms');
    } catch (_) {
      // SQL pas encore lancé, réseau absent… on réessaiera à la prochaine ouverture.
    }
  }

  Future<void> _removePaths(Iterable<String> paths) async {
    final list = paths.toList();
    // L'API Storage accepte jusqu'à 1000 chemins par appel.
    for (var i = 0; i < list.length; i += 1000) {
      final end = i + 1000 > list.length ? list.length : i + 1000;
      await _client.storage.from(photoBucket).remove(list.sublist(i, end));
    }
  }

  Future<void> setPhotosPerPlayer(String roomId, int count) => _client
      .from('pr_rooms')
      .update({'photos_per_player': count}).eq('id', roomId);

  Future<void> startGame(String roomId) => _client
      .from('pr_rooms')
      .update({'status': RoomStatus.picking.name}).eq('id', roomId);

  // ---------- Manches (cf. 04_rounds.sql) ----------

  Future<void> startRounds(String roomId) => _rpc('pr_start_rounds', {'p_room': roomId});

  Stream<List<GameRound>> watchRounds(String roomId) => _client
      .from('pr_rounds')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .order('round_index', ascending: true)
      .map((rows) {
        final byId = <String, GameRound>{};
        for (final r in rows) {
          final round = GameRound.fromMap(r);
          byId[round.id] = round;
        }
        return byId.values.toList()..sort((a, b) => a.index.compareTo(b.index));
      });

  Stream<List<Vote>> watchVotes(String roomId) => _client
      .from('pr_votes')
      .stream(primaryKey: ['round_id', 'voter_player_id'])
      .eq('room_id', roomId)
      .map((rows) {
        final byKey = <String, Vote>{};
        for (final r in rows) {
          final v = Vote.fromMap(r);
          byKey['${v.roundId}|${v.voterId}'] = v;
        }
        return byKey.values.toList();
      });

  Future<void> vote(String roundId, String guessPlayerId) =>
      _rpc('pr_vote', {'p_round': roundId, 'p_guess': guessPlayerId});

  Future<void> revealRound(String roundId) =>
      _rpc('pr_reveal_round', {'p_round': roundId});

  Future<void> nextRound(String roomId) => _rpc('pr_next_round', {'p_room': roomId});

  Future<Uint8List> downloadPhoto(String path) =>
      _client.storage.from(photoBucket).download(path);

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw RoomException(_translate(e.message));
    }
  }

  // ---------- Photos ----------

  static const photoBucket = 'pr-photos';
  final _random = Random();

  Future<List<MyPhoto>> myPhotos(String playerId) async {
    final rows = await _client
        .from('pr_photos')
        .select('id, storage_path')
        .eq('owner_player_id', playerId)
        .order('created_at');
    return rows
        .map((r) => MyPhoto(
              id: r['id'] as String,
              path: r['storage_path'] as String,
            ))
        .toList();
  }

  /// Envoie la photo dans <room_id>/<player_id>/ puis l'enregistre en base.
  Future<MyPhoto> uploadPhoto(RoomSession session, Uint8List bytes) async {
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1000000)}.jpg';
    final path = '${session.roomId}/${session.playerId}/$name';
    await _client.storage.from(photoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    final row = await _client
        .from('pr_photos')
        .insert({
          'room_id': session.roomId,
          'owner_player_id': session.playerId,
          'storage_path': path,
        })
        .select('id')
        .single();
    return MyPhoto(id: row['id'] as String, path: path, bytes: bytes);
  }

  Future<void> deletePhoto(MyPhoto photo) async {
    await _client.from('pr_photos').delete().eq('id', photo.id);
    await _client.storage.from(photoBucket).remove([photo.path]);
  }

  Future<String> photoUrl(String path) =>
      _client.storage.from(photoBucket).createSignedUrl(path, 3600);

  Future<void> setReady(String playerId, bool ready) => _client
      .from('pr_players')
      .update({'ready': ready}).eq('id', playerId);

  String _translate(String message) {
    if (message.contains('ROOM_NOT_FOUND')) {
      return 'Aucun salon en attente avec ce code.';
    }
    if (message.contains('ROOM_FULL')) return 'Ce salon est complet.';
    if (message.contains('ROUND_CLOSED')) return 'Trop tard, la manche est terminée.';
    if (message.contains('TOO_EARLY')) return 'TOO_EARLY';
    if (message.contains('NO_PHOTOS')) return 'Aucune photo dans la partie.';
    if (message.contains('NOT_HOST')) return 'Seul l\'hôte peut faire ça.';
    if (message.contains('Could not find the function')) {
      return 'Base pas à jour : lance 04_rounds.sql dans Supabase.';
    }
    if (message.contains('ROOM_STARTED')) {
      return 'La partie a déjà commencé, trop tard pour rejoindre.';
    }
    if (message.contains('NAME_REQUIRED')) return 'Choisis un pseudo.';
    if (message.contains('NOT_AUTHENTICATED')) {
      return 'Connexion impossible, réessaie.';
    }
    return 'Erreur : $message';
  }
}
