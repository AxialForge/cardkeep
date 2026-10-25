import 'content_model.dart';

/// The four welcome pages (S15a.1). Every claim here is checked against the app
/// as it ships: update the text when the app changes.
const welcomePages = <WelcomePage>[
  WelcomePage(
    'meet',
    Art.welcome,
    'Meet CardKeep',
    'Business cards in, organised contacts out. Everything stays on your phone.',
    [
      LessonStep(
        'Scan',
        'Point the camera at a card, or sweep over a whole table of them. CardKeep reads the text for you.',
      ),
      LessonStep('Organise', 'Tags, events where you met people, companies, places, and duplicates tidied in one tap.'),
      LessonStep(
        'Follow up',
        'Set a date on a contact and get a reminder in the morning. Nobody falls through the cracks.',
      ),
    ],
  ),
  WelcomePage(
    'privacy',
    Art.privacy,
    'Your privacy, precisely',
    'No account. No cloud. No analytics. Here is exactly what that means.',
    [
      LessonStep(
        'Nothing is uploaded',
        'Your contacts, notes and card photos are never sent to a server. Text on a card is read on this phone by Google ML Kit using models bundled in the app; CardKeep switched off its usage logging.',
      ),
      LessonStep(
        'The only internet use',
        'An update check against CardKeep\'s releases on GitHub, and only if you switch it on in Settings. It sends nothing about you. Links, maps, calls and emails you tap open other apps. If you pair a PC, Sync to desktop sends your library to that PC over your own Wi-Fi, only while the Sync screen is open.',
      ),
      LessonStep(
        'Backups stay here too',
        'Weekly backups are saved on this phone. Android\'s cloud backup is switched off for CardKeep, so nothing is copied to Google or to a new phone behind your back.',
      ),
    ],
  ),
  WelcomePage(
    'keeps',
    Art.keeps,
    'What CardKeep keeps, and who can see it',
    'Only what you put in, in the app\'s private storage.',
    [
      LessonStep(
        'What is stored',
        'Contacts and places with their phones, emails, notes, tags, events and follow-ups, plus the photo of each card you scan and any logo cut from it.',
      ),
      LessonStep(
        'Who can see it',
        'Only you, and only inside CardKeep. Other apps can\'t open its storage. A card photo or contact leaves only when you share or export it yourself.',
      ),
      LessonStep(
        'Deleting',
        'Delete a contact and you get an Undo straight away. After 7 days it is wiped for good, card photos included, and a deleted contact never goes into a backup. Uninstalling CardKeep removes everything.',
      ),
    ],
  ),
  WelcomePage('how', Art.tour, 'How this tour works', 'About five minutes, and you stay in control.', [
    LessonStep(
      'Permissions, explained first',
      'Before Android asks for the camera or notifications, you read why. You can say Not now.',
    ),
    LessonStep(
      'A few set-up choices',
      'Theme, name order, region and more, with sensible defaults you can change later.',
    ),
    LessonStep(
      'Eight short lessons',
      'Each has a small animation and a Try it button that takes you to the real screen. Skip any of them.',
    ),
    LessonStep(
      'Skip or leave any time',
      'The Skip button and the back button are always there. Replay the tour later from Settings, under Help.',
    ),
  ]),
];

/// The three permission cards (S15a.2). CardKeep asks for the camera and for
/// notifications; NFC needs no permission; it never asks for your Contacts.
const permissionCards = <PermissionCardInfo>[
  PermissionCardInfo(
    id: 'camera',
    art: Art.camera,
    title: 'Camera',
    kind: PermKind.camera,
    why: 'To photograph business cards. Scanning, Batch, Pile and Sweep all need it.',
    never: 'CardKeep takes pictures only while the scanner is open and you are pointing it at a card. It never records video, sound or anything in the background, and no picture leaves the phone.',
    ifNo: 'Scanning won\'t work. Everything else does: add contacts by hand, import a vCard or CSV, and import card photos from your gallery.',
    later: 'Phone Settings, Apps, CardKeep, Permissions, Camera.',
  ),
  PermissionCardInfo(
    id: 'notifications',
    art: Art.bell,
    title: 'Notifications',
    kind: PermKind.notifications,
    why: 'To remind you to follow up with someone on the day you chose.',
    never: 'No adverts, no "come back" nudges, no news. Only the reminders you set yourself, and the lock screen shows a private notice rather than the contact.',
    ifNo: 'You won\'t get reminders. Follow-ups still show in the app, under Follow-ups and on the Contacts banner.',
    later: 'Phone Settings, Apps, CardKeep, Notifications.',
  ),
  PermissionCardInfo(
    id: 'nfc',
    art: Art.nfcPhone,
    title: 'NFC, contacts and other apps',
    kind: null,
    why: 'NFC (Tap cards) needs no permission: switch NFC on in your phone\'s quick settings and hold a tap card to the back of the phone. CardKeep also never asks to read your phone\'s Contacts.',
    never: 'It won\'t read or change your phone\'s address book. To put someone into the Contacts app, open them and use Share as vCard. Calls, texts, email, maps and web checks open your own apps, which have their own settings.',
    ifNo: 'A phone without NFC only loses Tap cards. Nothing else in CardKeep depends on it.',
    later: 'NFC: phone quick settings or Settings, Connections.',
  ),
];

/// "How do I get my contacts in?" (finale and Import help).
const importHowTos = <ImportHowTo>[
  ImportHowTo('google', 'Google Contacts', [
    'On a computer open contacts.google.com and select the people you want (or everyone).',
    'Choose Export, pick vCard (for iOS Contacts) and download the .vcf file.',
    'Copy the file to your phone (email it to yourself, or use a cloud drive).',
    'In CardKeep open Import, choose vCard file and pick it. Nothing is changed until you confirm.',
  ]),
  ImportHowTo('outlook', 'Outlook', [
    'In Outlook open People, then Manage, Export contacts, and choose a .csv file.',
    'Copy the file to your phone.',
    'In CardKeep open Import, choose Spreadsheet and pick it. You confirm which column is which before anything is added.',
  ]),
  ImportHowTo('iphone', 'iPhone', [
    'On the iPhone open Contacts, select a contact (or use iCloud on a computer: icloud.com, Contacts, select all, Export vCard).',
    'Share the .vcf file to yourself by email or AirDrop to a computer, then copy it to your Android phone.',
    'In CardKeep open Import, choose vCard file and pick it.',
  ]),
  ImportHowTo('linkedin', 'LinkedIn', [
    'On a computer open LinkedIn, Settings and privacy, Data privacy, Get a copy of your data, and tick Connections.',
    'LinkedIn emails you a link; download Connections.csv.',
    'Copy the file to your phone and use Import, Spreadsheet in CardKeep. If the file starts with a few lines of notes before the column headings, delete those lines first. Connections come with a name, company and position, and sometimes an email.',
  ]),
];
