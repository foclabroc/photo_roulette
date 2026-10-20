import 'dart:typed_data';

import 'photo_source_native.dart'
    if (dart.library.js_interop) 'photo_source_web.dart' as impl;

/// Fournit des photos au hasard, déjà réduites (~1080 px, JPEG).
/// - Android : tirage dans toute la galerie.
/// - Web : tirage dans un lot choisi par le joueur (le navigateur ne lit pas la galerie).
abstract class PhotoSource {
  factory PhotoSource() => impl.createPhotoSource();

  /// À appeler depuis un geste utilisateur (le web l'exige pour ouvrir le sélecteur).
  /// Lève [PhotoSourceException] si l'accès est refusé ou s'il n'y a aucune photo.
  Future<void> init();

  /// Photo suivante, jamais deux fois la même ; null quand il n'y en a plus.
  Future<Uint8List?> next();

  /// Web : le joueur peut ajouter un lot quand le précédent est épuisé.
  bool get canPickMore;
  Future<void> pickMore();

  /// Android : ouvre les réglages de l'appli (permission refusée).
  Future<void> openSettings();
}

class PhotoSourceException implements Exception {
  const PhotoSourceException(this.message, {this.canOpenSettings = false});

  final String message;
  final bool canOpenSettings;

  @override
  String toString() => message;
}
