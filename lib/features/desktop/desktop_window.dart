import 'dart:async';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/settings/settings_repository.dart';
import 'window_bounds.dart';

/// Opens the Windows window where it was last time and remembers where it ends
/// up (S16.11). Does nothing on other platforms: main() only calls it on Windows.
class DesktopWindow with WindowListener {
  final SettingsRepository settings;
  Timer? _save;
  DesktopWindow._(this.settings);

  static Future<void> init(SettingsRepository settings) async {
    await windowManager.ensureInitialized();
    final saved = WindowBounds.decode(await settings.windowBounds());
    final screens = <Rect>[];
    try {
      for (final d in await screenRetriever.getAllDisplays()) {
        final p = d.visiblePosition ?? Offset.zero;
        final s = d.visibleSize ?? d.size;
        screens.add(Rect.fromLTWH(p.dx, p.dy, s.width, s.height));
      }
    } catch (_) {
      // no display list: open where Windows puts it
    }
    final bounds = saved?.onScreen(screens);
    final options = WindowOptions(
      size: bounds == null ? WindowBounds.defaultSize : Size(bounds.width, bounds.height),
      minimumSize: WindowBounds.minSize,
      center: bounds == null,
      title: 'CardKeep',
    );
    final me = DesktopWindow._(settings);
    windowManager.addListener(me);
    await windowManager.waitUntilReadyToShow(options, () async {
      if (bounds != null) {
        await windowManager.setBounds(bounds.rect);
        if (bounds.maximized) await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// Saves a moment after the last move or resize, not on every pixel.
  void _later() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), _write);
  }

  Future<void> _write() async {
    try {
      final maximized = await windowManager.isMaximized();
      // A maximized window keeps the size it had before, so restoring it later looks right.
      if (maximized) {
        final old = WindowBounds.decode(await settings.windowBounds());
        if (old != null) {
          await settings.setWindowBounds(
            WindowBounds(old.left, old.top, old.width, old.height, maximized: true).encode(),
          );
        }
        return;
      }
      final r = await windowManager.getBounds();
      await settings.setWindowBounds(WindowBounds(r.left, r.top, r.width, r.height).encode());
    } catch (_) {
      // the window is closing: nothing to save
    }
  }

  @override
  void onWindowResized() => _later();
  @override
  void onWindowMoved() => _later();
  @override
  void onWindowMaximize() => _later();
  @override
  void onWindowUnmaximize() => _later();
}
