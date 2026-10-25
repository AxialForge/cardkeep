import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// How an unlock attempt ended (S15.2).
enum AuthResult {
  /// The fingerprint, face or phone passcode was right.
  success,

  /// Tried and did not match.
  failed,

  /// The person closed the prompt, or Android did (for example the app went to the background).
  cancelled,

  /// The phone has no screen lock, so there is nothing to ask for.
  unavailable,

  /// Too many wrong tries; Android asks the person to wait.
  lockedOut,
}

/// The phone's own fingerprint, face or passcode check. CardKeep never sees or
/// stores a password of its own, so there is nothing to forget.
abstract class AuthService {
  /// True when the phone has a fingerprint, face or screen lock to ask for.
  Future<bool> isAvailable();

  Future<AuthResult> authenticate(String reason);
}

class LocalAuthService implements AuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AuthResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(localizedReason: reason);
      return ok ? AuthResult.success : AuthResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable => AuthResult.unavailable,
        LocalAuthExceptionCode.temporaryLockout || LocalAuthExceptionCode.biometricLockout => AuthResult.lockedOut,
        _ => AuthResult.cancelled,
      };
    } catch (_) {
      return AuthResult.cancelled;
    }
  }
}
