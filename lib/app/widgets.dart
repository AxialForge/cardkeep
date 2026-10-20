import 'package:flutter/material.dart';

import '../core/db/tables.dart';
import 'theme.dart';

/// White rounded panel used for every grouped section in the mockups.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: Tokens.gutter, vertical: 6),
  });

  @override
  // A Material (not a decorated Container) so ListTile ink and tile colors paint on it.
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: Tokens.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radius),
        side: BorderSide(color: Tokens.hairline),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class Overline extends StatelessWidget {
  final String text;
  const Overline(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: AppText.overline);
}

/// Initials in a circle; brass ring on the detail header.
class Avatar extends StatelessWidget {
  final String initials;
  final double size;
  final bool dark;
  const Avatar(this.initials, {super.key, this.size = 44, this.dark = false});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: dark ? Tokens.headerTint : Tokens.selected,
      border: dark ? Border.all(color: Tokens.brass, width: 1.2) : null,
    ),
    // Initials scale with the circle, not the system text size.
    child: Text(
      initials,
      textScaler: TextScaler.noScaling,
      style: AppText.heading.copyWith(fontSize: size * 0.36, color: dark ? Tokens.onStrong : Tokens.ink),
    ),
  );
}

/// Small rounded label: lead rating, status, counts.
class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const Pill(this.text, {super.key, required this.bg, required this.fg});

  factory Pill.rating(LeadRating r) => switch (r) {
    LeadRating.hot => Pill('HOT', bg: Tokens.hotBg, fg: Tokens.hotFg),
    LeadRating.warm => Pill('WARM', bg: Tokens.amberBg, fg: Tokens.amberFg),
    LeadRating.cold => Pill('COLD', bg: Tokens.coldBg, fg: Tokens.coldFg),
  };

  static Pill? status(PersonStatus s) => switch (s) {
    PersonStatus.moved => Pill('Moved', bg: Tokens.amberBg, fg: Tokens.amberFg),
    PersonStatus.retired => Pill('Retired', bg: Tokens.selected, fg: Tokens.ink2),
    _ => null,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text(text, style: AppText.label.copyWith(color: fg, fontSize: 11.5)),
  );
}

String ratingLabel(LeadRating r) => switch (r) {
  LeadRating.hot => 'Hot',
  LeadRating.warm => 'Warm',
  LeadRating.cold => 'Cold',
};

/// Round icon button on a white disc (header buttons in the mockups).
class DiscButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool onDark;
  const DiscButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.onDark = false});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: onDark ? Tokens.onStrong.withValues(alpha: 0.12) : Tokens.surface,
      shape: CircleBorder(side: onDark ? BorderSide.none : BorderSide(color: Tokens.hairline)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: onDark ? Tokens.onStrong : Tokens.ink, size: 22, semanticLabel: tooltip),
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: Tokens.surface, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: Tokens.brass),
          ),
          const SizedBox(height: 16),
          Text(title, style: AppText.heading, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message, style: AppText.secondary, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Tokens.surface,
      title: Text(title, style: AppText.heading),
      content: Text(message, style: AppText.body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(action, style: TextStyle(color: destructive ? Tokens.hotFg : Tokens.ink)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showMessage(BuildContext context, String text, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action, duration: const Duration(seconds: 5)));
}
