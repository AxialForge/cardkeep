import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';

import '../career/career_repository.dart';
import '../contacts/contact_models.dart';
import '../contacts/contacts_repository.dart';
import '../csv/csv_export.dart';
import '../db/database.dart';
import '../dupes/duplicates_repository.dart';
import '../images/image_store.dart';
import '../tags/tags_repository.dart';
import '../vcard/vcard.dart';
import 'csv_import.dart';

/// Who to export (S13.2).
sealed class ExportScope {
  const ExportScope();
}

class ScopeEveryone extends ExportScope {
  const ScopeEveryone();
}

class ScopeTag extends ExportScope {
  final String tagId;
  const ScopeTag(this.tagId);
}

class ScopeEvent extends ExportScope {
  final String eventId;
  const ScopeEvent(this.eventId);
}

class ScopePeople extends ExportScope {
  final List<String> ids;
  const ScopePeople(this.ids);
}

enum ExportFormat {
  vcard3('vCard 3.0', 'vcf'),
  vcard4('vCard 4.0', 'vcf'),
  csv('CSV', 'csv'),
  hubspot('HubSpot CSV', 'csv'),
  salesforce('Salesforce CSV', 'csv');

  final String label, ext;
  const ExportFormat(this.label, this.ext);
}

class ExportFile {
  final String name, mime;
  final Uint8List bytes;
  final int count;
  const ExportFile(this.name, this.mime, this.bytes, this.count);
}

class ImportSummary {
  final int added, merged, skipped;
  final int jobChanges;
  const ImportSummary(this.added, this.merged, this.skipped, this.jobChanges);
  int get total => added + merged + skipped;
}

/// Import and export (roadmap S13.1-S13.7).
class TransferRepository {
  final AppDatabase db;
  final ContactsRepository contacts;
  final DuplicatesRepository dupes;
  final CareerRepository career;
  final TagsRepository tags;
  final DateTime Function() now;

  TransferRepository(this.db, this.contacts, this.dupes, this.career, this.tags, {DateTime Function()? clock})
    : now = clock ?? DateTime.now;

  // ---------------------------------------------------------------- export

  Future<List<String>> idsFor(ExportScope scope) async {
    final (sql, vars) = switch (scope) {
      ScopeEveryone() => ('SELECT uuid FROM people WHERE deleted_at IS NULL', <Variable<Object>>[]),
      ScopeTag(:final tagId) => (
        'SELECT p.uuid FROM people p JOIN person_tags t ON t.person_id = p.uuid '
            'WHERE p.deleted_at IS NULL AND t.deleted_at IS NULL AND t.tag_id = ?',
        [Variable.withString(tagId)],
      ),
      ScopeEvent(:final eventId) => (
        'SELECT uuid FROM people WHERE deleted_at IS NULL AND met_event_id = ?',
        [Variable.withString(eventId)],
      ),
      ScopePeople(:final ids) => ('', <Variable<Object>>[]),
    };
    if (scope is ScopePeople) return scope.ids;
    final rows = await db.customSelect('$sql ORDER BY display_name COLLATE NOCASE', variables: vars).get();
    return [for (final r in rows) r.read<String>('uuid')];
  }

