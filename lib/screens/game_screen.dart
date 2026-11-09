import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app/services.dart';
import '../data/progress_controller.dart';
import '../game/flame/sort_factory_game.dart';
import '../game/logic/game_session.dart';
import '../game/logic/models.dart';
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
  Timer? _hudTimer;
  final _hud = ValueNotifier(0);

  AppServices get _svc => context.services;
  StageConfig get _stage => widget.stage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool _initialized = false;

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
    _hudTimer?.cancel();
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
      onEvents: _onEvents,
      alwaysHint: _stage.id <= 2 && progress.data.settings.showHints,
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
    // May run during build (first frame): notify listeners after it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      svc.progress.recordAttempt(_stage.id);
      svc.analytics.log('stage_start', {
        'stage': _stage.id,
        'attempt': _attempt,
      });
    });
    _hudTimer?.cancel();
    _hudTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _hud.value++,
    );
  }

  void _onEvents(List<SessionEvent> events) {
    final audio = _svc.audio;
    for (final e in events) {
      switch (e.type) {
        case SessionEventType.correct:
          audio.feedback(Sfx.correct);
        case SessionEventType.wrong || SessionEventType.expired:
          audio.feedback(Sfx.wrong);
        case SessionEventType.stored || SessionEventType.discarded:
          audio.feedback(Sfx.store);
        case SessionEventType.truckDeparted:
          audio.feedback(Sfx.truck);
        case SessionEventType.comboMilestone:
          audio.feedback(Sfx.combo);
        case SessionEventType.cleared:
          scheduleMicrotask(_onCleared);
        case SessionEventType.failed:
          scheduleMicrotask(_onFailed);
        case SessionEventType.spawned:
          break;
      }
    }
    _hud.value++;
  }

  StageResult _result() => StageResult(
    stageId: _stage.id,
    cleared: _session.status == SessionStatus.cleared,
    score: _session.score,
    stars: _session.stars,
    deliveries: _session.delivered,
    maxCombo: _session.maxCombo,
    timedDelivered: _session.timedDelivered,
    seconds: _session.elapsed,
  );

  Future<void> _onCleared() async {
    if (!mounted || _phase == _Phase.cleared) return;
    _hudTimer?.cancel();
    _svc.audio.feedback(Sfx.clear);
    setState(() => _phase = _Phase.cleared);
    final reward = await _svc.progress.recordResult(_result());
    _svc.analytics.log('stage_clear', {
      'stage': _stage.id,
      'score': _session.score,
      'stars': _session.stars,
      'seconds': _session.elapsed.round(),
      'mistakes': _session.mistakes,
      'revived': _session.revivesUsed,
    });
    if (mounted) setState(() => _reward = reward);
  }

  void _onFailed() {
    if (!mounted || _phase == _Phase.failed) return;
    _hudTimer?.cancel();
    _svc.audio.feedback(Sfx.fail);
    setState(() => _phase = _Phase.failed);
  }

  /// Records a failure once the player gives up (not before a revive choice).
  Future<void> _recordFailIfNeeded() async {
    if (_phase != _Phase.failed || _failRecorded) return;
    _failRecorded = true;
    await _svc.progress.recordResult(_result());
    _svc.analytics.log('stage_fail', {
      'stage': _stage.id,
      'reason': _session.failReason?.name ?? 'quit',
      'delivered': _session.delivered,
      'seconds': _session.elapsed.round(),
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

  Future<void> _revive() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _svc.ads.showRewarded(RewardPlacement.revive);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && _session.revive()) {
      _svc.analytics.log('revive', {'stage': _stage.id});
      _phase = _Phase.playing;
      _hudTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _hud.value++,
      );
      setState(() {});
    } else if (!ok) {
      showSnack(context, '広告を読み込めませんでした');
    }
  }

  Future<void> _doubleCoins() async {
    final reward = _reward;
    if (_busy || reward == null || _coinsDoubled) return;
    setState(() => _busy = true);
    final ok = await _svc.ads.showRewarded(RewardPlacement.doubleCoins);
    if (ok) await _svc.progress.addCoins(reward.coins);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _coinsDoubled = ok;
    });
    if (!ok) showSnack(context, '広告を読み込めませんでした');
  }

  Future<void> _hint() async {
    if (_busy || _phase != _Phase.playing) return;
    _game.pauseEngine();
    setState(() => _busy = true);
    final ok = await _svc.ads.showRewarded(RewardPlacement.hint);
    if (!mounted) return;
    if (ok) {
      _game.hintTime = 20;
      _svc.analytics.log('hint_used', {'stage': _stage.id});
    } else {
      showSnack(context, '広告を読み込めませんでした');
    }
    _game.resumeEngine();
    setState(() => _busy = false);
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
                    onPause: _pause,
                    onHint: _game.alwaysHint ? null : _hint,
                    hintActive: () => _game.hintActive,
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
      OutlinedButton(onPressed: _retry, child: const Text('やりなおす')),
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
    return _panel(
      children: [
        _title('STAGE CLEAR!', color: AppColors.success),
        const SizedBox(height: 8),
        Center(child: StarRow(_session.stars, size: 44)),
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
          '最大コンボ ${_session.maxCombo}　ミス ${_session.mistakes}',
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
              '🎁 「${u.name}」を入手！',
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
                child: const Text('リトライ'),
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
        _title('FAILED', color: AppColors.danger),
        const SizedBox(height: 8),
        if (reason != null)
          Text(
            S.failReason(reason),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17),
          ),
        const SizedBox(height: 4),
        Text(
          '配送 ${_session.delivered} / ${_stage.targetDeliveries}',
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
        FilledButton.tonal(onPressed: _retry, child: const Text('リトライ')),
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
    required this.onPause,
    required this.onHint,
    required this.hintActive,
  });

  final GameSession session;
  final StageConfig stage;
  final ValueNotifier<int> tick;
  final FactorySkin skin;
  final VoidCallback onPause;
  final VoidCallback? onHint;
  final bool Function() hintActive;

  @override
  Widget build(BuildContext context) {
    final fg = skin.onBackground;
    return ValueListenableBuilder(
      valueListenable: tick,
      builder: (context, _, _) {
        final s = session;
        final progress = s.delivered / stage.targetDeliveries;
        final livesLeft = stage.maxMistakes - s.mistakes;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onPause,
                    icon: Icon(Icons.pause_circle_filled, size: 36, color: fg),
                    tooltip: 'ポーズ',
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STAGE ${stage.id}　配送 ${s.delivered}/${stage.targetDeliveries}',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0, 1),
                            minHeight: 10,
                            backgroundColor: fg.withValues(alpha: 0.12),
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${s.score}',
                    style: TextStyle(
                      color: fg,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 12),
                  for (var i = 0; i < stage.maxMistakes; i++)
                    Icon(
                      i < livesLeft ? Icons.favorite : Icons.favorite_border,
                      color: AppColors.danger,
                      size: 20,
                    ),
                  const SizedBox(width: 10),
                  if (s.combo >= 2)
                    Text(
                      '${s.combo} COMBO',
                      style: const TextStyle(
                        color: AppColors.coin,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  const Spacer(),
                  if (s.timeLeft != null)
                    _pill(
                      Icons.timer,
                      '${s.timeLeft!.ceil()}秒',
                      s.timeLeft! < 10,
                      fg,
                    ),
                  if (s.movesLeft != null)
                    _pill(
                      Icons.touch_app,
                      '残り${s.movesLeft}手',
                      s.movesLeft! <= 3,
                      fg,
                    ),
                  if (onHint != null)
                    TextButton.icon(
                      onPressed: hintActive() ? null : onHint,
                      icon: const Icon(Icons.lightbulb, size: 18),
                      label: Text(hintActive() ? 'ヒント中' : 'ヒント'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(IconData icon, String text, bool urgent, Color fg) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        icon,
        size: 16,
        color: urgent ? Colors.white : AppColors.ink,
      ),
      backgroundColor: urgent ? AppColors.danger : Colors.white,
      label: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: urgent ? Colors.white : AppColors.ink,
        ),
      ),
    ),
  );
}
