import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/sync/change_set.dart';

/// One field both devices changed, in words a person can choose between.
class ConflictItem {
  final SyncConflict conflict;
  final String fieldLabel;
  final String mine;
  final String theirs;
  const ConflictItem(this.conflict, this.fieldLabel, this.mine, this.theirs);
}

/// The conflicts of one contact (or company, tag...), under its name.
class ConflictGroup {
  final String title;
  final String subtitle;
  final List<ConflictItem> items;
  const ConflictGroup(this.title, this.subtitle, this.items);
}

const _fieldLabels = <String, String>{
  'display_name': 'Name',
  'first': 'First name',
  'middle': 'Middle name',
  'last': 'Last name',
  'notes': 'Notes',
  'extras_json': 'More from the card',
  'lead_rating': 'Lead rating',
  'followup_at': 'Follow-up date',
  'followup_done_at': 'Follow-up done',
  'title': 'Title',
  'name': 'Name',
  'label': 'Name',
  'value': 'Value',
  'kind': 'Type',
  'hours': 'Opening hours',
  'place_category': 'Category',
  'logo_sha256': 'Logo',
  'website': 'Website',
  'address': 'Address',
  'status': 'Status',
  'ext': 'Extension',
  'color': 'Colour',
  'goal': 'Goal',
  'starts_at': 'Starts',
  'ends_at': 'Ends',
};

String fieldLabel(String column) {
  final known = _fieldLabels[column];
  if (known != null) return known;
  final words = column.replaceAll('_', ' ').trim();
  return words.isEmpty ? column : words[0].toUpperCase() + words.substring(1);
}

/// A stored value as text: dates for *_at columns, Yes/No for flags, a dash
/// for nothing, and long text cut short.
String describeValue(String column, Object? v) {
  if (v == null) return '(empty)';
  if (v is int && column.endsWith('_at')) {
    return DateFormat('MMM d, y h:mm a').format(DateTime.fromMillisecondsSinceEpoch(v * 1000));
  }
  if (v is int && (column.startsWith('is_') || column.startsWith('has_'))) return v == 0 ? 'No' : 'Yes';
  final s = '$v'.trim();
  if (s.isEmpty) return '(empty)';
  return s.length > 140 ? '${s.substring(0, 137)}…' : s;
}

String _tableName(String table) => switch (table) {
  'people' => 'Contact',
  'roles' => 'Job',
  'contact_points' => 'Phone, email or address',
  'cards' => 'Card',
  'companies' => 'Company',
  'tags' => 'Tag',
  'events' => 'Event',
  'place_categories' => 'Place category',
  'successions' => 'Job change',
  _ => 'Item',
};

Future<String?> _one(AppDatabase db, String sql, String arg) async {
  final r = await db.customSelect(sql, variables: [Variable.withString(arg)]).getSingleOrNull();
  if (r == null) return null;
  final v = r.data.values.first;
  return v == null ? null : '$v';
}

/// Names the thing a conflict is about: the contact for its jobs, numbers and
/// cards, the company or tag by its own name.
Future<(String, String)> _owner(AppDatabase db, SyncConflict c) async {
  final what = _tableName(c.table);
  String? name;
  switch (c.table) {
    case 'people':
      name = await _one(db, 'SELECT display_name FROM people WHERE uuid = ?', c.rowKey);
    case 'roles':
      name = await _one(
        db,
        'SELECT p.display_name FROM roles r JOIN people p ON p.uuid = r.person_id WHERE r.uuid = ?',
        c.rowKey,
      );
    case 'contact_points':
      name = await _one(
        db,
        'SELECT p.display_name FROM contact_points c JOIN people p ON p.uuid = c.person_id WHERE c.uuid = ?',
        c.rowKey,
      );
    case 'cards':
      name = await _one(
        db,
        'SELECT p.display_name FROM cards c JOIN people p ON p.uuid = c.person_id WHERE c.uuid = ?',
        c.rowKey,
      );
    case 'companies':
      name = await _one(db, 'SELECT name FROM companies WHERE uuid = ?', c.rowKey);
    case 'tags':
      name = await _one(db, 'SELECT name FROM tags WHERE uuid = ?', c.rowKey);
    case 'events':
      name = await _one(db, 'SELECT name FROM events WHERE uuid = ?', c.rowKey);
    case 'place_categories':
      name = await _one(db, 'SELECT label FROM place_categories WHERE id = ?', c.rowKey);
  }
  return ((name == null || name.trim().isEmpty) ? 'Unnamed ${what.toLowerCase()}' : name.trim(), what);
}

/// The open conflicts, grouped by what they are about.
Future<List<ConflictGroup>> describeConflicts(AppDatabase db, List<SyncConflict> conflicts) async {
  final groups = <String, (String, String, List<ConflictItem>)>{};
  for (final c in conflicts) {
    final (title, what) = await _owner(db, c);
    final key = '${c.table}|${c.rowKey}';
    final g = groups[key] ??= (title, what, <ConflictItem>[]);
    g.$3.add(ConflictItem(c, fieldLabel(c.field), describeValue(c.field, c.mine), describeValue(c.field, c.theirs)));
  }
  final list = [for (final g in groups.values) ConflictGroup(g.$1, g.$2, g.$3)];
  list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return list;
}