  /// One file in [format]; with [images] a zip of that file plus each
  /// person's newest card (front, and back when there is one).
  Future<ExportFile> export(
    ExportScope scope,
    ExportFormat format, {
    bool notes = true,
    bool images = false,
    ImageStore? store,
  }) async {
    final details = [for (final id in await idsFor(scope)) ?await contacts.loadDetail(id)];
    final people = [
      for (final d in details)
        if (contacts.toExport(d) case final c) notes ? c : _withoutNotes(c),
    ];
    final text = switch (format) {
      ExportFormat.vcard3 => writeVCards(people),
      ExportFormat.vcard4 => writeVCards(people, version: '4.0'),
      ExportFormat.csv => writeCsv(people),
      ExportFormat.hubspot => writeCsv(people, layout: CsvLayout.hubspot),
      ExportFormat.salesforce => writeCsv(people, layout: CsvLayout.salesforce),
    };
    final stamp = '${now().year}-${_pad2(now().month)}-${_pad2(now().day)}';
    final base = 'CardKeep contacts $stamp';
    final body = Uint8List.fromList(utf8.encode(format.ext == 'csv' ? '﻿$text' : text)); // BOM: Excel reads UTF-8
    if (!images || store == null) {
      return ExportFile('$base.${format.ext}', format.ext == 'csv' ? 'text/csv' : 'text/vcard', body, people.length);
    }
    final zip = Archive()..add(ArchiveFile.bytes('$base.${format.ext}', body));
    for (final d in details) {
      final card = d.cards.firstOrNull;
      if (card == null) continue;
      final safe = d.person.displayName.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
      for (final (side, hash) in [('front', card.frontHash), if (card.backHash != null) ('back', card.backHash!)]) {
        final f = store.rectified(hash);
        if (f.existsSync()) zip.add(ArchiveFile.bytes('cards/$safe ($side).jpg', await f.readAsBytes()));
      }
    }
    return ExportFile('$base.zip', 'application/zip', Uint8List.fromList(ZipEncoder().encode(zip)), people.length);
  }

  static ExportContact _withoutNotes(ExportContact c) => ExportContact(
    first: c.first,
    last: c.last,
    company: c.company,
    title: c.title,
    emails: c.emails,
    phones: c.phones,
    website: c.website,
    address: c.address,
  );

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  // ---------------------------------------------------------------- import

  /// S13.7: every row gets the Imported tag; one that matches someone at the
  /// same company is merged into them, one at another company becomes a
  /// possible job change. Exact repeats (nothing new) are skipped.
  Future<ImportSummary> importContacts(List<ExportContact> list, {String region = 'US'}) async {
    final tagId = await tags.ensureSystem(SystemTag.imported);
    var added = 0, merged = 0, skipped = 0, moves = 0;
    for (final c in list) {
      final draft = ContactDraft(
        first: c.first,
        last: c.last,
        company: c.company ?? '',
        title: c.title ?? '',
        phones: [
          for (final p in c.phones) LabeledValue(p.label.toLowerCase().startsWith('m') ? 'Mobile' : 'Office', p.number),
        ],
        emails: c.emails,
        website: c.website ?? '',
        address: c.address ?? '',
        notes: c.notes ?? '',
      );
      if (draft.isEmpty) {
        skipped++;
        continue;
      }
      final id = await contacts.save(draft, region: region, source: RoleSource.import);
      final match = (await dupes.matchesFor(id)).where((m) => m.match.sameCompany).firstOrNull;
      if (match != null) {
        if (await _addsNothing(match.b.id, id)) {
          await contacts.delete(id);
          skipped++;
        } else {
          await dupes.merge(match.b.id, id, const MergeChoices());
          await tags.addToAll([match.b.id], tagId);
          merged++;
        }
        continue;
      }
      await tags.addToAll([id], tagId);
      moves += await career.checkNewCard(id);
      added++;
    }
    return ImportSummary(added, merged, skipped, moves);
  }

  /// True when every phone and email of [newId] is already on [existingId].
  Future<bool> _addsNothing(String existingId, String newId) async {
    final a = await contacts.loadDetail(existingId), b = await contacts.loadDetail(newId);
    if (a == null || b == null) return false;
    final have = {for (final p in a.points) '${p.kind.name}:${p.value.toLowerCase()}'};
    return b.points.every((p) => have.contains('${p.kind.name}:${p.value.toLowerCase()}'));
  }

  /// Remembered CSV column mappings, by header row (S13.5).
  Future<List<CsvField>?> savedMapping(List<String> headers) async {
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('csvmap:${headerKey(headers)}'))).getSingleOrNull();
    if (row == null) return null;
    final names = (jsonDecode(row.value) as List).cast<String>();
    if (names.length != headers.length) return null;
    return [for (final n in names) CsvField.values.where((f) => f.name == n).firstOrNull ?? CsvField.skip];
  }

  Future<void> saveMapping(List<String> headers, List<CsvField> mapping) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'csvmap:${headerKey(headers)}',
          value: jsonEncode([for (final f in mapping) f.name]),
        ),
      );
}
