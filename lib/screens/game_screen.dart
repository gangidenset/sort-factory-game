import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app/services.dart';
import '../data/progress_controller.dart';
import '../game/flame/sort_factory_game.dart';
import '../game/logic/game_session.dart';
import '../game/logic/models.dart';
import '../game/logic/deduction.dart';
import '../game/logic/stage_config.dart';
import '../services/ads/ad_service.dart';
import '../services/audio/audio_service.dart';
import '../ui/palette.dart';
import '../ui/strings.dart';
import '../ui/widgets.dart';

enum _Phase { tutorial, playing, paused, cleared }

/// What the panel under the board is saying.
enum _MsgKind { hint, guide, blocked }

class _Msg {
  const _Msg(this.kind, this.text);
  final _MsgKind kind;
  final String text;
}

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
  bool _busy = false;
  bool _initialized = false;
  _Msg? _msg;
  Timer? _msgTimer;
  final _clock = Stopwatch();
  final _hud = ValueNotifier(0);

  AppServices get _svc => context.services;
  StageConfig get _stage => widget.stage;

  /// The first stages teach the rules: hints there are free and do not
  /// cost stars.
  bool get _practice => _stage.id <= 3;

  bool get _finale => _game.boardReady && _game.board.inFinale;

  /// Stage 1 walks the player through the solution, one explained step at
  /// a time ("tap the glowing cell").
  bool get _guided => _stage.id == 1 && _svc.progress.data.settings.showHints;

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
    _msgTimer?.cancel();
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
      onCue: _onCue,
      onSolved: _onSolved,
      onBlocked: _onBlocked,
    );
    _reward = null;
    _coinsDoubled = false;
    _msg = null;
    _msgTimer?.cancel();
    _clock
      ..reset()
      ..stop();
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
    _clock.start();
    // Runs inside setup/build: set the message directly, no setState.
    if (_guided) _msg = _guideMsg();
    final svc = _svc;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      svc.progress.recordAttempt(_stage.id);
      svc.analytics.log('stage_start', {
        'stage': _stage.id,
        'attempt': _attempt,
      });
    });
  }

  void _onCue(BoardCue cue, int step) {
    final audio = _svc.audio;
    switch (cue) {
      case BoardCue.box:
        audio.feedback(Sfx.correct);
      case BoardCue.cross || BoardCue.erase:
        audio.feedback(Sfx.tap);
      case BoardCue.lineDone:
        audio.feedback(Sfx.truck);
      case BoardCue.shipStep:
        // Pitch climbs as the convoy leaves.
        final total = _stage.trucks.length;
        audio.chainPitch(2 + ((step - 1) * 4) ~/ (total > 1 ? total - 1 : 1));
        audio.haptic(Sfx.truck);
      case BoardCue.shipDone:
        audio.feedback(Sfx.clear);
    }
    if (cue == BoardCue.box || cue == BoardCue.cross || cue == BoardCue.erase) {
      if (_guided && !_session.isCleared) {
        _guide();
      } else if (_msg?.kind == _MsgKind.hint &&
          (!_game.boardReady || _game.board.hint == null)) {
        // The hinted cell was handled: back to the rule reminder.
        _say(null);
      } else if (_msg?.kind == _MsgKind.blocked) {
        _say(null);
      }
    }
    if (_session.isCleared && _msg != null) _say(null);
    _hud.value++;
  }

  void _say(_Msg? msg, {Duration? clearAfter}) {
    _msgTimer?.cancel();
    if (!mounted) return;
    setState(() => _msg = msg);
    if (clearAfter != null) {
      _msgTimer = Timer(clearAfter, () {
        if (!mounted) return;
        // After a refusal, go back to whatever guidance was showing.
        if (_guided && !_session.isCleared) {
          _guide();
        } else {
          setState(() => _msg = null);
        }
      });
    }
  }

  /// Guided stage: always show the next logical step with its reason.
  void _guide() => _say(_guideMsg());

  _Msg _guideMsg() {
    final h = Deduction.next(_session);
    _game.showHint(h);
    final text = switch (h.mark) {
      Mark.box => '光っているマスをタップ！\n${h.reason}',
      Mark.cross => '光っているマスを2回タップして×に。\n${h.reason}',
      Mark.none => h.reason,
    };
    return _Msg(_MsgKind.guide, text);
  }

  void _onBlocked(String reason) {
    _svc.audio.feedback(Sfx.wrong);
    _say(
      _Msg(_MsgKind.blocked, 'ここには置けません：$reason'),
      clearAfter: const Duration(milliseconds: 2600),
    );
  }

  StageResult _result() => StageResult(
    stageId: _stage.id,
    cleared: _session.isCleared,
    score: _session.score,
    stars: _session.stars,
    deliveries: _session.isCleared ? _stage.boxCount : 0,
    seconds: _clock.elapsed.inSeconds.toDouble(),
  );

  /// The shipping finale finished: show the result.
  Future<void> _onSolved() async {
    if (!mounted || _phase == _Phase.cleared) return;
    _clock.stop();
    setState(() => _phase = _Phase.cleared);
    final reward = await _svc.progress.recordResult(_result());
    _svc.analytics.log('stage_clear', {
      'stage': _stage.id,
      'stars': _session.stars,
      'hints': _session.hintsUsed,
      'moves': _session.moves,
      'seconds': _clock.elapsed.inSeconds,
    });
    if (mounted) setState(() => _reward = reward);
  }

  void _pause() {
    if (_phase != _Phase.playing || _finale) return;
    _clock.stop();
    _game.pauseEngine();
    setState(() => _phase = _Phase.paused);
  }

  void _resume() {
    _clock.start();
    _game.resumeEngine();
    setState(() => _phase = _Phase.playing);
  }

  Future<void> _retry() async {
    _svc.analytics.log('stage_retry', {'stage': _stage.id});
    if (_phase == _Phase.cleared) await _svc.ads.onStageClearBreak();
    if (!mounted) return;
    setState(_setup);
  }

  Future<void> _exit() async {
    if (_phase == _Phase.paused || _phase == _Phase.playing) {
      _svc.analytics.log('stage_quit', {
        'stage': _stage.id,
        'placed': _session.boxesPlaced,
        'seconds': _clock.elapsed.inSeconds,
      });
    }
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

  void _undo() {
    if (_finale || !_session.undo()) return;
    _svc.audio.play(Sfx.tap);
    _game.refresh();
    if (_guided) _guide();
    _hud.value++;
  }

  void _reset() {
    _session.reset();
    _game.refresh();
    _resume();
    if (_guided) _guide();
  }

  Future<void> _hint() async {
    if (_phase != _Phase.playing || _finale) return;
    if (!_practice) {
      final free = _session.freeHints > 0;
      if (!free && !await _watchAd(RewardPlacement.hint)) return;
      _session.consumeHint(paid: !free);
    }
    final hint = Deduction.next(_session);
    _game.showHint(hint);
    _svc.analytics.log('hint_used', {
      'stage': _stage.id,
      'n': _session.hintsUsed,
    });
    _say(_Msg(_MsgKind.hint, hint.reason));
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
                    practice: _practice,
                    onPause: _pause,
                    onUndo: _undo,
                    onHint: _hint,
                  ),
                  Expanded(
                    child: GameWidget(key: ObjectKey(_game), game: _game),
                  ),
                  _BottomPanel(msg: _msg, skin: skin),
                ],
              ),
            ),
            if (_phase == _Phase.tutorial) _tutorialOverlay(),
            if (_phase == _Phase.paused) _pauseOverlay(),
            if (_phase == _Phase.cleared) _clearOverlay(),
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
      OutlinedButton(onPressed: _reset, child: const Text('盤面をまっさらにする')),
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
    final hasNext = _svc.stages.nextOf(_stage.id) != null;
    final stars = _session.stars;
    final secs = _clock.elapsed.inSeconds;
    return _panel(
      children: [
        _title('ALL SHIPPED!', color: AppColors.success),
        const SizedBox(height: 8),
        Center(child: StarRow(stars, size: 48)),
        const SizedBox(height: 6),
        Text(
          stars == 3 ? 'ヒントなしで解けました！' : 'ヒント ${_session.hintsUsed}回（ヒントなしで★3）',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: stars == 3 ? AppColors.coin : Colors.black54,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'タイム ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
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
        if (hasNext) FilledButton(onPressed: _next, child: const Text('次のパズル')),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _retry,
                child: Text(stars < 3 ? '★3に挑戦' : 'もう一度'),
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
}

/// Rule reminder, or the explanation of the current hint.
class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.msg, required this.skin});
  final _Msg? msg;
  final FactorySkin skin;

  @override
  Widget build(BuildContext context) {
    final m = msg;
    final (bg, icon, iconColor) = switch (m?.kind) {
      _MsgKind.blocked => (
        const Color(0xFFFFE3E3),
        Icons.block_rounded,
        AppColors.danger,
      ),
      _MsgKind.guide => (
        const Color(0xFFE3F0FF),
        Icons.touch_app_rounded,
        AppColors.primary,
      ),
      _MsgKind.hint => (
        const Color(0xFFFFF4D6),
        Icons.lightbulb_rounded,
        AppColors.coin,
      ),
      null => (
        Colors.white.withValues(alpha: skin.isDark ? 0.12 : 0.85),
        null,
        null,
      ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: m != null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.text,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          : _RuleCard(color: skin.onBackground),
    );
  }
}

