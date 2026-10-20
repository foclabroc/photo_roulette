import 'dart:typed_data';

import 'room_service.dart';

/// Photos de la partie gardées en mémoire : chaque photo n'est téléchargée
/// qu'une fois (bande passante Supabase limitée à 5 Go/mois en gratuit).
class PhotoCache {
  static final _bytes = <String, Uint8List>{};
  static final _pending = <String, Future<Uint8List>>{};

  static Uint8List? peek(String path) => _bytes[path];

  static Future<Uint8List> get(RoomService service, String path) {
    final cached = _bytes[path];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(path, () async {
      try {
        final data = await service.downloadPhoto(path);
        _bytes[path] = data;
        return data;
      } finally {
        _pending.remove(path);
      }
    });
  }

  /// Précharge sans attendre ni remonter d'erreur.
  static void prefetch(RoomService service, String path) {
    if (path.isEmpty || _bytes.containsKey(path)) return;
    get(service, path).ignore();
  }

  static void clear() {
    _bytes.clear();
    _pending.clear();
  }
}
