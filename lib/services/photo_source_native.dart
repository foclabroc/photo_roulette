import 'dart:math';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'photo_source.dart';

PhotoSource createPhotoSource() => _GalleryPhotoSource();

class _GalleryPhotoSource implements PhotoSource {
  final _random = Random();
  final _used = <int>{};
  AssetPathEntity? _album;
  int _count = 0;

  @override
  bool get canPickMore => false;

  @override
  Future<void> pickMore() async {}

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<void> init() async {
    final state = await PhotoManager.requestPermissionExtend();
    if (!state.hasAccess) {
      throw const PhotoSourceException(
        'Accès aux photos refusé. Autorise-le dans les réglages de l\'appli.',
        canOpenSettings: true,
      );
    }
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      throw const PhotoSourceException('Aucune photo trouvée sur ce téléphone.');
    }
    _album = albums.first;
    _count = await _album!.assetCountAsync;
    if (_count == 0) {
      throw const PhotoSourceException('Aucune photo trouvée sur ce téléphone.');
    }
  }

  @override
  Future<Uint8List?> next() async {
    final album = _album;
    if (album == null) return null;

    // Quelques essais au cas où une photo serait illisible.
    for (var attempt = 0; attempt < 10; attempt++) {
      if (_used.length >= _count) return null;
      int index;
      do {
        index = _random.nextInt(_count);
      } while (_used.contains(index));
      _used.add(index);

      final assets = await album.getAssetListRange(start: index, end: index + 1);
      if (assets.isEmpty) continue;
      final bytes = await assets.first.thumbnailDataWithSize(
        const ThumbnailSize(1080, 1080),
        quality: 80,
      );
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
    return null;
  }
}
