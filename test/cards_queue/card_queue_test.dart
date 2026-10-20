import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/core/cards/card_queue_repository.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/scan/quality.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ScannedSide side(String hash, List<String> lines, {List<double>? heights, List<QualityIssue> issues = const [], List<String> qr = const []}) =>
    ScannedSide(
      hash: hash,
      thumb: Uint8List(0),
      issues: issues,
      ocr: OcrPage.fromText(lines, heights: heights),
      qrRaw: qr,
    );

void main() {
  late AppDatabase db;
  late Directory dir;
  late CardQueueRepository q;
  late ContactsRepository contacts;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('ck_queue');
    q = CardQueueRepository(db, ImageStore(dir));
    contacts = ContactsRepository(db);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  final clean = side('h1', ['Acme Corp', 'Jo Park', 'Plant Manager', 'M 330-555-0142', 'jo@acme.com'], heights: [14, 22, 11, 9, 9]);

  test('enqueue, restore from the database, link to a person', () async {
    final id = await q.enqueue(clean);
    final items = await q.watchQueue().first;
    expect(items.single.cardId, id);
    expect(items.single.front.parsed!.name!.value, 'Jo Park', reason: 'parse is recomputed from stored OCR');

    final personId = await contacts.save(draftFromScan(items.single.front.parsed));
    await q.link(id, personId);
    expect(await q.watchQueue().first, isEmpty);
    expect((await contacts.loadDetail(personId))!.cards.single.frontHash, 'h1');
  });

  test('auto-save rule: clean cards only', () {
    expect(isCleanCard(clean), isTrue);
    expect(isCleanCard(side('h2', ['Jo Park', 'Plant Manager'], heights: [22, 11])), isFalse, reason: 'no phone or email');
    expect(isCleanCard(side('h3', clean.ocr!.lines.map((l) => l.text).toList(), heights: [14, 22, 11, 9, 9], issues: [QualityIssue.blurry])), isFalse);
  });

  test('auto-save creates the contact and counts toward today', () async {
    final id = await q.enqueue(clean);
    await q.autoSave(id, clean, contacts);
    final stats = await q.watchStats().first;
    expect(stats.waiting, 0);
    expect(stats.savedToday, 1);
    expect(stats.autoSavedToday, 1);
    expect((await contacts.watchContacts(const ContactFilterAll()).first).single.displayName, 'Jo Park');
  });

  test('back side is stored with the card; discard and restore', () async {
    final id = await q.enqueue(clean);
    await q.setBack(id, clean, side('b1', ['4200 Industrial Pkwy', 'Akron, OH 44311']));
    final item = (await q.item(id))!;
    expect(item.back!.hash, 'b1');
    expect(draftFromScan(item.front.parsed, item.back!.parsed).address, '4200 Industrial Pkwy, Akron, OH 44311');

    await q.discard(id);
    expect(await q.watchQueue().first, isEmpty);
    await q.restore(id);
    expect(await q.watchQueue().first, hasLength(1));
  });

  test('QR vCard wins over OCR and only real disagreements are flagged', () {
    final s = side(
      'h4',
      ['Brightlne', 'Sam Okafor', 'Head of Sales', 'sam@brightline.io'],
      heights: [16, 20, 10, 9],
      qr: ['BEGIN:VCARD\nVERSION:3.0\nN:Okafor;Sam\nORG:Brightline\nTEL;TYPE=CELL:+12165550123\nEND:VCARD'],
    );
    expect(s.parsed!.company!.value, 'Brightline');
    expect(s.parsed!.title!.value, 'Head of Sales');
    expect(s.parsed!.phones.single.value, '+12165550123');
    expect(s.check, {'company'});
  });

  test('a queued card round-trips through JSON', () {
    final s = side('h5', ['Acme', 'Jo Park'], issues: [QualityIssue.glare], qr: ['https://acme.example/jo']);
    final back = ScannedSide.fromJson('h5', Uint8List(0), s.toJson());
    expect(back.issues, [QualityIssue.glare]);
    expect(back.qrLink!.url.toString(), 'https://acme.example/jo');
    expect(back.ocr!.lines.map((l) => l.text), ['Acme', 'Jo Park']);
  });
}

class ContactFilterAll extends ContactFilter {
  const ContactFilterAll();
}
