import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';

/// The build number from pubspec (`0.7.4+18` -> 18). Split APKs add an offset per
/// ABI (+1000 armeabi-v7a, +2000 arm64-v8a, +4000 x86_64) to Android's versionCode,
/// so the number the phone reports is 2018, not 18.
String displayBuildNumber(String raw) {
  final n = int.tryParse(raw);
  if (n == null) return raw;
  return '${n % 1000}';
}

const repoUrl = 'https://github.com/AxialForge/cardkeep';
const privacyUrl = 'https://github.com/AxialForge/cardkeep#privacy';
const issuesPageUrl = 'https://github.com/AxialForge/cardkeep/issues';

/// What stays on the phone and the few things that can leave it, in plain words.
/// The same facts as the privacy section of the README and the tour.
const stayOnPhone = <String>[
  'Your contacts, notes, tags, events and follow-ups.',
  'Card photos and logos.',
  'Reading the text on a card: it happens on the phone, with no internet.',
  'Reminders and backups made by CardKeep.',
];

const canLeavePhone = <String>[
  'Checking for updates asks GitHub for the list of releases. It sends nothing about you, and only runs when you tap Check for updates or switch on "Check when CardKeep opens".',
  'A phone call, email, text, map or web link opens in another app, only when you tap it.',
  'A file you export, a contact you share or a backup you save goes where you choose to send it.',
  'Sync to desktop sends your contacts and card photos to the PC you paired, over your own Wi-Fi, only while that screen is open. Nothing goes through the internet or an account.',
];

/// About CardKeep (S15.11): version, licences, privacy, changelog, issues.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launcher = ref.read(launcherProvider);
    Future<void> open(String url) async {
      if (!await launcher.web(url) && context.mounted) {
        showMessage(context, 'No browser found to open $url');
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('About CardKeep')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Tokens.brandIvory, borderRadius: BorderRadius.circular(14)),
                  child: Image.asset('assets/brand/cardkeep-mark-256.png', semanticLabel: 'CardKeep logo'),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CardKeep', style: AppText.title),
                      FutureBuilder(
                        future: PackageInfo.fromPlatform(),
                        builder: (_, s) => Text(
                          s.data == null
                              ? ''
                              : 'Version ${s.data!.version} (build ${displayBuildNumber(s.data!.buildNumber)})',
                          style: AppText.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'A business card organizer that keeps everything on your phone. No account, no cloud, no analytics.',
              style: AppText.body,
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('What leaves your phone')),
          Panel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stays on your phone', style: AppText.bodyStrong),
                const SizedBox(height: 6),
                for (final t in stayOnPhone) _Bullet(t),
                const SizedBox(height: 14),
                Text('Can leave it, only when you choose', style: AppText.bodyStrong),
                const SizedBox(height: 6),
                for (final t in canLeavePhone) _Bullet(t),
                const SizedBox(height: 14),
                Text(
                  'CardKeep has no analytics, no crash reporting and no advertising. Android\'s cloud backup is switched off for it.',
                  style: AppText.secondary,
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('More')),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: Text('Privacy policy', style: AppText.body),
                  subtitle: Text('The privacy section on GitHub', style: AppText.secondary),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => open(privacyUrl),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: Text('What\'s changed', style: AppText.body),
                  subtitle: Text('The changelog, version by version', style: AppText.secondary),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/about/changelog'),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: Text('Open-source licences', style: AppText.body),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(context: context, applicationName: 'CardKeep'),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: Text('Report an issue', style: AppText.body),
                  subtitle: Text('Opens GitHub in your browser', style: AppText.secondary),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => open(issuesPageUrl),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: Text('CardKeep on GitHub', style: AppText.body),
                  subtitle: Text(repoUrl, style: AppText.secondary),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => open(repoUrl),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: Text('Copy version details', style: AppText.body),
                  subtitle: Text('Handy when you report a problem', style: AppText.secondary),
                  onTap: () async {
                    final info = await PackageInfo.fromPlatform();
                    await Clipboard.setData(
                      ClipboardData(text: 'CardKeep ${info.version} (build ${displayBuildNumber(info.buildNumber)})'),
                    );
                    if (context.mounted) showMessage(context, 'Copied');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7, right: 10),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: Tokens.brass, shape: BoxShape.circle),
          ),
        ),
        Expanded(child: Text(text, style: AppText.body)),
      ],
    ),
  );
}
