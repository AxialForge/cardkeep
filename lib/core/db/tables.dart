import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Public: drift copies clientDefault closures into database.g.dart.
const uuidGen = Uuid();

/// Columns every table carries (spec §3): uuid PK, timestamps, tombstone.
mixin SyncColumns on Table {
  TextColumn get uuid => text().clientDefault(() => uuidGen.v4())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {uuid};
}

enum LeadRating { hot, warm, cold }

enum PersonStatus { active, moved, retired, unknown }

enum RoleStatus { current, former, retired }

enum RoleSource { scan, manual, import, webCheck, bounce, nfcLink }

enum ContactKind { mobile, office, email, web, address, fax }

enum ContactStatus { active, former, bounced }

enum SuggestionKind { moved, retired, bounce }

enum SuggestionStatus { pending, applied, dismissed }

enum SuggestionSource { scan, bounce, manual }

enum CardStatus { parsed, needsReview, saved }

enum EventType { tradeShow, networking }

/// A person, or a place: a card that belongs to a business, not a person (S14b).
enum PersonKind { person, place }

/// The built-in place categories. Their names are the ids of the first rows in
/// [PlaceCategories]; scanning only ever guesses one of these.
enum PlaceCategory { store, restaurant, vendor, service, other }

/// The place category list, editable in Settings (S14b.6, v5). People store the
/// id, so a rename shows everywhere; built-in rows keep the enum names as ids.
@DataClassName('PlaceCategoryRow')
class PlaceCategories extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  BoolColumn get builtIn => boolean().withDefault(const Constant(false))();

  /// v6, for sync. A constant default (0) because SQLite cannot add a column with
  /// a computed one; a trigger stamps new custom rows and every later edit.
  DateTimeColumn get updatedAt => dateTime().withDefault(Constant(DateTime.fromMillisecondsSinceEpoch(0)))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A Place keeps its business name as the company of its current role and as
/// display_name; first/middle/last and the role title stay empty.
class People extends Table with SyncColumns {
  TextColumn get kind => textEnum<PersonKind>().withDefault(Constant(PersonKind.person.name))(); // v4
  TextColumn get placeCategory => text().nullable()(); // v4: a place_categories id (v5)
  TextColumn get hours => text().withDefault(const Constant(''))(); // v4: opening hours as printed
  TextColumn get first => text().withDefault(const Constant(''))();
  TextColumn get last => text().withDefault(const Constant(''))();
  TextColumn get middle => text().withDefault(const Constant(''))(); // v3: name or initial
  TextColumn get logoSha256 => text().nullable()(); // v3: logo cut from the card, shown as the avatar
  TextColumn get extrasJson => text().withDefault(const Constant('[]'))(); // v3: [{label, value}] other card text
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get leadRating => textEnum<LeadRating>().nullable()();
  BoolColumn get trackCareer => boolean().withDefault(const Constant(true))();
  TextColumn get status => textEnum<PersonStatus>().withDefault(Constant(PersonStatus.active.name))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get metEventId => text().nullable()();
  TextColumn get introducedByPersonId => text().nullable()();
  DateTimeColumn get followupAt => dateTime().nullable()();
  DateTimeColumn get followupDoneAt => dateTime().nullable()();
}

class Companies extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get nameNorm => text()();
  TextColumn get domain => text().nullable()();
  TextColumn get website => text().nullable()();
  TextColumn get address => text().nullable()();
}

