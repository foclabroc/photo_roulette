import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import 'photo_source.dart';

PhotoSource createPhotoSource() => _PickedPhotoSource();

/// Taille max d'un côté après réduction, et nombre max de photos par lot.
const _maxSide = 1080;
const _maxPerBatch = 40;

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
    // Pas de redimensionnement ici : le faire sur tout le lot d'un coup
    // fait planter l'onglet sur mobile (manque de mémoire).
    final files = await _picker.pickMultiImage();
    final batch = [...files]..shuffle(_random);
    _queue
      ..addAll(batch.take(_maxPerBatch))
      ..shuffle(_random);
  }

  @override
  Future<Uint8List?> next() async {
    while (_queue.isNotEmpty) {
      final file = _queue.removeLast();
      try {
        return await _resize(file);
      } catch (_) {
        // Format illisible par le navigateur (HEIC…) : on passe à la suivante.
      }
    }
    return null;
  }

  /// Réduit une seule image (côté max 1080 px, JPEG qualité 0,8) via un canvas.
  Future<Uint8List> _resize(XFile file) async {
    final bytes = await file.readAsBytes();
    final blob = web.Blob(<web.BlobPart>[bytes.toJS].toJS);
    final bitmap = await web.window.createImageBitmap(blob).toDart;

    final w = bitmap.width;
    final h = bitmap.height;
    final scale = min(1.0, _maxSide / max(w, h));
    final outW = max(1, (w * scale).round());
    final outH = max(1, (h * scale).round());

    final canvas = web.HTMLCanvasElement()
      ..width = outW
      ..height = outH;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.drawImage(bitmap, 0, 0, outW, outH);
    bitmap.close();

    final completer = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? result) => completer.complete(result)).toJS,
      'image/jpeg',
      0.8.toJS,
    );
    final jpeg = await completer.future;
    if (jpeg == null) throw StateError('Conversion JPEG impossible');

    final buffer = await jpeg.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }
}
