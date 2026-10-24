/// Which version of the tour this build carries. Bump it when the tour changes
/// enough that finished users should hear about it.
const tourVersion = '0.7.3';

/// What to show when CardKeep opens.
enum OnboardingStart {
  /// A new user: run the tour.
  tour,

  /// Someone upgrading with data already in the app: a short "What's new"
  /// sheet that offers the tour instead of forcing it.
  whatsNew,

  /// Nothing.
  none,
}

/// The routing rule (S15a.8), kept pure so it is easy to test.
///
/// * [doneVersion]: the tour version finished or skipped (null = never).
/// * [whatsNewSeen]: the version whose sheet was already shown.
/// * [hasData]: the library already holds contacts or queued cards.
OnboardingStart decideOnboarding({required String? doneVersion, required String? whatsNewSeen, required bool hasData}) {
  if (doneVersion != null) return OnboardingStart.none;
  if (!hasData) return OnboardingStart.tour;
  return whatsNewSeen == tourVersion ? OnboardingStart.none : OnboardingStart.whatsNew;
}

/// The show-once rule for coach marks (S15a.5).
bool shouldShowTip(String id, {required bool tipsEnabled, required Set<String> seen, String? forced}) =>
    forced == id || (tipsEnabled && !seen.contains(id));
