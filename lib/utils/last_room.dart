import 'package:shared_preferences/shared_preferences.dart';

/// Mémorise le dernier salon sur l'appareil pour pouvoir y revenir
/// après un plantage ou une fermeture d'onglet.
class LastRoomStore {
  static const _key = 'last_room_id';

  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> save(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, roomId);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
