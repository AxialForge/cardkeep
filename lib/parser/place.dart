import '../core/db/tables.dart' show PlaceCategory;
import 'rules.dart';

/// A card that belongs to a business, not a person (roadmap S14b.2): a store,
/// restaurant, vendor or service card.
class PlaceGuess {
  final String business;
  final String category; // a built-in PlaceCategory name: scanning never guesses a custom one
  final String hours;
  const PlaceGuess(this.business, this.category, this.hours);
}

const _restaurant = {
  'restaurant', 'cafe', 'café', 'coffee', 'grill', 'pizza', 'pizzeria', 'bakery', 'diner', 'bar', 'pub', //
  'kitchen', 'bistro', 'deli', 'tavern', 'brewing', 'brewery', 'eatery', 'taqueria', 'sushi', 'bbq', 'catering',
};
const _store = {
  'store', 'shop', 'market', 'boutique', 'hardware', 'outlet', 'pharmacy', 'nursery', 'mart', 'gallery', //
  'books', 'bookstore', 'florist', 'flowers', 'jewelers', 'jewelry', 'thrift', 'goods', 'emporium', 'grocery',
};
const _vendor = {
  'wholesale',
  'distributor',
  'distributors',
  'distribution',
  'supplier',
  'suppliers',
  'vendor',
  'supply',
};
const _service = {
  'repair', 'repairs', 'auto', 'automotive', 'salon', 'spa', 'barber', 'barbershop', 'cleaning', 'cleaners', //
  'plumbing', 'heating', 'hvac', 'roofing', 'landscaping', 'lawn', 'clinic', 'garage', 'tire', 'tires', 'detailing',
  'laundry', 'tailor', 'printing', 'storage', 'rental', 'rentals', 'fitness', 'gym', 'veterinary', 'pet', 'grooming',
};

final _slogan = RegExp(
  r'\b(order online|shop online|visit us|come see us|open daily|open 7 days|walk-?ins? welcome|free estimates?|'
  r'now open|dine in|take ?out|carry ?out|delivery available|curbside|follow us|book online|call for appointment|'
  r'locally owned|family owned)\b',
  caseSensitive: false,
);

/// The place guess for a scanned card, or null for a person's card.
///
/// Signals: opening hours (2), a shop slogan (2), a store/restaurant/vendor/
/// service word in the name or company line (2), a street address (1). A place
/// needs 2 points, 4 when a person's name is printed too; a card with a person's
/// name plus a job title is always a person, unless that "name" is itself a
/// business ("Lakeside Hardware").
PlaceGuess? guessPlace(ParsedCard? front, [ParsedCard? back]) {
  final cards = [?front, ?back];
  if (cards.isEmpty) return null;
  final name = cards.map((c) => c.name?.value).nonNulls.firstOrNull ?? '';
  final company = cards.map((c) => c.company?.value).nonNulls.firstOrNull ?? '';
  final title = cards.map((c) => c.title?.value).nonNulls.firstOrNull ?? '';
  final hours = [
    for (final c in cards)
      for (final e in c.extras)
        if (e.label == 'Hours') e.value,
  ];
  final text = [
    for (final c in cards) ...[...c.notes, for (final e in c.extras) e.value, ?c.title?.value],
  ].join('\n');

  final nameIsBusiness = _category(name) != null;
  if (name.isNotEmpty && !nameIsBusiness && title.isNotEmpty) return null;
  final local = cards.expand((c) => c.emails).map((e) => e.value.split('@').first.toLowerCase()).firstOrNull ?? '';
  if (name.isNotEmpty &&
      !nameIsBusiness &&
      name.toLowerCase().split(' ').any((t) => t.length > 2 && local.contains(t))) {
    return null;
  }

  var points = 0;
  if (hours.isNotEmpty) points += 2;
  if (_slogan.hasMatch(text)) points += 2;
  final category = _category(company) ?? _category(name) ?? _category(title) ?? _category(text);
  if (_category(company) != null || nameIsBusiness) points += 2;
  if (cards.any((c) => c.address != null)) points += 1;
  // A person's name on the card needs more than one sign it is a business card.
  final personName = name.isNotEmpty && !nameIsBusiness;
  if (points < (personName ? 4 : 2)) return null;

  final business = company.isNotEmpty ? company : name;
  if (business.isEmpty) return null;
  return PlaceGuess(business, (category ?? PlaceCategory.other).name, hours.join('\n'));
}

PlaceCategory? _category(String s) {
  if (s.isEmpty) return null;
  final words = s.toLowerCase().split(RegExp(r'[^a-zà-ÿ]+')).toSet();
  if (words.any(_restaurant.contains)) return PlaceCategory.restaurant;
  if (words.any(_vendor.contains)) return PlaceCategory.vendor;
  if (words.any(_store.contains)) return PlaceCategory.store;
  if (words.any(_service.contains)) return PlaceCategory.service;
  return null;
}
