import 'dart:math';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'photo_source.dart';

PhotoSource createPhotoSource() => _PickedPhotoSource();

class _PickedPhotoSource implements PhotoSource {
  final _picker = ImagePicker();
  final _random = Random();
  final _queue = <XFile>[];

  @override
  bool get canPickMore => true;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> init() async {
    await pickMore();
    if (_queue.isEmpty) {
      throw const PhotoSourceException('Aucune photo sélectionnée.');
    }
  }

  @override
  Future<void> pickMore() async {
    // Le navigateur réduit les images avant de nous les donner.
    final files = await _picker.pickMultiImage(
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 80,
    );
    _queue
      ..addAll(files)
      ..shuffle(_random);
  }

  @override
  Future<Uint8List?> next() async {
    if (_queue.isEmpty) return null;
    return _queue.removeLast().readAsBytes();
  }
}
