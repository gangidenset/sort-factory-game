import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app/services.dart';
import '../data/progress_controller.dart';
import '../game/flame/sort_factory_game.dart';
import '../game/logic/game_session.dart';
import '../game/logic/models.dart';
import '../game/logic/solver.dart';
import '../game/logic/stage_config.dart';
import '../services/ads/ad_service.dart';
import '../services/audio/audio_service.dart';
import '../ui/palette.dart';
import '../ui/strings.dart';
import '../ui/widgets.dart';

enum _Phase { tutorial, playing, paused, cleared, failed }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.stage});
  final StageConfig stage;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late GameSession _session;
  late SortFactoryGame _game;
  var _phase = _Phase.tutorial;
  var _attempt = 0;
  RewardSummary? _reward;
  bool _coinsDoubled = false;
  bool _failRecorded = false;
  bool _busy = false;
  bool _initialized = false;
  final _hud = ValueNotifier(0);

  AppServices get _svc => context.services;
  StageConfig get _stage => widget.stage;

  /// Hints are free in the first stages (tutorial); later they cost an ad.
  bool get _freeHint => _stage.id <= 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _setup();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hud.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _Phase.playing) {
      _pause();
    }
  }

  void _setup() {
    final progress = _svc.progress;
    _session = GameSession(_stage, modifiers: progress.modifiers);
    _game = SortFactoryGame(
      session: _session,
      skin: FactorySkin.fromId(progress.data.equippedSkin),
      boxStyle: progress.data.equippedBox,
      onEvent: _onEvent,
      onSettled: _onSettled,
    );
    _reward = null;
    _coinsDoubled = false;
    _failRecorded = false;
    final tut = _stage.tutorial;
    if (tut != null &&
        tutorials.containsKey(tut) &&
        !progress.tutorialSeen(tut)) {
      _phase = _Phase.tutorial;
    } else {
      _start();
    }
  }

  void _start() {
    _attempt++;
    _phase = _Phase.playing;
    _session.start();
    final svc = _svc;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      svc.progress.recordAttempt(_stage.id);
      svc.analytics.log('stage_start', {
        'stage': _stage.id,
        'attempt': _attempt,
      });
    });
  }

  void _onEvent(SessionEvent e) {
    final audio = _svc.audio;
    switch (e.type) {
      case SessionEventType.move:
        audio.feedback(switch (e.destination) {
          ToTruck() => Sfx.correct,
          ToShelf() => Sfx.store,
          _ => Sfx.wrong,
        });
      case SessionEventType.depart:
        audio.feedback(e.chain >= 2 ? Sfx.combo : Sfx.truck);
        audio.chainPitch(e.chain);
      case SessionEventType.reveal:
        audio.play(Sfx.tap);
      default:
        break;
    }
    _hud.value++;
  }

  /// Playback finished and the session ended: show the result.
  void _onSettled() {
    if (!mounted) return;
    if (_session.status == SessionStatus.cleared) {
      _onCleared();
    } else if (_session.status == SessionStatus.failed) {
      _svc.audio.feedback(Sfx.fail);
      setState(() => _phase = _Phase.failed);
    }
  }

  StageResult _result() => StageResult(
    stageId: _stage.id,
    cleared: _session.status == SessionStatus.cleared,
    score: _session.score,
    stars: _session.stars,
    deliveries: _session.delivered,
    maxChain: _session.maxChain,
    seconds: 0,
  );

  Future<void> _onCleared() async {
    if (_phase == _Phase.cleared) return;
    _svc.audio.feedback(Sfx.clear);
    setState(() => _phase = _Phase.cleared);
    final reward = await _svc.progress.recordResult(_result());
    _svc.analytics.log('stage_clear', {
      'stage': _stage.id,
      'score': _session.score,
      'stars': _session.stars,
      'moves': _session.moves,
      'shelf': _session.shelfPlacements,
      'chain': _session.maxChain,
      'undos': _session.undosUsed,
      'revived': _session.revivesUsed,
    });
    if (mounted) setState(() => _reward = reward);
  }

  Future<void> _recordFailIfNeeded() async {
    if (_phase != _Phase.failed || _failRecorded) return;
    _failRecorded = true;
    await _svc.progress.recordResult(_result());
    _svc.analytics.log('stage_fail', {
      'stage': _stage.id,
      'reason': _session.failReason?.name ?? 'quit',
      'shipped': _session.shipped,
      'moves': _session.moves,
    });
  }

  void _pause() {
    if (_phase != _Phase.playing) return;
    _game.pauseEngine();
    setState(() => _phase = _Phase.paused);
  }

  void _resume() {
    _game.resumeEngine();
    setState(() => _phase = _Phase.playing);
  }

  Future<void> _retry() async {
    await _recordFailIfNeeded();
    _svc.analytics.log('stage_retry', {'stage': _stage.id});
    if (_phase == _Phase.cleared) await _svc.ads.onStageClearBreak();
    if (!mounted) return;
    setState(_setup);
  }

  Future<void> _exit() async {
    if (_phase == _Phase.paused || _phase == _Phase.playing) {
      _svc.analytics.log('stage_quit', {'stage': _stage.id});
    }
    await _recordFailIfNeeded();
    if (_phase == _Phase.cleared) await _svc.ads.onStageClearBreak();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _next() async {
    final next = _svc.stages.nextOf(_stage.id);
    await _svc.ads.onStageClearBreak();
    if (!mounted) return;
    if (next == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => GameScreen(stage: next)),
    );
  }

  Future<bool> _watchAd(RewardPlacement placement) async {
    if (_busy) return false;
    setState(() => _busy = true);
    _game.pauseEngine();
    final ok = await _svc.ads.showRewarded(placement);
    if (!mounted) return false;
    _game.resumeEngine();
    setState(() => _busy = false);
    if (!ok) showSnack(context, '広告を読み込めませんでした');
    return ok;
  }

  Future<void> _undo() async {
    if (!_session.canUndo || !_game.board.isIdle) return;
    if (_session.freeUndos > 0) {
      _session.undo();
    } else {
      if (!await _watchAd(RewardPlacement.hint)) return;
      _session.undo(paid: true);
      _svc.analytics.log('undo_ad', {'stage': _stage.id});
    }
    _svc.audio.play(Sfx.tap);
    _game.resync();
    _hud.value++;
  }

  Future<void> _hint() async {
    if (_phase != _Phase.playing || !_game.board.isIdle) return;
    if (!_freeHint && !await _watchAd(RewardPlacement.hint)) return;
    final lane = Solver(maxNodes: 30000).hint(_session);
    if (lane != null) _game.showHint(lane);
    _svc.analytics.log('hint_used', {'stage': _stage.id});
  }

  Future<void> _revive() async {
    if (!await _watchAd(RewardPlacement.revive)) return;
    if (_session.revive()) {
      _svc.analytics.log('revive', {'stage': _stage.id});
      _game.resync();
      setState(() => _phase = _Phase.playing);
    }
  }

  Future<void> _doubleCoins() async {
    final reward = _reward;
    if (reward == null || _coinsDoubled) return;
    final ok = await _watchAd(RewardPlacement.doubleCoins);
    if (ok) await _svc.progress.addCoins(reward.coins);
    if (mounted) setState(() => _coinsDoubled = ok);
  }

  @override
  Widget build(BuildContext context) {
    final skin = FactorySkin.fromId(_svc.progress.data.equippedSkin);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_phase == _Phase.playing) {
          _pause();
        } else if (_phase == _Phase.paused) {
          _resume();
        } else {
          _exit();
        }
      },
      child: Scaffold(
        backgroundColor: skin.background,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _Hud(
                    session: _session,
                    stage: _stage,
                    tick: _hud,
                    skin: skin,
                    freeHint: _freeHint,
                    onPause: _pause,
                    onUndo: _undo,
                    onHint: _hint,
                  ),
                  Expanded(
                    child: GameWidget(key: ObjectKey(_game), game: _game),
                  ),
                ],
              ),
            ),
            if (_phase == _Phase.tutorial) _tutorialOverlay(),
            if (_phase == _Phase.paused) _pauseOverlay(),
            if (_phase == _Phase.cleared) _clearOverlay(),
            if (_phase == _Phase.failed) _failOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _panel({required List<Widget> children}) => Positioned.fill(
    child: ColoredBox(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _title(String text, {Color color = AppColors.ink}) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color),
  );

  Widget _tutorialOverlay() {
    final t = tutorials[_stage.tutorial]!;
    return _panel(
      children: [
        Text(
          'STAGE ${_stage.id}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.w700,
          ),
        ),
        _title(t.title),
        const SizedBox(height: 16),
        for (final line in t.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            _svc.progress.markTutorialSeen(_stage.tutorial!);
            setState(_start);
          },
          child: const Text('スタート'),
        ),
      ],
    );
  }

  Widget _pauseOverlay() => _panel(
    children: [
      _title('ポーズ'),
      const SizedBox(height: 20),
      FilledButton(onPressed: _resume, child: const Text('つづける')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: _retry, child: const Text('最初からやりなおす')),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: _exit, child: const Text('ステージ選択へ')),
      const SizedBox(height: 6),
      ListenableBuilder(
        listenable: _svc.progress,
        builder: (context, _) => SwitchListTile(
          title: const Text('効果音'),
          value: _svc.progress.data.settings.sound,
          onChanged: (v) => _svc.progress.updateSettings((s) => s.sound = v),
        ),
      ),
    ],
  );

  Widget _clearOverlay() {
    final reward = _reward;
    final rec = _svc.progress.recordOf(_stage.id);
    final hasNext = _svc.stages.nextOf(_stage.id) != null;
    final stars = _session.stars;
    return _panel(
      children: [
        _title('ALL SHIPPED!', color: AppColors.success),
        const SizedBox(height: 8),
        Center(child: StarRow(stars, size: 48)),
        const SizedBox(height: 6),
        Text(
          stars == 3
              ? 'パーフェクト！'
              : '★3条件：棚に置くのは${_stage.par}回まで（今回${_session.shelfPlacements}回）',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: stars == 3 ? AppColors.coin : Colors.black54,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'スコア ${_session.score}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        Text(
          reward?.newBest == true ? 'ベスト更新！' : 'ベスト ${rec?.bestScore ?? 0}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: reward?.newBest == true ? AppColors.coin : Colors.black54,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '最大${_session.maxChain}連鎖　${_session.moves}手',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (reward != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.monetization_on, color: AppColors.coin),
              const SizedBox(width: 4),
              Text(
                '+${_coinsDoubled ? reward.coins * 2 : reward.coins}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (reward.leveledUp) ...[
                const SizedBox(width: 12),
                Text(
                  'Lv.${reward.levelAfter} にアップ！',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          for (final u in reward.newUnlocks)
            Text(
              '「${u.name}」を入手！',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 12),
          if (!_coinsDoubled && _svc.ads.rewardedAvailable)
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _doubleCoins,
              icon: const Icon(Icons.smart_display),
              label: const Text('広告を見てコイン2倍'),
            ),
        ],
        const SizedBox(height: 10),
        if (hasNext)
          FilledButton(onPressed: _next, child: const Text('次のステージ')),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _retry,
                child: Text(stars < 3 ? '★3に挑戦' : 'リトライ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _exit,
                child: const Text('ステージ選択'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _failOverlay() {
    final reason = _session.failReason;
    return _panel(
      children: [
        _title('おしい！', color: AppColors.danger),
        const SizedBox(height: 8),
        if (reason != null)
          Text(
            S.failReason(reason),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17),
          ),
        const SizedBox(height: 4),
        Text(
          '出荷 ${_session.shipped} / ${_session.totalTrucks} 台',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (_session.canRevive &&
            reason != null &&
            _svc.ads.rewardedAvailable) ...[
          FilledButton.icon(
            onPressed: _busy ? null : _revive,
            icon: const Icon(Icons.smart_display),
            label: Text(S.reviveLabel(reason)),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.tonal(onPressed: _retry, child: const Text('最初からやりなおす')),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: _exit, child: const Text('ステージ選択へ')),
      ],
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.session,
    required this.stage,
    required this.tick,
    required this.skin,
    required this.freeHint,
    required this.onPause,
    required this.onUndo,
    required this.onHint,
  });

  final GameSession session;
  final StageConfig stage;
  final ValueNotifier<int> tick;
  final FactorySkin skin;
  final bool freeHint;
  final VoidCallback onPause;
  final VoidCallback onUndo;
  final VoidCallback onHint;

  @override
  Widget build(BuildContext context) {
    final fg = skin.onBackground;
    return ValueListenableBuilder(
      valueListenable: tick,
      builder: (context, _, _) {
        final s = session;
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: onPause,
                icon: Icon(Icons.pause_circle_filled, size: 34, color: fg),
                tooltip: 'ポーズ',
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STAGE ${stage.id}  ${stage.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'スコア ${s.score}　棚 ${s.shelfPlacements}回（★3: ${stage.par}回以内）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _HudButton(
                icon: Icons.undo_rounded,
                label: '戻す',
                badge: s.freeUndos > 0 ? '${s.freeUndos}' : null,
                ad: s.freeUndos <= 0,
                onTap: s.canUndo ? onUndo : null,
              ),
              _HudButton(
                icon: Icons.lightbulb_rounded,
                label: 'ヒント',
                ad: !freeHint,
                onTap: s.status == SessionStatus.playing ? onHint : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.ad = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? badge;
  final bool ad;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: Colors.white.withValues(alpha: enabled ? 1 : 0.5),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: enabled ? AppColors.primary : Colors.black26,
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (badge != null || ad)
                  Positioned(
                    right: 3,
                    top: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: ad ? AppColors.coin : AppColors.success,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ad
                          ? const Icon(
                              Icons.smart_display,
                              size: 11,
                              color: Colors.white,
                            )
                          : Text(
                              badge!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
