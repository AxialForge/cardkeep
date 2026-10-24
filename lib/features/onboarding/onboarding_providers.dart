import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/demo/demo_data.dart';
import '../tags/tags_screen.dart';
import 'permission_service.dart';

/// Replaced with a fake in tests.
final permissionServiceProvider = Provider<PermissionService>((ref) => SystemPermissionService());

final demoDataProvider = Provider(
  (ref) => DemoData(ref.watch(databaseProvider), ref.watch(contactsRepoProvider), ref.watch(tagsRepoProvider)),
);

/// How many demo contacts exist; drives "Remove demo data".
final demoCountProvider = StreamProvider<int>((ref) => ref.watch(demoDataProvider).watchCount());

final tipsEnabledProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepoProvider).watchTipsEnabled());
final tipsSeenProvider = StreamProvider<Set<String>>((ref) => ref.watch(settingsRepoProvider).watchTipsSeen());

/// "Try it" in a lesson forces that screen's coach mark to show once, even if
/// tips are off or already seen.
class CoachForce extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

final coachForceProvider = NotifierProvider<CoachForce, String?>(CoachForce.new);

/// Where the app keeps its data, in words (overridden in tests, where there is
/// no documents folder).
final appFolderLabelProvider = FutureProvider<String>((ref) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  } catch (_) {
    return "CardKeep's private storage";
  }
});