class Roles extends Table with SyncColumns {
  TextColumn get personId => text().references(People, #uuid)();
  TextColumn get companyId => text().nullable().references(Companies, #uuid)();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get status => textEnum<RoleStatus>().withDefault(Constant(RoleStatus.current.name))();
  TextColumn get source => textEnum<RoleSource>().withDefault(Constant(RoleSource.manual.name))();
  TextColumn get sourceCardId => text().nullable()();
  DateTimeColumn get confirmedAt => dateTime().nullable()();
}

class ContactPoints extends Table with SyncColumns {
  TextColumn get personId => text().references(People, #uuid)();
  TextColumn get roleId => text().nullable().references(Roles, #uuid)();
  TextColumn get kind => textEnum<ContactKind>()();
  TextColumn get value => text()();
  TextColumn get label => text().withDefault(const Constant(''))();
  TextColumn get extension => text().withDefault(const Constant(''))(); // v3: "112" for Ext. 112
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  TextColumn get status => textEnum<ContactStatus>().withDefault(Constant(ContactStatus.active.name))();
}

class Successions extends Table with SyncColumns {
  TextColumn get companyId => text().nullable().references(Companies, #uuid)();
  TextColumn get roleTitle => text().withDefault(const Constant(''))();
  TextColumn get predecessorPersonId => text().references(People, #uuid)();
  TextColumn get successorPersonId => text().nullable().references(People, #uuid)();
  DateTimeColumn get effectiveDate => dateTime().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get note => text().withDefault(const Constant(''))();
}

class ChangeSuggestions extends Table with SyncColumns {
  TextColumn get personId => text().references(People, #uuid)();
  TextColumn get kind => textEnum<SuggestionKind>()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  TextColumn get status => textEnum<SuggestionStatus>().withDefault(Constant(SuggestionStatus.pending.name))();
  TextColumn get source => textEnum<SuggestionSource>()();
}

class Cards extends Table with SyncColumns {
  TextColumn get personId => text().nullable().references(People, #uuid)();
  TextColumn get frontSha256 => text()();
  TextColumn get backSha256 => text().nullable()();
  TextColumn get ocrJson => text().withDefault(const Constant('{}'))();
  TextColumn get scanSessionId => text().nullable().references(ScanSessions, #uuid)();
  TextColumn get status => textEnum<CardStatus>().withDefault(Constant(CardStatus.parsed.name))();
  DateTimeColumn get scannedAt => dateTime().withDefault(currentDateAndTime)();
}

class Events extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get type => textEnum<EventType>()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get booth => text().nullable()();
  IntColumn get goal => integer().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  BoolColumn get autoScan => boolean().withDefault(const Constant(false))();
  IntColumn get reminderOffsetDays => integer().withDefault(const Constant(2))();
}

class ScanSessions extends Table with SyncColumns {
  TextColumn get eventId => text().nullable().references(Events, #uuid)();
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endedAt => dateTime().nullable()();
}

class Tags extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#B08A4A'))();
}

class PersonTags extends Table with SyncColumns {
  TextColumn get personId => text().references(People, #uuid)();
  TextColumn get tagId => text().references(Tags, #uuid)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {personId, tagId},
  ];
}

/// A paired device (sync, 0.8). Its uuid is the peer's own device id. Not synced itself.
class Devices extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get platform => text()();
  TextColumn get certFingerprint => text()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  /// v6. Seconds on the peer's clock: its changes up to here are applied here.
  IntColumn get theirWatermark => integer().withDefault(const Constant(0))();

  /// v6. Seconds on this phone's clock: changes up to here have reached the peer.
  IntColumn get myWatermark => integer().withDefault(const Constant(0))();
  DateTimeColumn get pairedAt => dateTime().nullable()();

  /// v6. Peer clock minus this clock, in seconds, measured when pairing.
  IntColumn get clockOffsetSeconds => integer().withDefault(const Constant(0))();
}

/// A field both devices changed inside the conflict window (sync, 0.8). The row
/// keeps this device's value until the owner picks a side.
@DataClassName('SyncConflictRow')
class SyncConflicts extends Table {
  TextColumn get id => text().clientDefault(() => uuidGen.v4())();
  TextColumn get peerId => text()();
  TextColumn get forTable => text().named('table_name')();
  TextColumn get rowKey => text()();
  TextColumn get field => text()();
  TextColumn get mineJson => text()();
  TextColumn get theirsJson => text()();
  IntColumn get mineUpdatedAt => integer()();
  IntColumn get theirsUpdatedAt => integer()();
  IntColumn get detectedAt => integer()();
  IntColumn get resolvedAt => integer().nullable()();
  TextColumn get resolution => text().nullable()(); // mine | theirs | sync

  @override
  Set<Column> get primaryKey => {id};
}

/// What each paired device last had for a row, so the next merge can tell which
/// fields changed on which side (a three-way merge). Fields we are unsure of are
/// left out of the JSON.
class SyncBase extends Table {
  TextColumn get peerId => text()();
  TextColumn get forTable => text().named('table_name')();
  TextColumn get rowKey => text()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {peerId, forTable, rowKey};
}

/// Pairs you said are not the same person (S8.6); key = sorted ids joined by |.
class NotDuplicates extends Table with SyncColumns {
  TextColumn get pairKey => text().unique()();
}

/// Key/value app settings (S15 fills in the rest). Not synced row-by-row.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}
