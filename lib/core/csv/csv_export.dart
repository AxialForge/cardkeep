import '../vcard/vcard.dart';

enum CsvLayout { generic, hubspot, salesforce }

const _headers = {
  CsvLayout.generic: [
    'First name',
    'Last name',
    'Company',
    'Title',
    'Email',
    'Mobile',
    'Office',
    'Website',
    'Address',
    'Notes',
  ],
  CsvLayout.hubspot: [
    'First Name',
    'Last Name',
    'Company Name',
    'Job Title',
    'Email',
    'Mobile Phone Number',
    'Phone Number',
    'Website URL',
    'Street Address',
    'Notes',
  ],
  CsvLayout.salesforce: [
    'FirstName',
    'LastName',
    'Company',
    'Title',
    'Email',
    'MobilePhone',
    'Phone',
    'Website',
    'Street',
    'Description',
  ],
};

String writeCsv(Iterable<ExportContact> cs, {CsvLayout layout = CsvLayout.generic}) {
  String phone(ExportContact c, bool mobile) =>
      c.phones.where((p) => p.label.toLowerCase().startsWith('m') == mobile).map((p) => p.number).firstOrNull ?? '';
  final rows = <List<String>>[
    _headers[layout]!,
    for (final c in cs)
      [
        c.first,
        c.last,
        c.company ?? '',
        c.title ?? '',
        c.emails.firstOrNull ?? '',
        phone(c, true),
        phone(c, false),
        c.website ?? '',
        c.address ?? '',
        c.notes ?? '',
      ],
  ];
  return rows.map((r) => r.map(_cell).join(',')).join('\r\n');
}

String _cell(String v) => RegExp(r'[,"\r\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
