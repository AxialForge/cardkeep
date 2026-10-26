import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/platform/platform_info.dart';
import '../contacts/contact_detail_screen.dart';
import '../contacts/contacts_screen.dart';
import 'desktop_providers.dart';

/// Width at which the Windows app shows the list and a contact side by side.
const twoPaneMinWidth = 900.0;
const twoPaneListWidth = 420.0;

/// True when the layout for [width] is list on the left and contact on the right.
bool useTwoPane(double width) => PlatformInfo.isDesktop && width >= twoPaneMinWidth;

/// Tells the contact rows below it that tapping selects (right pane) rather than opens a page.
class TwoPane extends InheritedWidget {
  final bool active;
  const TwoPane({super.key, required this.active, required super.child});

  static bool activeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TwoPane>()?.active ?? false;

  @override
  bool updateShouldNotify(TwoPane old) => old.active != active;
}

/// The home screen. On a phone, or a narrow Windows window, it is the Contacts
/// list alone; on a wide window it is the list beside the chosen contact (S16.11).
class DesktopHome extends ConsumerWidget {
  const DesktopHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, box) {
        if (!useTwoPane(box.maxWidth)) return const TwoPane(active: false, child: ContactsScreen());
        final selected = ref.watch(selectedContactProvider);
        return Row(
          children: [
            const SizedBox(
              width: twoPaneListWidth,
              child: TwoPane(active: true, child: ContactsScreen()),
            ),
            VerticalDivider(width: 1, thickness: 1, color: Tokens.hairline),
            Expanded(
              child: selected == null
                  ? const _NothingSelected()
                  : ContactDetailScreen(key: ValueKey(selected), id: selected, embedded: true),
            ),
          ],
        );
      },
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) => Material(
    child: ColoredBox(
      color: Tokens.ground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: 48, color: Tokens.hairline),
            const SizedBox(height: 12),
            Text('Choose a contact', style: AppText.heading),
            const SizedBox(height: 4),
            Text('Its details and card show here. Ctrl+F searches, Ctrl+N adds one.', style: AppText.secondary),
          ],
        ),
      ),
    ),
  );
}
