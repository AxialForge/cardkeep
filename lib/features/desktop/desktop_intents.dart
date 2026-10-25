import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keyboard shortcuts of the Windows app (S16.11). One map, so it can be tested.
class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

class NewContactIntent extends Intent {
  const NewContactIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class GoBackIntent extends Intent {
  const GoBackIntent();
}

/// Ctrl+F search, Ctrl+N new contact, Ctrl+S save, Esc back.
Map<ShortcutActivator, Intent> desktopShortcutMap() => const {
  SingleActivator(LogicalKeyboardKey.keyF, control: true): FocusSearchIntent(),
  SingleActivator(LogicalKeyboardKey.keyN, control: true): NewContactIntent(),
  SingleActivator(LogicalKeyboardKey.keyS, control: true): SaveIntent(),
  SingleActivator(LogicalKeyboardKey.escape): GoBackIntent(),
};
