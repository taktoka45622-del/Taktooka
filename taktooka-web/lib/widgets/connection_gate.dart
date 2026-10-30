import 'dart:async';

import 'package:flutter/material.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/connection_monitor.dart';

class ConnectionGate extends StatefulWidget {
  final Widget child;
  final ConnectionMonitor? monitor;
  const ConnectionGate({super.key, required this.child, this.monitor});

  @override
  State<ConnectionGate> createState() => _ConnectionGateState();
}

class _ConnectionGateState extends State<ConnectionGate>
    with WidgetsBindingObserver {
  late final monitor = widget.monitor ?? connectionMonitor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    monitor.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) monitor.start();
    });
  }

  void changed() {
    if (!mounted) return;
    if (monitor.status == NetworkStatus.offline) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      monitor.start();
    } else {
      monitor.pause();
    }
  }

  @override
  void dispose() {
    monitor.removeListener(changed);
    monitor.pause();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = monitor.status == NetworkStatus.offline;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: blocked,
          child: ExcludeSemantics(
            excluding: blocked,
            child: IgnorePointer(ignoring: blocked, child: widget.child),
          ),
        ),
        if (blocked)
          Positioned.fill(
            child: ConnectionScreen(
              checking:
                  monitor.checking || monitor.status == NetworkStatus.unknown,
              offline: monitor.status == NetworkStatus.offline,
              retry: () => unawaited(monitor.check()),
            ),
          ),
      ],
    );
  }
}

class ConnectionScreen extends StatefulWidget {
  final bool checking, offline;
  final VoidCallback retry;
  const ConnectionScreen({
    super.key,
    required this.checking,
    required this.offline,
    required this.retry,
  });

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppText(
                    'تكتوكة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: AnimatedBuilder(
                      animation: motion,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(
                          MediaQuery.disableAnimationsOf(context)
                              ? 0
                              : (motion.value - .5) * 14,
                          0,
                        ),
                        child: child,
                      ),
                      child: Container(
                        width: 144,
                        height: 144,
                        decoration: BoxDecoration(
                          color: scarlet.withValues(alpha: .08),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scarlet.withValues(alpha: .12),
                          ),
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/brand.png',
                            width: 104,
                            height: 88,
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (widget.offline) ...[
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: scarlet,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    const AppText(
                      'لا يوجد اتصال بالإنترنت',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const AppText(
                      'حاول مرة ثانية',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 16),
                    ),
                    const SizedBox(height: 26),
                    FilledButton.icon(
                      onPressed: widget.checking ? null : widget.retry,
                      icon: widget.checking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: AppText(
                        widget.checking
                            ? 'جاري فحص الاتصال…'
                            : 'إعادة المحاولة',
                      ),
                    ),
                  ] else ...[
                    const AppText(
                      'جاري فحص الاتصال…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(color: scarlet),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
