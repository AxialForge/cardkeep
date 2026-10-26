import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/drawer.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/platform/platform_info.dart';
import '../../core/sync/net/sync_client.dart';
import 'desktop_sync.dart';
import 'sync_providers.dart';
import 'webcam/webcam_qr_dialog.dart';

/// Sync with phone (Windows): paste the code from the phone, pair, sync, unpair (S16.8, S16.9).
class DesktopSyncScreen extends ConsumerStatefulWidget {
  const DesktopSyncScreen({super.key});

  @override
  ConsumerState<DesktopSyncScreen> createState() => _DesktopSyncScreenState();
}

class _DesktopSyncScreenState extends ConsumerState<DesktopSyncScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) setState(() => _code.text = data!.text!.trim());
  }

  /// Reads the code from the phone's screen with the PC's webcam, then pairs (S16.12).
  Future<void> _scan() async {
    final notifier = ref.read(desktopSyncProvider.notifier);
    final outcome = await showWebcamQrDialog(
      context,
      source: ref.read(webcamSourceFactoryProvider)(),
      onCode: (text) async {
        if (mounted) setState(() => _code.text = text);
        return notifier.pair(text);
      },
    );
    if (outcome == WebcamQrOutcome.paste && mounted) await _paste();
  }

  Future<void> _unpair() async {
    final ok = await confirm(
      context,
      title: 'Unpair from the phone?',
      message: 'This PC keeps its copy of your contacts, but it stops syncing with the phone until you pair again. Pairing a different phone later starts from a full copy.',
      action: 'Unpair',
      destructive: true,
    );
    if (ok) await ref.read(desktopSyncProvider.notifier).unpair();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(desktopSyncProvider);
    final conflicts = ref.watch(openConflictsProvider).value ?? 0;
    return Scaffold(
      drawer: const AppDrawer(current: '/sync'),
      appBar: AppBar(title: const Text('Sync with phone')),
      body: !s.loaded
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    if (s.notice != null) _Note(s.notice!, good: true),
                    if (s.error != null) _Note(s.error!, good: false),
                    if (!s.paired) ..._pairing(s) else ..._paired(s, conflicts),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
                      child: Overline('If it will not connect'),
                    ),
                    Panel(
                      child: Text(
                        'This PC connects out to your phone, so Windows Firewall needs no rule. Both must be on the same Wi-Fi: a guest network, a VPN or a router that isolates devices blocks it. The phone must have Sync to desktop open. If you move to a new Wi-Fi, pair again.',
                        style: AppText.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _pairing(DesktopSyncState s) => [
    const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 6), child: Overline('Pair with your phone')),
    Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('1. On the phone, open the menu and choose Sync to desktop.', style: AppText.body),
          const SizedBox(height: 6),
          Text('2. Tap Copy code text, then paste it here (the code works for 2 minutes).', style: AppText.body),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            minLines: 2,
            maxLines: 4,
            enabled: !s.busy,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'cardkeep-sync:…',
              labelText: 'Pairing code from the phone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: s.busy ? null : _paste,
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste'),
              ),
              if (PlatformInfo.isDesktop) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: s.busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan with webcam'),
                ),
              ],
              const SizedBox(width: 10),
              FilledButton(
                onPressed: s.busy || _code.text.trim().isEmpty
                    ? null
                    : () => ref.read(desktopSyncProvider.notifier).pair(_code.text),
                child: Text(s.busy ? 'Pairing…' : 'Pair'),
              ),
            ],
          ),
          if (s.busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          const SizedBox(height: 10),
          Text('Your contacts go only between your phone and this PC, over your own Wi-Fi.', style: AppText.secondary),
        ],
      ),
    ),
  ];

  List<Widget> _paired(DesktopSyncState s, int conflicts) {
    final host = s.host!;
    final last = s.peer?.lastSyncAt;
    final p = s.progress;
    return [
      const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 6), child: Overline('Paired phone')),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smartphone, color: Tokens.brassText),
                const SizedBox(width: 10),
                Expanded(child: Text(host.hostName, style: AppText.heading)),
                TextButton(onPressed: s.busy ? null : _unpair, child: const Text('Unpair')),
              ],
            ),
            const SizedBox(height: 4),
            Text('${host.host}:${host.port}', style: AppText.secondary),
            Text(
              last == null ? 'Not synced yet' : 'Last synced ${DateFormat('MMM d, h:mm a').format(last)}',
              style: AppText.secondary,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: s.busy ? null : () => ref.read(desktopSyncProvider.notifier).syncNow(),
              icon: const Icon(Icons.sync),
              label: Text(s.busy ? 'Syncing…' : 'Sync now'),
            ),
            if (s.busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: p != null && p.total > 0 ? p.done / p.total : null),
              const SizedBox(height: 6),
              Text(p?.message ?? 'Connecting…', style: AppText.secondary),
            ],
            if (s.last != null && !s.busy) ...[const SizedBox(height: 12), _ResultLine(s.last!)],
          ],
        ),
      ),
      if (conflicts > 0)
        Panel(
          child: Row(
            children: [
              Icon(Icons.call_split, color: Tokens.brassText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$conflicts field${conflicts == 1 ? '' : 's'} changed on both devices. You choose which to keep.',
                  style: AppText.body,
                ),
              ),
              TextButton(onPressed: () => context.push('/sync/conflicts'), child: const Text('Review')),
            ],
          ),
        ),
      Panel(
        child: Row(
          children: [
            Expanded(child: Text('Sync automatically while CardKeep is open', style: AppText.body)),
            DropdownButton<int>(
              value: autoSyncChoices.contains(s.autoMinutes) ? s.autoMinutes : 10,
              items: [
                for (final m in autoSyncChoices)
                  DropdownMenuItem(value: m, child: Text(m == 0 ? 'Only when I ask' : 'Every $m minutes')),
              ],
              onChanged: (m) {
                if (m != null) ref.read(desktopSyncProvider.notifier).setAutoMinutes(m);
              },
            ),
          ],
        ),
      ),
    ];
  }
}

class _Note extends StatelessWidget {
  final String text;
  final bool good;
  const _Note(this.text, {required this.good});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 0),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: good ? Tokens.selected : Tokens.amberBg,
        borderRadius: BorderRadius.circular(Tokens.radius),
      ),
      child: Text(text, style: AppText.body.copyWith(color: good ? Tokens.ink : Tokens.amberFg)),
    ),
  );
}

/// "Received 12, sent 3, 4 photos" for the last round.
class _ResultLine extends StatelessWidget {
  final SyncRoundResult r;
  const _ResultLine(this.r);

  @override
  Widget build(BuildContext context) {
    final bits = [
      '${r.received} received',
      '${r.sent} sent',
      if (r.imagesDown + r.imagesUp > 0) '${r.imagesDown + r.imagesUp} photos',
      if (r.conflicts > 0) '${r.conflicts} to review',
    ];
    return Text('Synced: ${bits.join(', ')}.', style: AppText.secondary);
  }
}
