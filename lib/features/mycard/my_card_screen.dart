import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/drawer.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/db/database.dart';
import '../../core/vcard/vcard.dart';

const _key = 'my_card';

/// Your own card, stored in app_settings as JSON (S13.11).
final myCardProvider = StreamProvider<ExportContact?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.appSettings)..where((s) => s.key.equals(_key))).watchSingleOrNull().map((r) {
    if (r == null) return null;
    final j = (jsonDecode(r.value) as Map).cast<String, Object?>();
    String s(String k) => '${j[k] ?? ''}';
    return ExportContact(
      first: s('first'),
      last: s('last'),
      title: s('title').isEmpty ? null : s('title'),
      company: s('company').isEmpty ? null : s('company'),
      emails: [if (s('email').isNotEmpty) s('email')],
      phones: [
        if (s('mobile').isNotEmpty) (label: 'Mobile', number: s('mobile')),
        if (s('office').isNotEmpty) (label: 'Office', number: s('office')),
      ],
      website: s('website').isEmpty ? null : s('website'),
      address: s('address').isEmpty ? null : s('address'),
    );
  });
});

/// My card (mockup MyCard): show a QR others can scan, share as a .vcf.
class MyCardScreen extends ConsumerWidget {
  const MyCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myCardProvider).value;
    return Scaffold(
      drawer: const AppDrawer(current: '/mycard'),
      appBar: AppBar(
        title: const Text('My card'),
        actions: [
          if (me != null)
            IconButton(
              tooltip: 'Edit my card',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(context, ref, me),
            ),
        ],
      ),
      body: me == null
          ? Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  const EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'Your own card',
                    message:
                        'Add your details once. Then show a QR code to share them, or send them as a contact file.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => _edit(context, ref, null), child: const Text('Add my details')),
                ],
              ),
            )
          : ListView(
              children: [
                Panel(
                  child: Column(
                    children: [
                      Text(me.fullName, style: AppText.title),
                      if ((me.title ?? '').isNotEmpty || (me.company ?? '').isNotEmpty)
                        Text([me.title, me.company].whereType<String>().join(' · '), style: AppText.secondary),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => _FullQr(data: writeVCard(me)),
                          ),
                        ),
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(data: writeVCard(me), size: 240, semanticsLabel: 'QR code of my card'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Tap the code to show it full screen', style: AppText.secondary),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Tokens.gutter),
                  child: FilledButton.icon(
                    onPressed: () {
                      final name = '${me.fullName.isEmpty ? 'My card' : me.fullName}.vcf';
                      SharePlus.instance.share(
                        ShareParams(
                          files: [
                            XFile.fromData(
                              Uint8List.fromList(utf8.encode(writeVCard(me))),
                              name: name,
                              mimeType: 'text/vcard',
                            ),
                          ],
                          fileNameOverrides: [name],
                        ),
                      );
                    },
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share as contact file'),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ExportContact? me) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MyCardForm(me: me),
  );
}

class _MyCardForm extends ConsumerStatefulWidget {
  final ExportContact? me;
  const _MyCardForm({this.me});
  @override
  ConsumerState<_MyCardForm> createState() => _MyCardFormState();
}

class _MyCardFormState extends ConsumerState<_MyCardForm> {
  late final Map<String, TextEditingController> _c = {
    'first': TextEditingController(text: widget.me?.first),
    'last': TextEditingController(text: widget.me?.last),
    'title': TextEditingController(text: widget.me?.title),
    'company': TextEditingController(text: widget.me?.company),
    'mobile': TextEditingController(
      text: widget.me?.phones.where((p) => p.label == 'Mobile').map((p) => p.number).firstOrNull,
    ),
    'office': TextEditingController(
      text: widget.me?.phones.where((p) => p.label == 'Office').map((p) => p.number).firstOrNull,
    ),
    'email': TextEditingController(text: widget.me?.emails.firstOrNull),
    'website': TextEditingController(text: widget.me?.website),
    'address': TextEditingController(text: widget.me?.address),
  };
  static const _labels = {
    'first': 'First name',
    'last': 'Last name',
    'title': 'Title',
    'company': 'Company',
    'mobile': 'Mobile',
    'office': 'Office phone',
    'email': 'Email',
    'website': 'Website',
    'address': 'Address',
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    final json = jsonEncode({for (final e in _c.entries) e.key: e.value.text.trim()});
    await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: _key, value: json));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('My details', style: AppText.heading),
          for (final e in _c.entries) ...[
            const SizedBox(height: 10),
            TextField(
              controller: e.value,
              autofocus: e.key == 'first' && widget.me == null,
              keyboardType: switch (e.key) {
                'mobile' || 'office' => TextInputType.phone,
                'email' => TextInputType.emailAddress,
                'website' => TextInputType.url,
                _ => TextInputType.text,
              },
              textCapitalization: switch (e.key) {
                'first' || 'last' || 'title' || 'company' || 'address' => TextCapitalization.words,
                _ => TextCapitalization.none,
              },
              decoration: InputDecoration(labelText: _labels[e.key]),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    ),
  );
}

/// Full-screen QR at full brightness, restored on close.
class _FullQr extends StatefulWidget {
  final String data;
  const _FullQr({required this.data});
  @override
  State<_FullQr> createState() => _FullQrState();
}

class _FullQrState extends State<_FullQr> {
  @override
  void initState() {
    super.initState();
    ScreenBrightness.instance.setApplicationScreenBrightness(1.0).catchError((_) {});
  }

  @override
  void dispose() {
    ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: QrImageView(data: widget.data, semanticsLabel: 'QR code of my card'),
      ),
    ),
  );
}
