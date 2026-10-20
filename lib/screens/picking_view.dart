import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/photo.dart';
import '../models/room.dart';
import '../services/photo_source.dart';
import '../services/room_service.dart';
import '../theme.dart';

/// Phase « picking » : chaque joueur valide ses photos (tirage au hasard + veto).
class PickingView extends StatefulWidget {
  const PickingView({
    super.key,
    required this.session,
    required this.room,
    required this.players,
    required this.isHost,
    required this.service,
  });

  final RoomSession session;
  final Room room;
  final List<Player> players;
  final bool isHost;
  final RoomService service;

  @override
  State<PickingView> createState() => _PickingViewState();
}

class _PickingViewState extends State<PickingView> {
  final PhotoSource _source = PhotoSource();
  final _urls = <String, Future<String>>{};

  List<MyPhoto> _mine = [];
  bool _loadingMine = true;
  bool _started = false;
  bool _busy = false;
  bool _sourceEmpty = false;
  Uint8List? _candidate;
  PhotoSourceException? _error;

  int get _required => widget.room.photosPerPlayer;
  bool get _done => _mine.length >= _required;

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  Future<void> _loadMine() async {
    try {
      final mine = await widget.service.myPhotos(widget.session.playerId);
      if (!mounted) return;
      setState(() {
        _mine = mine;
        _loadingMine = false;
      });
      await _syncReady();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMine = false);
      _snack('Impossible de charger tes photos : $e');
    }
  }

  /// Garde le drapeau « prêt » aligné sur le nombre de photos validées.
  Future<void> _syncReady() async {
    final me = widget.players
        .where((p) => p.id == widget.session.playerId)
        .firstOrNull;
    if (me != null && me.ready == _done) return;
    try {
      await widget.service.setReady(widget.session.playerId, _done);
    } catch (_) {}
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _guard(() async {
        try {
          await _source.init();
        } on PhotoSourceException catch (e) {
          setState(() => _error = e);
          return;
        }
        setState(() {
          _error = null;
          _started = true;
        });
        await _next();
      });

  Future<void> _next() async {
    final bytes = await _source.next();
    if (!mounted) return;
    setState(() {
      _candidate = bytes;
      _sourceEmpty = bytes == null;
    });
  }

  Future<void> _reject() => _guard(_next);

  Future<void> _keep() => _guard(() async {
        final bytes = _candidate;
        if (bytes == null) return;
        final photo = await widget.service.uploadPhoto(widget.session, bytes);
        if (!mounted) return;
        setState(() {
          _mine = [..._mine, photo];
          _candidate = null;
        });
        await _syncReady();
        if (!_done) await _next();
      });

  Future<void> _remove(MyPhoto photo) => _guard(() async {
        await widget.service.deletePhoto(photo);
        if (!mounted) return;
        setState(() => _mine = _mine.where((p) => p.id != photo.id).toList());
        await _syncReady();
        if (_started && _candidate == null && !_sourceEmpty) await _next();
      });

  Future<void> _pickMore() => _guard(() async {
        await _source.pickMore();
        await _next();
      });

  Future<void> _startRounds() =>
      _guard(() => widget.service.startRounds(widget.room.id));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readyCount = widget.players.where((p) => p.ready).length;
    final allReady =
        widget.players.isNotEmpty && readyCount == widget.players.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tes photos : ${_mine.length}/$_required',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: _required == 0
                      ? 0
                      : (_mine.length / _required).clamp(0, 1).toDouble(),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildMain(theme)),
        if (_mine.isNotEmpty) _buildThumbs(),
        _ReadyBar(
          players: widget.players,
          readyCount: readyCount,
          allReady: allReady,
          isHost: widget.isHost,
          busy: _busy,
          onStartRounds: _startRounds,
        ),
      ],
    );
  }

  Widget _buildMain(ThemeData theme) {
    if (_loadingMine) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_done) {
      return _CenteredMessage(
        icon: Icons.check_circle_rounded,
        iconColor: Colors.greenAccent,
        title: 'Tes photos sont prêtes !',
        text: 'Touche une miniature pour la retirer si tu changes d\'avis.',
      );
    }

    if (!_started) {
      final error = _error;
      return _CenteredMessage(
        icon: Icons.casino_rounded,
        iconColor: kAccent,
        title: kIsWeb ? 'Choisis un lot de photos' : 'Tirage dans ta galerie',
        text: kIsWeb
            ? 'Sélectionne une vingtaine de photos : l\'appli en tirera au hasard, '
                'et tu pourras refuser celles que tu ne veux pas montrer.'
            : 'L\'appli va tirer des photos au hasard dans ta galerie. '
                'Tu pourras refuser celles que tu ne veux pas montrer, '
                'rien n\'est envoyé sans ton accord.',
        error: error?.message,
        actions: [
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.photo_library_rounded),
            label: Text(kIsWeb ? 'Choisir mes photos' : 'Commencer'),
          ),
          if (error != null && error.canOpenSettings) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _source.openSettings,
              child: const Text('Ouvrir les réglages'),
            ),
          ],
        ],
      );
    }

    if (_sourceEmpty) {
      return _CenteredMessage(
        icon: Icons.photo_rounded,
        iconColor: theme.colorScheme.onSurfaceVariant,
        title: 'Plus de photos à proposer',
        text: _source.canPickMore
            ? 'Ajoute un autre lot pour continuer.'
            : 'Toute ta galerie y est passée !',
        actions: [
          if (_source.canPickMore)
            FilledButton.icon(
              onPressed: _busy ? null : _pickMore,
              icon: const Icon(Icons.add_photo_alternate_rounded),
              label: const Text('Ajouter des photos'),
            ),
        ],
      );
    }

    final candidate = _candidate;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (candidate != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: Colors.black,
                      child: Image.memory(
                        candidate,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                if (_busy)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || candidate == null ? null : _reject,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Refuser'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || candidate == null ? null : _keep,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Garder'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildThumbs() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _mine.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final photo = _mine[i];
          return GestureDetector(
            onTap: _busy ? null : () => _confirmRemove(photo),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: _thumbImage(photo),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _thumbImage(MyPhoto photo) {
    final bytes = photo.bytes;
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    final url = _urls.putIfAbsent(
      photo.path,
      () => widget.service.photoUrl(photo.path),
    );
    return FutureBuilder<String>(
      future: url,
      builder: (_, snap) => snap.hasData
          ? Image.network(snap.data!, fit: BoxFit.cover)
          : const ColoredBox(color: Colors.white10),
    );
  }

  Future<void> _confirmRemove(MyPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer cette photo ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirer')),
        ],
      ),
    );
    if (ok == true) await _remove(photo);
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.text,
    this.error,
    this.actions = const [],
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String text;
  final String? error;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 64, color: iconColor),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (actions.isNotEmpty) const SizedBox(height: 20),
          ...actions,
        ],
      ),
    );
  }
}

class _ReadyBar extends StatelessWidget {
  const _ReadyBar({
    required this.players,
    required this.readyCount,
    required this.allReady,
    required this.isHost,
    required this.busy,
    required this.onStartRounds,
  });

  final List<Player> players;
  final int readyCount;
  final bool allReady;
  final bool isHost;
  final bool busy;
  final VoidCallback onStartRounds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Prêts : $readyCount/${players.length}',
              textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in players)
                Chip(
                  avatar: Icon(
                    p.ready
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_top_rounded,
                    size: 18,
                    color: p.ready
                        ? Colors.greenAccent
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(p.name),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (isHost) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: allReady && !busy ? onStartRounds : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(allReady
                  ? 'Lancer les manches'
                  : 'En attente des photos…'),
            ),
          ],
        ],
      ),
    );
  }
}
