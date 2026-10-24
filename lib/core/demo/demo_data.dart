import 'package:drift/drift.dart';

import '../contacts/contact_models.dart';
import '../contacts/contacts_repository.dart';
import '../db/database.dart';
import '../tags/tags_repository.dart';

/// Six clearly fictional contacts for the tour (S15a.6): five people at three
/// companies and one place. Every one is tagged **Demo**, so [remove] takes them
/// all away in one go. Names, numbers (555) and addresses (.example) are made up.
class DemoData {
  final AppDatabase db;
  final ContactsRepository contacts;
  final TagsRepository tags;
  DemoData(this.db, this.contacts, this.tags);

  static const note = 'Sample contact for the tour: made up, safe to delete. Settings, Help, Remove demo data.';

  static List<ContactDraft> samples() => [
    ContactDraft(
      first: 'Maya',
      last: 'Chen',
      title: 'VP Sales',
      company: 'Brightline Medical Supply',
      phones: [const LabeledValue('Mobile', '216 555 0101')],
      emails: ['maya@brightline.example'],
      website: 'brightline.example',
      address: '1200 Lakeview Pkwy, Cleveland, OH 44114',
      notes: note,
      leadRating: LeadRating.hot,
      trackCareer: false,
    ),
    ContactDraft(
      first: 'Omar',
      last: 'Haddad',
      title: 'Plant Manager',
      company: 'Ironbridge Castings',
      phones: [const LabeledValue('Office', '330 555 0114', '212')],
      emails: ['omar@ironbridge.example'],
      website: 'ironbridge.example',
      notes: note,
      leadRating: LeadRating.warm,
      trackCareer: false,
    ),
    ContactDraft(
      first: 'Priya',
      last: 'Nair',
      title: 'Data Lead',
      company: 'Larkspur Analytics',
      phones: [const LabeledValue('Mobile', '440 555 0133'), const LabeledValue('Office', '440 555 0100')],
      emails: ['priya@larkspur.example'],
      notes: note,
      trackCareer: false,
    ),
    ContactDraft(
      first: 'Lena',
      last: 'Fischer',
      title: 'Purchasing Agent',
      company: 'Larkspur Analytics',
      phones: [const LabeledValue('Office', '440 555 0100', '118')],
      emails: ['lena@larkspur.example'],
      notes: note,
      trackCareer: false,
    ),
    ContactDraft(
      first: 'Tom',
      last: 'Becker',
      title: 'Quality Engineer',
      company: 'Halden Tooling Group',
      phones: [const LabeledValue('Mobile', '234 555 0170')],
      emails: ['tom@halden.example'],
      leadRating: LeadRating.cold,
      notes: note,
      trackCareer: false,
    ),
    ContactDraft(
      kind: PersonKind.place,
      company: 'Lakeside Hardware',
      category: 'store',
      hours: 'Mon-Sat 8am-7pm, Sun 10am-4pm',
      phones: [const LabeledValue('Office', '440 555 0161')],
      website: 'lakesidehardware.example',
      address: '412 Lakeshore Blvd, Willoughby, OH 44094',
      notes: note,
      trackCareer: false,
    ),
  ];

  /// Adds the six, once: a second call adds nothing while they are still there.
  Future<int> add({String region = 'US'}) async {
    if (await count() > 0) return 0;
    final tagId = await tags.ensureSystem(SystemTag.demo);
    var n = 0;
    for (final d in samples()) {
      final id = await contacts.save(d, region: region);
      await tags.setTags(id, {tagId});
      n++;
    }
    return n;
  }

  /// How many demo contacts exist right now.
  Future<int> count() async => (await _demoCount().getSingle()).read<int>('c');

  /// Live count, for showing or hiding "Remove demo data".
  Stream<int> watchCount() => _demoCount().watch().map((r) => r.single.read<int>('c'));

  Selectable<QueryRow> _demoCount() => db.customSelect(
    '''
SELECT COUNT(*) AS c FROM person_tags pt
JOIN people p ON p.uuid = pt.person_id
WHERE pt.deleted_at IS NULL AND p.deleted_at IS NULL
  AND pt.tag_id = (SELECT value FROM app_settings WHERE key = 'tag.system.demo')''',
    readsFrom: {db.personTags, db.people, db.appSettings},
  );

  /// Deletes every demo contact and the Demo tag. Returns how many went.
  Future<int> remove() async {
    final rows = await db.customSelect('''
SELECT pt.person_id AS id FROM person_tags pt
JOIN people p ON p.uuid = pt.person_id
WHERE pt.deleted_at IS NULL AND p.deleted_at IS NULL
  AND pt.tag_id = (SELECT value FROM app_settings WHERE key = 'tag.system.demo')''').get();
    for (final r in rows) {
      await contacts.delete(r.read<String>('id'));
    }
    final saved = await (db.select(db.appSettings)..where((a) => a.key.equals('tag.system.demo'))).getSingleOrNull();
    if (saved != null) {
      await tags.delete(saved.value);
      await (db.delete(db.appSettings)..where((a) => a.key.equals('tag.system.demo'))).go();
    }
    return rows.length;
  }
}
