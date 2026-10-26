import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/drawer.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/sync/sync_engine.dart';
import '../shared/sensitive_clipboard.dart';
import 'qr_fullscreen.dart';
import 'sync_providers.dart';

/// Sync to desktop (S16): while this screen is open the phone listens on your
/// Wi-Fi, shows a pairing code, and lets your PC fetch and send changes. Leave
/// the screen and the phone stops listening.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The phone must stay awake or the PC loses it mid-sync.
    try {
      unawaited(WakelockPlus.enable().catchError((_) {}));
    } catch (_) {}
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(syncHostProvider).payload != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    try {
      unawaited(WakelockPlus.disable().catchError((_) {}));
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncHostProvider);
    final host = ref.read(syncHostProvider.notifier);
    final conflicts = ref.watch(openConflictsProvider).value ?? 0;
    return Scaffold(
      drawer: const AppDrawer(current: '/sync'),
      appBar: AppBar(title: const Text('Sync to desktop')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (s.phase == SyncHostPhase.starting)
            const Panel(
              child: Row(
                children: [
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  SizedBox(width: 14),
                  Expanded(child: Text('Getting ready…')),
                ],
              ),
            ),
          if (s.phase == SyncHostPhase.noNetwork)
            EmptyState(
              icon: Icons.wifi_off,
              title: 'Not on Wi-Fi',
              message:
                  'Sync only works on your own network. Connect this phone to the same Wi-Fi as your PC, then try '
                  'again. No Wi-Fi? Turn on this phone\'s hotspot and join it from the PC.',
              action: FilledButton(onPressed: host.start, child: const Text('Try again')),
            ),
          if (s.phase == SyncHostPhase.failed)
            EmptyState(
              icon: Icons.error_outline,
              title: 'Could not start',
              message: 'CardKeep could not open the sync connection (${s.error ?? 'unknown error'}).',
              action: FilledButton(onPressed: host.start, child: const Text('Try again')),
            ),
          if (s.phase == SyncHostPhase.ready) ...[
            if (s.notice != null || s.activity.isNotEmpty)
              Panel(
                child: Row(
                  children: [
                    if (s.activity.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(right: 14),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Icon(Icons.check_circle_outline, color: Tokens.brass),
                      ),
                    Expanded(child: Text(s.activity.isNotEmpty ? s.activity : s.notice!, style: AppText.body)),
                  ],
                ),
              ),
            if (conflicts > 0) _ConflictsBanner(count: conflicts),
            if (s.peers.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 6), child: Overline('Paired PC')),
              for (final p in s.peers) _PeerTile(peer: p, onUnpair: () => _unpair(context, host, p)),
              if (s.payload == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'On your PC, open CardKeep and press Sync. Keep this screen open until it says Synced.',
                    style: AppText.secondary,
                  ),
                ),
            ],
            if (s.payload == null && s.peers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _pairAnother(context, host, s.peers.first),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Pair a different PC'),
                  ),
                ),
              ),
            if (s.payload != null) _PairingPanel(state: s, onNewCode: host.newCode),
            const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('What happens to your data')),
            Panel(
              child: Text(
                'Your contacts and card photos go straight from this phone to your own PC over your Wi-Fi. Nothing '
                'passes through the internet, a server or an account. Only the PC you pair can ask, only while this '
                'screen is open, and only devices on your own network are answered.',
                style: AppText.body,
              ),
            ),
          ],
          const _Troubleshooting(),
        ],
      ),
    );
  }

  Future<void> _unpair(BuildContext context, SyncHostController host, SyncPeer p) async {
    final ok = await confirm(
      context,
      title: 'Unpair ${p.name}?',
      message:
          'The PC keeps its copy of your contacts, but it can no longer sync with this phone until you pair again.',
      action: 'Unpair',
      destructive: true,
    );
    if (ok) await host.unpair(p.id);
  }

  Future<void> _pairAnother(BuildContext context, SyncHostController host, SyncPeer current) async {
    final ok = await confirm(
      context,
      title: 'Pair a different PC?',
      message:
          'CardKeep syncs with one PC. Pairing another one unpairs ${current.name}, and the new PC starts with a full copy.',
      action: 'Show a new code',
    );
    if (ok) await host.newCode();
  }
}

class _ConflictsBanner extends StatelessWidget {
  final int count;
  const _ConflictsBanner({required this.count});

  @override
  Widget build(BuildContext context) => Panel(
    padding: EdgeInsets.zero,
    child: ListTile(
      leading: Icon(Icons.call_split, color: Tokens.hotFg),
      title: Text('$count field${count == 1 ? '' : 's'} changed on both devices', style: AppText.bodyStrong),
      subtitle: const Text('Choose which value to keep. Until then each device keeps its own.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/sync/conflicts'),
    ),
  );
}

