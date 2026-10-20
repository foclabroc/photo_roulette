import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/room.dart';
import '../models/round.dart';
import '../services/photo_cache.dart';
import '../services/room_service.dart';
import '../theme.dart';

/// Phase « playing » : une photo par manche, vote avec chrono, révélation, scores.
class GameView extends StatefulWidget {
  const GameView({
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
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  StreamSubscription<List<GameRound>>? _roundsSub;
  StreamSubscription<List<Vote>>? _votesSub;
  Timer? _ticker;
  Timer? _retry;

  List<GameRound> _rounds = const [];
  List<Vote> _votes = const [];

  String? _activeRoundId;
  DateTime? _localEnd;
  bool _revealAsked = false;
  int _revealTries = 0;
  bool _busy = false;
  String? _myGuess;

  String get _me => widget.session.playerId;

  GameRound? get _current {
    for (final r in _rounds) {
      if (r.index == widget.room.currentRound) return r;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _subscribe() {
    _retry?.cancel();
    _roundsSub?.cancel();
    _votesSub?.cancel();
    final roomId = widget.room.id;
    _roundsSub = widget.service.watchRounds(roomId).listen((rounds) {
      if (!mounted) return;
      setState(() => _rounds = rounds);
      _onRoundsChanged();
    }, onError: (_) => _scheduleRetry());
    _votesSub = widget.service.watchVotes(roomId).listen((votes) {
      if (!mounted) return;
      setState(() => _votes = votes);
    }, onError: (_) => _scheduleRetry());
  }

  void _scheduleRetry() {
    if (_retry?.isActive ?? false) return;
    _retry = Timer(const Duration(seconds: 3), _subscribe);
  }

  @override
  void didUpdateWidget(covariant GameView old) {
    super.didUpdateWidget(old);
    if (old.room.currentRound != widget.room.currentRound) _onRoundsChanged();
  }

  /// Nouvelle manche : chrono local (insensible au décalage d'horloge) + préchargement.
  void _onRoundsChanged() {
    final current = _current;
    if (current == null) return;
    if (current.id != _activeRoundId) {
      _activeRoundId = current.id;
      _localEnd = DateTime.now().add(current.duration);
      _revealAsked = false;
      _revealTries = 0;
      _myGuess = null;
    }
    PhotoCache.prefetch(widget.service, current.storagePath);
    for (final r in _rounds) {
      if (r.index == current.index + 1) {
        PhotoCache.prefetch(widget.service, r.storagePath);
      }
    }
  }

  void _tick() {
    if (!mounted) return;
    final current = _current;
    if (current == null || current.revealed) return;
    setState(() {}); // rafraîchit le chrono
    final end = _localEnd;
    if (end != null && DateTime.now().isAfter(end) && !_revealAsked) {
      _revealAsked = true;
      _askReveal(current.id);
    }
  }

  /// Fin du chrono : demande la révélation (le serveur refuse si c'est trop tôt pour lui).
  Future<void> _askReveal(String roundId) async {
    try {
      await widget.service.revealRound(roundId);
    } on RoomException catch (e) {
      if (e.message == 'TOO_EARLY' && _revealTries < 5 && mounted) {
        _revealTries++;
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (mounted && _activeRoundId == roundId) await _askReveal(roundId);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _retry?.cancel();
    _roundsSub?.cancel();
    _votesSub?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _vote(GameRound round, Player guess) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _myGuess = guess.id;
    });
    try {
      await widget.service.vote(round.id, guess.id);
    } on RoomException catch (e) {
      setState(() => _myGuess = null);
      _snack(e.message);
    } catch (e) {
      setState(() => _myGuess = null);
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.nextRound(widget.room.id);
    } on RoomException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Player? _player(String? id) {
    for (final p in widget.players) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _name(String? id) => _player(id)?.name ?? 'Joueur parti';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _current;
    final room = widget.room;

    if (current == null) {
      // Manche introuvable (chargement, ou photo d'un joueur parti)
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          if (widget.isHost && _rounds.isNotEmpty) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _next,
              child: const Text('Passer à la manche suivante'),
            ),
          ],
        ]),
      );
    }

    final votes = _votes.where((v) => v.roundId == current.id).toList();
    final myVote = votes.where((v) => v.voterId == _me).firstOrNull;
    final mine = current.isOwnedBy(_me);
    final voters = widget.players.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            Text('Manche ${current.index + 1}/${room.totalRounds}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            if (!current.revealed) _Countdown(end: _localEnd, total: current.duration),
          ]),
        ),
        Expanded(
          flex: current.revealed ? 4 : 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _RoundPhoto(service: widget.service, path: current.storagePath),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: current.revealed ? 6 : 4,
          child: current.revealed
              ? _buildReveal(theme, current, votes)
              : _buildVoting(theme, current, mine, myVote, votes.length, voters),
        ),
      ],
    );
  }

  Widget _buildVoting(ThemeData theme, GameRound round, bool mine, Vote? myVote,
      int voteCount, int voters) {
    if (mine) {
      return _Waiting(
        icon: '🤫',
        title: 'C\'est ta photo !',
        text: 'Ne dis rien… Votes : $voteCount/$voters',
      );
    }
    final guessId = myVote?.guessId ?? _myGuess;
    if (guessId != null) {
      return _Waiting(
        icon: '🗳️',
        title: 'Vote : ${_name(guessId)}',
        text: 'En attente des autres… Votes : $voteCount/$voters',
      );
    }
    final choices = widget.players.where((p) => p.id != _me).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('À qui est cette photo ?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in choices)
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _vote(round, p),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(130, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(p.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReveal(ThemeData theme, GameRound round, List<Vote> votes) {
    final owner = round.ownerPlayerId;
    final wrong = votes.where((v) => v.guessId != owner).length;
    final ranking = [...widget.players]..sort((a, b) => b.score.compareTo(a.score));
    final last = widget.room.currentRound >= widget.room.totalRounds - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          owner == _me ? 'C\'était ta photo !' : 'C\'était la photo de ${_name(owner)} !',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900, color: kAccent),
        ),
        if (wrong > 0)
          Text('${_name(owner)} : +${20 * wrong} ($wrong joueur${wrong > 1 ? 's' : ''} trompé${wrong > 1 ? 's' : ''})',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final v in votes)
                _VoteLine(
                  voter: _name(v.voterId),
                  guess: _name(v.guessId),
                  correct: v.guessId == owner,
                  points: v.points,
                ),
              if (votes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Personne n\'a voté.', textAlign: TextAlign.center),
                ),
              const Divider(height: 24),
              for (var i = 0; i < ranking.length; i++)
                _ScoreLine(
                  rank: i + 1,
                  name: ranking[i].id == _me ? '${ranking[i].name} (toi)' : ranking[i].name,
                  score: ranking[i].score,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: widget.isHost
              ? FilledButton.icon(
                  onPressed: _busy ? null : _next,
                  icon: Icon(last ? Icons.emoji_events_rounded : Icons.skip_next_rounded),
                  label: Text(last ? 'Voir le podium' : 'Manche suivante'),
                )
              : Text('En attente de l\'hôte…',
                  textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        ),
      ],
    );
  }
}

