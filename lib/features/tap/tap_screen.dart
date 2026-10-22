import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ndef_record/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/contacts/contact_models.dart';
import '../../core/tags/tags_repository.dart';
import '../../core/vcard/vcard.dart';
import '../../nfc/ndef.dart';
import '../events/events_screens.dart';
import '../shared/sensitive_clipboard.dart';
import '../tags/tags_screen.dart';

enum _Nfc { checking, unsupported, off, listening }

/// One card read in this session.
class _Read {
  final TapContent content;
  final DateTime at;
  bool saved = false;
  _Read(this.content, this.at);
}

/// Tap cards (mockup TapCard, S14.1-S14.13). Android keeps reading card after
/// card (reader mode); each tap gives a buzz and adds a row.
class TapScreen extends ConsumerStatefulWidget {
  const TapScreen({super.key});
  @override
  ConsumerState<TapScreen> createState() => _TapScreenState();
}

class _TapScreenState extends ConsumerState<TapScreen> with WidgetsBindingObserver {
  static const _channel = MethodChannel('cardkeep/incoming');
  _Nfc _state = _Nfc.checking;
  final _reads = <_Read>[];
  final _debounce = TapDebounce();
  bool _sessionOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  // Back from NFC settings: check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && _state != _Nfc.listening) _start();
    if (s == AppLifecycleState.paused) _stop();
  }

  Future<void> _start() async {
    final NfcAvailability a;
    try {
      a = await NfcManager.instance.checkAvailability();
    } catch (_) {
      if (mounted) setState(() => _state = _Nfc.unsupported);
      return;
    }
    if (!mounted) return;
    if (a != NfcAvailability.enabled) {
      setState(() => _state = a == NfcAvailability.disabled ? _Nfc.off : _Nfc.unsupported);
      return;
    }
    setState(() => _state = _Nfc.listening);
    if (_sessionOn) return;
    _sessionOn = true;
    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      noPlatformSoundsAndroid: true,
      onDiscovered: _onTag,
    );
  }

  void _stop() {
    if (!_sessionOn) return;
    _sessionOn = false;
    NfcManager.instance.stopSession().catchError((_) {});
  }

  Future<void> _onTag(NfcTag tag) async {
    TapContent content;
    try {
      final ndef = Ndef.from(tag);
      final msg = ndef?.cachedMessage ?? await ndef?.read();
      final recs = [
        for (final r in msg?.records ?? const <NdefRecord>[]) Rec(r.typeNameFormat.index, r.type, r.payload),
      ];
      // A non-NDEF tag (payment card, door badge) is not read further (S14.8).
      content = ndef == null ? const TapUnsupported('Not a business card (no NDEF data)') : interpret(recs);
    } on FormatException catch (e) {
      content = TapUnsupported('Unreadable tag: ${e.message}');
    } catch (_) {
      content = const TapUnsupported('Tag moved away too soon. Hold it still and try again.');
    }
    final uid = defaultTargetPlatform == TargetPlatform.android ? NfcTagAndroid.from(tag)?.id : null;
    if (_debounce.isRepeat(tapKey(uid, content), DateTime.now())) return;
    unawaited(HapticFeedback.mediumImpact());
    if (mounted) setState(() => _reads.insert(0, _Read(content, DateTime.now())));
  }

  ContactDraft _draftOf(ExportContact c, {String? link}) => ContactDraft(
    first: c.first,
    last: c.last,
    company: c.company ?? '',
    title: c.title ?? '',
    phones: [
      for (final p in c.phones) LabeledValue(p.label.toLowerCase().startsWith('m') ? 'Mobile' : 'Office', p.number),
    ],
    emails: c.emails,
    website: c.website ?? link ?? '',
    address: c.address ?? '',
    notes: c.notes ?? '',
  );

  /// Link cards: keep just the link on a new contact with the "NFC link" tag (S14.6).
  Future<void> _saveLinkOnly(_Read r, TapLink l) async {
    final id = await ref
        .read(contactsRepoProvider)
        .save(
          ContactDraft(first: l.title ?? l.url.host, website: l.url.toString(), notes: 'Saved from an NFC link card'),
        );
    final tags = ref.read(tagsRepoProvider);
    await tags.setTags(id, {await tags.ensureSystem(SystemTag.nfcLink)});
    final session = await ref.read(eventsRepoProvider).watchActive().first;
    if (session != null) await ref.read(eventsRepoProvider).setMetAt(id, session.event.uuid);
    setState(() => r.saved = true);
    if (mounted) showMessage(context, 'Saved the link. Fill in the name from their page when you know it.');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Tap a card')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.gutter, 4, Tokens.gutter, 0),
              child: Pill('Adding to ${session.event.name}', bg: Tokens.amberBg, fg: Tokens.amberFg),
            ),
          Panel(child: _status()),
          if (_reads.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Overline('Read this time (${_reads.length})'),
            ),
          for (final r in _reads) _tile(r),
        ],
      ),
    );
  }

  Widget _status() => switch (_state) {
    _Nfc.checking => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    ),
    _Nfc.unsupported => const EmptyState(
      icon: Icons.nfc,
      title: 'No NFC on this phone',
      message: 'Tap cards need NFC. You can still scan paper cards with the camera.',
    ),
    _Nfc.off => Column(
      children: [
        const EmptyState(icon: Icons.nfc, title: 'NFC is off', message: 'Turn on NFC to read tap cards.'),
        FilledButton(
          onPressed: () => _channel.invokeMethod<void>('openNfcSettings').catchError((_) {}),
          child: const Text('Open NFC settings'),
        ),
      ],
    ),
    _Nfc.listening => Column(
      children: [
        const Icon(Icons.contactless_outlined, size: 72, color: Tokens.brandOrange),
        const SizedBox(height: 10),
        Text('Hold a card to the back of the phone', style: AppText.heading, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          // Antenna tip (S14.13): on most Android phones it's in the middle of the back, near the camera on some.
          'The reader is usually in the middle of the back. Keep the card still for a second. You can tap card after card.',
          style: AppText.secondary,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  };

  Widget _tile(_Read r) {
    final launcher = ref.read(launcherProvider);
    return Panel(
      child: switch (r.content) {
        TapContact(:final contact, :final link) => _row(
          Icons.contact_page_outlined,
          contact.fullName.isEmpty ? (contact.company ?? 'Contact') : contact.fullName,
          [contact.title, contact.company].whereType<String>().join(' · '),
          [
            FilledButton(
              onPressed: r.saved
                  ? null
                  : () async {
                      setState(() => r.saved = true);
                      await context.push('/contact/new', extra: _draftOf(contact, link: link));
                    },
              child: Text(r.saved ? 'Opened' : 'Review and save'),
            ),
          ],
        ),
        TapLink(:final url, :final title) => _row(Icons.link, title ?? url.host, url.toString(), [
          TextButton(
            onPressed: r.saved ? null : () => _saveLinkOnly(r, r.content as TapLink),
            child: const Text('Save link only'),
          ),
          FilledButton(onPressed: () => launcher.web(url.toString()), child: const Text('Open')),
        ]),
        TapText(:final text) => _row(Icons.notes, 'Text', text, [
          TextButton(
            onPressed: () {
              copySensitive(text);
              showMessage(context, 'Copied');
            },
            child: const Text('Copy'),
          ),
        ]),
        TapEmpty() => _row(Icons.crop_square, 'Empty tag', 'Nothing is written on it.', const []),
        TapUnsupported(:final why) => _row(Icons.block, 'Not read', why, const []),
      },
    );
  }

  Widget _row(IconData icon, String title, String sub, List<Widget> actions) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(icon, color: Tokens.ink2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                if (sub.isNotEmpty) Text(sub, style: AppText.secondary, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
      if (actions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.end, spacing: 8, children: actions),
      ],
    ],
  );
}
