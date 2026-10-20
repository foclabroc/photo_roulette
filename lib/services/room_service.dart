import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/photo.dart';
import '../models/room.dart';

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
      .map((rows) => rows.map(Player.fromMap).toList());

  /// L'hôte qui part ferme le salon ; un joueur qui part retire juste sa ligne.
  Future<void> leaveRoom(RoomSession session, {required bool isHost}) async {
    if (isHost) {
      await _client.from('pr_rooms').delete().eq('id', session.roomId);
    } else {
      await _client.from('pr_players').delete().eq('id', session.playerId);
    }
  }

  Future<void> kickPlayer(String playerId) =>
      _client.from('pr_players').delete().eq('id', playerId);

  Future<void> setPhotosPerPlayer(String roomId, int count) => _client
      .from('pr_rooms')
      .update({'photos_per_player': count}).eq('id', roomId);

  Future<void> startGame(String roomId) => _client
      .from('pr_rooms')
      .update({'status': RoomStatus.picking.name}).eq('id', roomId);

  Future<void> startRounds(String roomId) => _client
      .from('pr_rooms')
      .update({'status': RoomStatus.playing.name}).eq('id', roomId);

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
    if (message.contains('NAME_REQUIRED')) return 'Choisis un pseudo.';
    if (message.contains('NOT_AUTHENTICATED')) {
      return 'Connexion impossible, réessaie.';
    }
    return 'Erreur : $message';
  }
}
