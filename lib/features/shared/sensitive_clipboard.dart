import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('cardkeep/incoming');

/// Copies contact details marked sensitive, so Android 13+ does not show them
/// in the clipboard preview (audit MOB-SEC-0007). Elsewhere a plain copy.
Future<void> copySensitive(String text) async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await _channel.invokeMethod('copySensitive', {'text': text});
      return;
    } catch (_) {}
  }
  await Clipboard.setData(ClipboardData(text: text));
}

/// Keeps CardKeep out of the recents thumbnail and screenshots (MOB-SEC-0004).
Future<void> setHideInRecents(bool on) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod('setSecure', on);
  } catch (_) {}
}