class _PeerTile extends StatelessWidget {
  final SyncPeer peer;
  final VoidCallback onUnpair;
  const _PeerTile({required this.peer, required this.onUnpair});

  static String when(DateTime? t) {
    if (t == null) return 'Not synced yet';
    final ago = DateTime.now().difference(t);
    if (ago.inSeconds < 60) return 'Synced just now';
    if (ago.inMinutes < 60) return 'Synced ${ago.inMinutes} min ago';
    return 'Synced ${DateFormat('MMM d, h:mm a').format(t)}';
  }

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.computer, color: Tokens.brass),
            const SizedBox(width: 12),
            Expanded(child: Text(peer.name, style: AppText.heading)),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 36),
          child: Text(when(peer.lastSyncAt), style: AppText.secondary),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: onUnpair, child: const Text('Unpair')),
        ),
      ],
    ),
  );
}

class _PairingPanel extends StatelessWidget {
  final SyncHostState state;
  final Future<void> Function() onNewCode;
  const _PairingPanel({required this.state, required this.onNewCode});

  @override
  Widget build(BuildContext context) {
    final payload = state.payload!;
    final left = state.codeExpiresAt?.difference(DateTime.now()) ?? Duration.zero;
    final expired = left <= Duration.zero;
    final mm = left.inMinutes.remainder(60).toString();
    final ss = left.inSeconds.remainder(60).toString().padLeft(2, '0');
    final side = (MediaQuery.sizeOf(context).width - 96).clamp(160.0, 260.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('Pair your PC')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. On your PC, open CardKeep and choose Sync with a phone.', style: AppText.body),
              const SizedBox(height: 6),
              Text('2. Scan this code with the PC\'s camera, or paste the text under it.', style: AppText.body),
              const SizedBox(height: 6),
              Text('3. Keep this screen open while it syncs.', style: AppText.body),
              const SizedBox(height: 16),
              Center(
                child: Opacity(
                  opacity: expired ? 0.25 : 1,
                  child: InkWell(
                    key: const Key('qr-enlarge'),
                    onTap: expired ? null : () => showQrFullScreen(context, data: payload.toQrText()),
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(10),
                      child: QrImageView(
                        data: payload.toQrText(),
                        size: side,
                        backgroundColor: Colors.white,
                        semanticsLabel: 'Pairing code for your PC. Tap to make it big and bright.',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Tap the code to make it big and bright for the PC\'s camera.',
                  style: AppText.secondary,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  expired ? 'This code has expired.' : 'This code works for $mm:$ss.',
                  style: expired ? AppText.bodyStrong : AppText.secondary,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Phone address ${payload.host}:${payload.port}',
                  style: AppText.secondary,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(onPressed: onNewCode, child: const Text('New code')),
                  OutlinedButton(
                    onPressed: expired
                        ? null
                        : () async {
                            await copySensitive(payload.toQrText());
                            if (context.mounted) {
                              showMessage(context, 'Code copied. Paste it into CardKeep on your PC.');
                            }
                          },
                    child: const Text('Copy code text'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Troubleshooting extends StatelessWidget {
  const _Troubleshooting();

  @override
  Widget build(BuildContext context) => Panel(
    padding: EdgeInsets.zero,
    margin: const EdgeInsets.fromLTRB(Tokens.gutter, 18, Tokens.gutter, 6),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text('Trouble connecting?', style: AppText.bodyStrong),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• The phone and the PC must be on the same Wi-Fi. A guest network often blocks devices from seeing each '
            'other.\n'
            '• Keep this screen open and the phone awake.\n'
            '• On the PC, allow CardKeep through the Windows firewall when it asks (private networks only).\n'
            '• A VPN on either device can hide it from the other: switch it off while syncing.',
            style: AppText.body,
          ),
          const SizedBox(height: 10),
          Text('No shared Wi-Fi?', style: AppText.bodyStrong),
          const SizedBox(height: 4),
          Text(
            'Turn on this phone\'s hotspot (Android Settings › Connections › Mobile Hotspot), join it from the PC, and '
            'open this screen again. The PC reaches the phone over the hotspot.',
            style: AppText.body,
          ),
          const SizedBox(height: 10),
          Text('Can\'t connect at all?', style: AppText.bodyStrong),
          const SizedBox(height: 4),
          Text('Move your library with a backup file instead.', style: AppText.body),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => context.go('/export'), child: const Text('Open Export and backup')),
          ),
        ],
      ),
    ),
  );
}