/// The three rules, each with a tiny picture.
class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> icons, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 84, child: Row(children: icons)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: color.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    const truck = Icon(
      Icons.local_shipping_rounded,
      size: 20,
      color: AppColors.primary,
    );
    const box = Icon(
      Icons.inventory_2_rounded,
      size: 18,
      color: Color(0xFFD9A066),
    );
    final no = Icon(
      Icons.close_rounded,
      size: 16,
      color: AppColors.danger.withValues(alpha: 0.9),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(const [truck, box], 'トラックのとなりに箱を1つずつ'),
        row([box, no, box], '箱どうしはくっつけない（ななめも）'),
        row([
          Text(
            '2',
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward_rounded, size: 16),
          box,
          box,
        ], '数字＝その列・行の箱の数'),
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
    required this.practice,
    required this.onPause,
    required this.onUndo,
    required this.onHint,
  });

  final GameSession session;
  final StageConfig stage;
  final ValueNotifier<int> tick;
  final FactorySkin skin;
  final bool practice;
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
                      '箱 ${s.boxesPlaced} / ${stage.boxCount}　${stage.size}×${stage.size}',
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
                onTap: s.canUndo ? onUndo : null,
              ),
              _HudButton(
                icon: Icons.lightbulb_rounded,
                label: 'ヒント',
                badge: practice
                    ? '∞'
                    : (s.freeHints > 0 ? '${s.freeHints}' : null),
                ad: !practice && s.freeHints <= 0,
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
