import 'dart:typed_data';

/// Une photo validée par le joueur et envoyée dans le bucket.
class MyPhoto {
  const MyPhoto({required this.id, required this.path, this.bytes});

  final String id;
  final String path;

  /// Présent pour les photos envoyées pendant cette session (évite un téléchargement).
  final Uint8List? bytes;
}
