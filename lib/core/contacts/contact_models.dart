import '../db/database.dart';

/// One editable phone/email/etc. line in the edit form.
class LabeledValue {
  final String label;
  final String value;
  const LabeledValue(this.label, this.value);

  @override
  bool operator ==(Object other) => other is LabeledValue && other.label == label && other.value == value;
  @override
  int get hashCode => Object.hash(label, value);
}

/// Everything the edit screen can change. Saved by ContactsRepository.save().
class ContactDraft {
  String first;
  String last;
  String title;
  String company;
  List<LabeledValue> phones; // label: Mobile, Office, Direct, Other
  List<String> emails;
  String website;
  String address;
  String notes;
  LeadRating? leadRating;
  DateTime? followupAt;
  bool trackCareer;

  ContactDraft({
    this.first = '',
    this.last = '',
    this.title = '',
    this.company = '',
    List<LabeledValue>? phones,
    List<String>? emails,
    this.website = '',
    this.address = '',
    this.notes = '',
    this.leadRating,
    this.followupAt,
    this.trackCareer = true,
  }) : phones = phones ?? [],
       emails = emails ?? [];

  String get displayName => [first.trim(), last.trim()].where((s) => s.isNotEmpty).join(' ');

  bool get isEmpty => displayName.isEmpty && company.trim().isEmpty && phones.isEmpty && emails.isEmpty;
}

/// A row in the Contacts list.
class ContactSummary {
  final String id;
  final String first;
  final String last;
  final String displayName;
  final String? title;
  final String? company;
  final LeadRating? leadRating;
  final PersonStatus status;
  final DateTime? followupAt;
  final DateTime createdAt;

  const ContactSummary({
    required this.id,
    required this.first,
    required this.last,
    required this.displayName,
    this.title,
    this.company,
    this.leadRating,
    this.status = PersonStatus.active,
    this.followupAt,
    required this.createdAt,
  });

  String get initials {
    final parts = [first, last].where((s) => s.trim().isNotEmpty).toList();
    if (parts.isEmpty) return displayName.isEmpty ? '?' : displayName[0].toUpperCase();
    return parts.map((s) => s.trim()[0].toUpperCase()).join();
  }

  /// "Director of Procurement · Halden Tooling Group"
  String get subtitle => [title, company].where((s) => s != null && s.isNotEmpty).join(' · ');
}

class RoleView {
  final String id;
  final String title;
  final String? company;
  final RoleStatus status;
  final DateTime? startDate;
  final DateTime? endDate;
  const RoleView(this.id, this.title, this.company, this.status, this.startDate, this.endDate);
}

class ContactPointView {
  final String id;
  final ContactKind kind;
  final String value;
  final String label;
  final bool isPrimary;
  final ContactStatus status;
  const ContactPointView(this.id, this.kind, this.value, this.label, this.isPrimary, this.status);

  bool get isActive => status == ContactStatus.active;
}

/// A scanned card's images (hashes into the ImageStore).
class CardView {
  final String id;
  final String frontHash;
  final String? backHash;
  final DateTime scannedAt;
  const CardView(this.id, this.frontHash, this.backHash, this.scannedAt);
}

/// Everything the detail screen shows.
class ContactDetail {
  final PeopleData person;
  final List<RoleView> roles; // current first
  final List<ContactPointView> points; // active first
  final List<CardView> cards; // newest first
  final String? introducedByName;
  final String? metEventName;

  const ContactDetail({
    required this.person,
    required this.roles,
    required this.points,
    this.cards = const [],
    this.introducedByName,
    this.metEventName,
  });

  RoleView? get currentRole => roles.where((r) => r.status == RoleStatus.current).firstOrNull;

  Iterable<ContactPointView> active(ContactKind k) => points.where((p) => p.kind == k && p.isActive);

  /// Default targets never use former or bounced points (spec §4 rules).
  ContactPointView? get callTarget => active(ContactKind.mobile).firstOrNull ?? active(ContactKind.office).firstOrNull;
  ContactPointView? get textTarget => active(ContactKind.mobile).firstOrNull;
  ContactPointView? get emailTarget =>
      active(ContactKind.email).where((p) => p.isPrimary).firstOrNull ?? active(ContactKind.email).firstOrNull;

  ContactDraft toDraft() => ContactDraft(
    first: person.first,
    last: person.last,
    title: currentRole?.title ?? '',
    company: currentRole?.company ?? '',
    phones: [
      for (final p in points.where((p) => p.isActive && (p.kind == ContactKind.mobile || p.kind == ContactKind.office)))
        LabeledValue(p.label.isEmpty ? (p.kind == ContactKind.mobile ? 'Mobile' : 'Office') : p.label, p.value),
    ],
    emails: [for (final p in active(ContactKind.email)) p.value],
    website: active(ContactKind.web).firstOrNull?.value ?? '',
    address: active(ContactKind.address).firstOrNull?.value ?? '',
    notes: person.notes,
    leadRating: person.leadRating,
    followupAt: person.followupAt,
    trackCareer: person.trackCareer,
  );
}

enum ContactSort { name, company, recent }

class ContactFilter {
  final String query;
  final ContactSort sort;
  final LeadRating? rating;
  final PersonStatus? status;
  final bool followupOnly;

  const ContactFilter({
    this.query = '',
    this.sort = ContactSort.name,
    this.rating,
    this.status,
    this.followupOnly = false,
  });

  bool get hasFilters => rating != null || status != null || followupOnly;

  ContactFilter copyWith({
    String? query,
    ContactSort? sort,
    LeadRating? Function()? rating,
    PersonStatus? Function()? status,
    bool? followupOnly,
  }) => ContactFilter(
    query: query ?? this.query,
    sort: sort ?? this.sort,
    rating: rating != null ? rating() : this.rating,
    status: status != null ? status() : this.status,
    followupOnly: followupOnly ?? this.followupOnly,
  );
}

class LibraryStats {
  final int people;
  final int companies;
  final int followupsThisWeek;
  const LibraryStats(this.people, this.companies, this.followupsThisWeek);
}
