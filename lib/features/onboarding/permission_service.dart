import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'content/content_model.dart';

/// Where a permission stands, in the words the tour uses.
enum PermState {
  /// Never asked (Android also reports this before the first request).
  notAsked,
  granted,

  /// Asked and refused; Android will show the prompt again.
  denied,

  /// Refused for good: only the phone's settings can change it.
  blocked,
}

/// The tour talks to permissions through this so tests can fake every answer.
abstract class PermissionService {
  Future<PermState> status(PermKind kind);

  /// Shows the system prompt (a no-op returning the current state if already
  /// granted or blocked).
  Future<PermState> request(PermKind kind);

  Future<void> openSettings();
}

class SystemPermissionService implements PermissionService {
  Permission _of(PermKind k) => switch (k) {
    PermKind.camera => Permission.camera,
    PermKind.notifications => Permission.notification,
  };

  PermState _map(PermissionStatus s, {bool asked = false}) {
    if (s.isGranted || s.isLimited || s.isProvisional) return PermState.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return PermState.blocked;
    return asked ? PermState.denied : PermState.notAsked;
  }

  @override
  Future<PermState> status(PermKind kind) async {
    if (kIsWeb) return PermState.notAsked;
    try {
      return _map(await _of(kind).status);
    } catch (_) {
      return PermState.notAsked;
    }
  }

  @override
  Future<PermState> request(PermKind kind) async {
    try {
      return _map(await _of(kind).request(), asked: true);
    } catch (_) {
      return PermState.denied;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }
}
