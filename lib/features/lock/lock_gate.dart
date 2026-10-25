import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lock/lock_controller.dart';
import 'lock_screen.dart';

/// Sits above the whole app. While CardKeep is locked the app underneath stays
/// alive (a scan in progress carries on) but is hidden and cannot be reached,
/// not even by TalkBack. It also watches the app going to the background and
/// coming back, which is when the lock timer runs (S15.2).
class LockGate extends ConsumerStatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Opened locked: ask straight away, once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(lockControllerProvider).locked) ref.read(lockControllerProvider.notifier).unlock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final lock = ref.read(lockControllerProvider.notifier);
    switch (s) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        lock.leftApp();
      case AppLifecycleState.resumed:
        lock.returned();
        if (ref.read(lockControllerProvider).locked) lock.unlock();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(lockControllerProvider.select((s) => s.locked));
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: locked,
          child: Visibility(visible: !locked, maintainState: true, child: widget.child),
        ),
        if (locked) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}
