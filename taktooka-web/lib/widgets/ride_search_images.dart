import 'package:taktooka/widgets/app_notice.dart';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class RideSearchImages extends StatefulWidget {
  final List<String> assets;
  const RideSearchImages({super.key, required this.assets});

  @override
  State<RideSearchImages> createState() => _RideSearchImagesState();
}

class _RideSearchImagesState extends State<RideSearchImages>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  Timer? _timer, _limitTimer;
  Future<void> _audioQueue = Future<void>.value();
  int _index = 0;
  int _holdGeneration = 0;
  int? _pointer;
  Offset? _downPosition;
  bool _hornRequested = false;
  bool _foreground = true;
  bool _closing = false;

  void _queueAudio(Future<void> Function() action) {
    _audioQueue = _audioQueue.then((_) => action()).catchError((Object error) {
      if (mounted && !_closing) {
        showAppNotice(context, 'تعذّر تشغيل الصوت');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _queueAudio(() async {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setSource(AssetSource('audio/tuktuk_horn.mp3'));
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          _foreground &&
          widget.assets.length > 1 &&
          !MediaQuery.disableAnimationsOf(context)) {
        setState(() => _index = (_index + 1) % widget.assets.length);
      }
    });
  }

  void _beginHold(PointerDownEvent event) {
    if (_pointer != null) return;
    final generation = ++_holdGeneration;
    _pointer = event.pointer;
    _downPosition = event.position;
    {
      if (!mounted ||
          _closing ||
          !_foreground ||
          _pointer == null ||
          generation != _holdGeneration)
        return;
      _hornRequested = true;
      _limitTimer = Timer(const Duration(seconds: 10), _endHold);
      _queueAudio(() async {
        if (!_hornRequested || _closing || generation != _holdGeneration)
          return;
        await _player.resume();
        if (!_hornRequested || _closing || generation != _holdGeneration)
          await _player.pause();
      });
    }
  }

  void _endHold() {
    _holdGeneration++;
    _pointer = null;
    _downPosition = null;
    _limitTimer?.cancel();
    _hornRequested = false;
    _queueAudio(() async {
      await _player.pause();
      await _player.seek(Duration.zero);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _endHold();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final asset in widget.assets) {
      unawaited(precacheImage(AssetImage(asset), context));
    }
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _endHold();
    _queueAudio(() => _player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.assets.isEmpty
      ? const SizedBox.shrink()
      : Listener(
          onPointerDown: _beginHold,
          onPointerUp: (event) {
            if (event.pointer == _pointer) _endHold();
          },
          onPointerCancel: (event) {
            if (event.pointer == _pointer) _endHold();
          },
          onPointerMove: (event) {
            if (event.pointer == _pointer &&
                _downPosition != null &&
                (event.position - _downPosition!).distance > 18)
              _endHold();
          },
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                widget.assets[_index % widget.assets.length],
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
}
