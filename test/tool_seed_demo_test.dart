// Writes a demo database of fictional contacts for emulator checks and screenshots.
// Skipped unless SEED_OUT is set:  SEED_OUT=C:/tmp/seed.sqlite flutter test test/tool_seed_demo_test.dart
import 'dart:io';

import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _people = [
  ('Priya', 'Nambiar', 'Director of Procurement', 'Halden Tooling Group', '330 555 0142', LeadRating.warm),
  ('Marcus', 'Oyelaran', 'VP Operations', 'Calder Hydraulics', '216 555 0177', LeadRating.hot),
  ('Dana', 'Reyes', 'Purchasing Manager', 'Northwind Forging, Inc.', '330 555 0101', LeadRating.hot),
  ('Sam', 'Okafor', 'Head of Sales', 'Brightline', '216 555 0123', null),
  ('Elena', 'Marsh', 'Quality Engineer', 'Kestrel Aerospace', '440 555 0190', LeadRating.cold),
  ('Tomás', 'Herrera', 'Plant Manager', 'Ridgeway Castings', '419 555 0165', LeadRating.warm),
  ('Grace', 'Lindqvist', 'Buyer', 'Halden Tooling Group', '330 555 0155', null),
  ('Jun', 'Park', 'Process Engineer', 'Summit Die & Mold', '614 555 0111', LeadRating.cold),
  ('Aisha', 'Bello', 'Supply Chain Lead', 'Orbit Medical Devices', '513 555 0188', LeadRating.warm),
  ('Owen', 'Fitzgerald', 'President', 'Fitzgerald Heat Treat LLC', '330 555 0133', LeadRating.hot),
  ('Hannah', 'Weiss', 'Account Executive', 'Vector Steel Supply', '412 555 0102', null),
  ('Luca', 'Romano', 'Engineering Manager', 'Calder Hydraulics', '216 555 0148', null),
  ('Mei', 'Chen', 'Director of Engineering', 'Brightline', '216 555 0199', LeadRating.warm),
  ('Carlos', 'Mendez', 'Estimator', 'Ridgeway Castings', '419 555 0120', null),
  ('Nora', 'Sullivan', 'Chief Operating Officer', 'Kestrel Aerospace', '440 555 0107', LeadRating.hot),
  ('Ibrahim', 'Haddad', 'Sales Representative', 'Vector Steel Supply', '412 555 0164', LeadRating.cold),
  ('Rachel', 'Adler', 'Procurement Specialist', 'Orbit Medical Devices', '513 555 0136', null),
  ('Victor', 'Novak', 'Maintenance Supervisor', 'Northwind Forging, Inc.', '330 555 0178', null),
  ('Zoe', 'Taylor', 'Marketing Manager', 'Summit Die & Mold', '614 555 0193', null),
  ('Ben', 'Albright', 'Owner', 'Albright Machine Works', '330 555 0115', LeadRating.warm),
  ('Fatima', 'Qureshi', 'Metallurgist', 'Kestrel Aerospace', '440 555 0181', null),
  ('George', 'Ivanov', 'Logistics Coordinator', 'Halden Tooling Group', '330 555 0166', null),
];

void main() {
  final out = Platform.environment['SEED_OUT'];
  test('seed demo database', () async {
    final f = File(out!);
    if (f.existsSync()) f.deleteSync();
    final db = AppDatabase(NativeDatabase(f));
    var clock = DateTime(2026, 9, 1, 9);
    final repo = ContactsRepository(db, clock: () => clock);
    for (final (i, (first, last, title, company, phone, rating)) in _people.indexed) {
      clock = clock.add(const Duration(days: 2, hours: 3));
      final domain = company
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z]'), '')
          .replaceAll('inc', '')
          .replaceAll('llc', '');
      await repo.save(
        ContactDraft(
          first: first,
          last: last,
          title: title,
          company: company,
          phones: [
            LabeledValue('Mobile', phone),
            if (i.isEven) LabeledValue('Office', phone.replaceRange(8, 12, '0100')),
          ],
          emails: ['${first[0].toLowerCase()}.${last.toLowerCase()}@$domain.example'],
          website: '$domain.example',
          leadRating: rating,
          followupAt: i % 5 == 0 ? DateTime.now().add(Duration(days: i % 9 - 2)) : null,
          notes: i % 3 == 0 ? 'Met at the booth. Interested in die inserts; prefers email.' : '',
        ),
      );
    }
    await db.close();
  }, skip: out == null ? 'Set SEED_OUT to write the demo database' : false);
}