class _RoundPhoto extends StatelessWidget {
  const _RoundPhoto({required this.service, required this.path});

  final RoomService service;
  final String path;

  @override
  Widget build(BuildContext context) {
    final cached = PhotoCache.peek(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: Colors.black,
        child: cached != null
            ? _image(cached)
            : FutureBuilder<Uint8List>(
                key: ValueKey(path),
                future: PhotoCache.get(service, path),
                builder: (_, snap) {
                  if (snap.hasData) return _image(snap.data!);
                  if (snap.hasError) {
                    return const Center(
                        child: Text('Photo indisponible',
                            style: TextStyle(color: Colors.white54)));
                  }
                  return const Center(child: CircularProgressIndicator());
                },
              ),
      ),
    );
  }

  Widget _image(Uint8List bytes) => SizedBox.expand(
        child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
      );
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.end, required this.total});

  final DateTime? end;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final left = end == null
        ? Duration.zero
        : end!.difference(DateTime.now());
    final secs = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
    final ratio = total.inMilliseconds == 0
        ? 0.0
        : (left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final color = secs <= 5 ? Colors.redAccent : kAccent;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: ratio.toDouble(),
          strokeWidth: 5,
          color: color,
          backgroundColor: Colors.white12,
        ),
        Text('$secs',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: color)),
      ]),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.icon, required this.title, required this.text});

  final String icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        Text(title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _VoteLine extends StatelessWidget {
  const _VoteLine({
    required this.voter,
    required this.guess,
    required this.correct,
    required this.points,
  });

  final String voter;
  final String guess;
  final bool correct;
  final int points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 20, color: correct ? Colors.greenAccent : Colors.redAccent),
        const SizedBox(width: 8),
        Expanded(child: Text('$voter → $guess')),
        if (points > 0)
          Text('+$points',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: Colors.greenAccent)),
      ]),
    );
  }
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({required this.rank, required this.name, required this.score});

  final int rank;
  final String name;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 28, child: Text('$rank.')),
        Expanded(child: Text(name)),
        Text('$score pts', style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
