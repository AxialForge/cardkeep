import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import 'desktop_actions.dart';
import 'desktop_intents.dart';
import 'desktop_providers.dart';

/// Wraps the whole Windows app: keyboard shortcuts (Ctrl+F, Ctrl+N, Esc) and
/// files dropped on the window (S16.11). Only used on Windows.
class DesktopRoot extends ConsumerStatefulWidget {
  final GoRouter router;
  final GlobalKey<ScaffoldMessengerState> messenger;
  final Widget child;

  /// Tests: stands in for the real drop target.
  final Widget Function(Widget child, void Function(List<String>) onDrop, void Function(bool) onHover)? dropBuilder;

  const DesktopRoot({super.key, required this.router, required this.messenger, required this.child, this.dropBuilder});

  @override
  ConsumerState<DesktopRoot> createState() => _DesktopRootState();
}

class _DesktopRootState extends ConsumerState<DesktopRoot> {
  bool _hovering = false;

  /// Esc must not take Back away from a text box that is being typed in.
  bool get _typing => isTypingIn(FocusManager.instance.primaryFocus);

  Future<void> _onDrop(List<String> paths) async {
    setState(() => _hovering = false);
    final line = await handleDroppedFiles(ref, widget.router, paths);
    widget.messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(line), duration: const Duration(seconds: 6), persist: false));
  }

  @override
  Widget build(BuildContext context) {
    final body = Stack(
      children: [
        widget.child,
        if (_hovering)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Tokens.brass.withValues(alpha: 0.12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                    decoration: BoxDecoration(
                      color: Tokens.surface,
                      borderRadius: BorderRadius.circular(Tokens.radius),
                      border: Border.all(color: Tokens.brass, width: 2),
                    ),
                    child: Text('Drop contact files, spreadsheets or card photos', style: AppText.heading),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    final dropBuilder = widget.dropBuilder;
    final target = dropBuilder != null
        ? dropBuilder(body, _onDrop, (h) => setState(() => _hovering = h))
        : DropTarget(
            onDragEntered: (_) => setState(() => _hovering = true),
            onDragExited: (_) => setState(() => _hovering = false),
            onDragDone: (d) => _onDrop([for (final f in d.files) f.path]),
            child: body,
          );
    return Shortcuts(
      shortcuts: desktopShortcutMap(),
      child: Actions(
        actions: {
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(
            onInvoke: (_) {
              final here = widget.router.state.uri.path;
              if (here != '/') widget.router.go('/');
              ref.read(focusSearchProvider.notifier).bump();
              return null;
            },
          ),
          NewContactIntent: CallbackAction<NewContactIntent>(
            onInvoke: (_) {
              widget.router.push('/contact/new');
              return null;
            },
          ),
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (_) {
              ref.read(saveRequestProvider.notifier).bump();
              return null;
            },
          ),
          GoBackIntent: _BackAction(widget.router, () => _typing),
        },
        child: Focus(autofocus: true, canRequestFocus: false, child: target),
      ),
    );
  }
}

/// True when [focus] sits inside a text field (the focused widget is the Focus
/// the field builds, so its text field is an ancestor, not the widget itself).
bool isTypingIn(FocusNode? focus) => focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

class _BackAction extends Action<GoBackIntent> {
  final GoRouter router;
  final bool Function() typing;
  _BackAction(this.router, this.typing);

  @override
  bool isEnabled(GoBackIntent intent) => !typing() && router.canPop();

  @override
  Object? invoke(GoBackIntent intent) {
    router.pop();
    return null;
  }
}
