import 'content_model.dart';

/// The eight lessons of the tour (S15a.4), in teaching order. Each is also an
/// article in Help & tips.
const lessons = <HelpArticle>[
  HelpArticle(
    id: 'scan-one',
    title: 'Scan one card',
    summary: 'Point, hold still, check, save.',
    group: HelpGroup.scanning,
    art: Art.scanOne,
    lesson: true,
    steps: [
      LessonStep(
        'Open the scanner',
        'Tap Scan card on Contacts, or the + button then Scan a card. Allow the camera the first time. Choose One card at the top.',
      ),
      LessonStep(
        'Hold steady over the card',
        'A dark table works best. Fill most of the frame and keep the phone still. CardKeep outlines the card, takes the photo by itself and straightens it.',
      ),
      LessonStep(
        'Check what it read',
        'A sheet shows the name and company it found. Tap Use this card to see the whole form, Add the back side for a two-sided card, Adjust corners if the edges are wrong, or Retake.',
      ),
      LessonStep(
        'Save',
        'Fix anything that looks off (amber fields are the ones to check against the card), then Save. If the person is already in your contacts, CardKeep says so.',
      ),
    ],
    tip: 'Dim room? The torch icon at the top right lights the card. The round button takes the photo yourself.',
    tryLabel: 'Open the scanner',
    tryRoute: '/scan',
    coachId: 'scan',
    keywords: ['camera', 'photo', 'business card', 'capture', 'read', 'ocr'],
  ),
  HelpArticle(
    id: 'sweep',
    title: 'Sweep over many cards',
    summary: 'Lay them out, move the phone across, and each card is captured once.',
    group: HelpGroup.scanning,
    art: Art.sweep,
    lesson: true,
    steps: [
      LessonStep(
        'Lay the cards out',
        'Put them on a dark table with a small gap between each. About a dozen at a time works well.',
      ),
      LessonStep('Open Sweep', 'Tap + then Sweep across cards, or choose Sweep at the top of the scanner.'),
      LessonStep(
        'Move slowly, then hold',
        'Each card gets an orange outline when it is seen. Hold over it for a moment: an orange wipe means it is being read, a green tick with Done means it is captured. A card you already scanned shows Already in queue.',
      ),
      LessonStep(
        'Finish',
        'Tap Finish. If Save clear cards automatically is on, clear cards go straight to Contacts and the rest wait in the Review queue.',
      ),
    ],
    tip: 'Long-press the green counter to see the speed and, for each card still waiting, why.',
    tryLabel: 'Open Sweep',
    tryRoute: '/scan?mode=sweep',
    coachId: 'sweep',
    keywords: ['pile', 'batch', 'many', 'table', 'multiple', 'counter', 'done'],
  ),
  HelpArticle(
    id: 'review-queue',
    title: 'The Review queue',
    summary: 'Where cards CardKeep was not sure about wait for a quick look.',
    group: HelpGroup.scanning,
    art: Art.queue,
    lesson: true,
    steps: [
      LessonStep(
        'What lands here',
        'Cards that were not clear enough to save by themselves. The three numbers at the top are: saved automatically today, need a quick look, and still being read.',
      ),
      LessonStep(
        'Read the chips',
        'Low confidence: the reading may be wrong. Blurry: the photo is not sharp, so retake it. Small: the card is small in the photo. Glare: a reflection. No name found, No edges found and Cut off: part of the card is missing.',
      ),
      LessonStep(
        'Fix and save',
        'Open a card and compare it with the photo. Amber fields are the ones to check. Tap a block of text on the photo to say which field it belongs to, or use Read a region. Then Save, or Save and review next.',
      ),
      LessonStep(
        'Clean up',
        'Swipe a card left to remove it. The three-dot menu has Remove all, with an Undo that stays at the top until you use it.',
      ),
    ],
    tip: 'A card you retake or remove never reaches your contacts, so the queue is a safe place to be fussy.',
    tryLabel: 'Open the Review queue',
    tryRoute: '/queue',
    coachId: 'queue',
    keywords: ['chips', 'blurry', 'low confidence', 'amber', 'remove all', 'undo', 'saved automatically'],
  ),
  HelpArticle(
    id: 'person-or-place',
    title: 'Person or Place',
    summary: 'A person has a name and a job; a place is a shop, restaurant, vendor or service.',
    group: HelpGroup.organise,
    art: Art.personPlace,
    lesson: true,
    steps: [
      LessonStep(
        'Two kinds of card',
        'Most cards are people. Some belong to a business with nobody\'s name on them: a hardware store, a cafe, a supplier, a repair shop.',
      ),
      LessonStep(
        'CardKeep guesses',
        'A card with opening hours, a street address and no person\'s name is suggested as a Place. A card with a name and a job title stays a Person, even if it is for a shop.',
      ),
      LessonStep(
        'Switch if it guessed wrong',
        'At the top of the form choose Person or Place. A place has a business name, a category, opening hours, phone, website and address instead of first name, last name and job title.',
      ),
      LessonStep(
        'Your own categories',
        'Store, Restaurant, Vendor, Service and Other are built in. In Settings, Place categories lets you add, rename, reorder and delete your own. Tap a place\'s address to open it in Maps.',
      ),
    ],
    tryLabel: 'Start a new contact',
    tryRoute: '/contact/new',
    keywords: ['place', 'store', 'shop', 'restaurant', 'vendor', 'category', 'hours', 'maps'],
  ),
  HelpArticle(
    id: 'organise',
    title: 'Tags, events, follow-ups and duplicates',
    summary: 'Keep your contacts tidy and never lose track of who to call.',
    group: HelpGroup.organise,
    art: Art.organise,
    lesson: true,
    steps: [
      LessonStep(
        'Tags',
        'Open Tags from the menu to make your own groups (Customers, Suppliers) with colours. In Contacts, press and hold a contact to select several, then add a tag to all of them.',
      ),
      LessonStep(
        'Events and follow-ups',
        'Events remember where you met people: start a scan session and new cards are filed under it. Set a follow-up date on a contact and you get a reminder that morning. Follow-ups lists everything due.',
      ),
      LessonStep(
        'Duplicates',
        'Duplicates finds the same person twice. Compare and merge one pair, or tap Merge all obvious duplicates: you see a preview first, and Undo stays at the top until you use it. Not the same person remembers your answer.',
      ),
      LessonStep(
        'Company pages',
        'Tap a company name on a contact to see everyone there now and before, its places, where you met them and the shared phone numbers.',
      ),
    ],
    tip: 'Career moves suggests a job change when a new card or a bounced email shows someone moved.',
    tryLabel: 'Open Duplicates',
    tryRoute: '/duplicates',
    coachId: 'duplicates',
    keywords: ['tag', 'event', 'follow up', 'followup', 'reminder', 'merge', 'duplicate', 'company', 'career'],
  ),
  HelpArticle(
    id: 'import-export',
    title: 'Import, export, back up and restore',
    summary: 'Bring contacts in, take them out, and keep a safety copy.',
    group: HelpGroup.data,
    art: Art.importExport,
    lesson: true,
    steps: [
      LessonStep(
        'Import',
        'Open Import from the menu. A vCard file (.vcf) comes from any phone or Google Contacts; a spreadsheet (.csv) from Outlook, LinkedIn or Excel. You confirm which column is which, imported people are tagged Imported, and people you already have are matched rather than doubled.',
      ),
      LessonStep(
        'Export',
        'Export and backup shares everyone, or one tag, as vCard or spreadsheet. You choose whether to include notes and card photos.',
      ),
      LessonStep(
        'Back up',
        'Back up now saves one zip of everything, photos included. Switch on Weekly backup on this phone and the newest four are kept. Copy one off the phone now and then: if the phone is lost, a backup on the phone is lost with it.',
      ),
      LessonStep(
        'Restore',
        'Restore from a backup file checks the zip, then swaps it in when CardKeep restarts. Your previous data is kept as Data from before the last restore for 30 days, with Go back to it and Discard.',
      ),
    ],
    tryLabel: 'Open Export and backup',
    tryRoute: '/export',
    keywords: ['vcf', 'csv', 'google contacts', 'outlook', 'linkedin', 'zip', 'weekly', 'restore', 'backup'],
  ),
  HelpArticle(
    id: 'tap-cards',
    title: 'Tap cards (NFC)',
    summary: 'Receive a contact by holding your phone to an NFC business card.',
    group: HelpGroup.scanning,
    art: Art.nfc,
    lesson: true,
    steps: [
      LessonStep(
        'What it reads',
        'NFC business cards and tags such as Popl and Linq: a contact card, or a link to a web page.',
      ),
      LessonStep(
        'Tap',
        'Open + then Tap an NFC card and hold the back of your phone to the card. A contact card opens a form to Review and save. A link card lets you Open the page or Save link only.',
      ),
      LessonStep(
        'Not read',
        'Bank cards, door badges and anything that is not a business card are ignored. Nothing from them is shown or kept.',
      ),
      LessonStep(
        'NFC off or missing',
        'If NFC is off the screen says so, with a button to open your phone\'s settings; turn it on and it starts listening by itself. A phone without NFC simply has no Tap cards, and nothing else changes.',
      ),
    ],
    tryLabel: 'Open Tap cards',
    tryRoute: '/tap',
    keywords: ['nfc', 'tap', 'popl', 'linq', 'tag', 'link card'],
  ),
  HelpArticle(
    id: 'my-card',
    title: 'My card',
    summary: 'Your own details, ready to share with a QR code.',
    group: HelpGroup.organise,
    art: Art.myCard,
    lesson: true,
    steps: [
      LessonStep(
        'Add your details',
        'Open My card from the menu and tap Add my details: name, company, phones, email.',
      ),
      LessonStep(
        'Show the QR code',
        'The code holds your details. Someone points their camera at it and can add you. Tap the code to show it full screen.',
      ),
      LessonStep(
        'Share the file',
        'Share as contact file sends your details as a vCard by message, email or any app you choose.',
      ),
    ],
    tryLabel: 'Open My card',
    tryRoute: '/mycard',
    keywords: ['qr', 'share', 'my details', 'vcard', 'business card'],
  ),
];

/// Short answers (S15a.7). Not part of the tour; they live in Help & tips.
const faq = <HelpArticle>[
  HelpArticle(
    id: 'privacy-promise',
    title: 'What data leaves my phone?',
    summary: 'Almost nothing, and only when you ask.',
    group: HelpGroup.start,
    art: Art.privacy,
    steps: [
      LessonStep(
        'Never',
        'Contacts, notes, card photos, tags and your location are never uploaded. There is no account, no analytics and no crash-reporting service.',
      ),
      LessonStep(
        'Only if you switch it on',
        'Settings, Check when CardKeep opens: contacts CardKeep\'s releases on GitHub to see if a new version exists. It sends nothing about you.',
      ),
      LessonStep(
        'Only when you tap',
        'Links, maps, calls, texts, email and web checks open other apps, and what you share with them is up to those apps. Sharing or exporting a contact sends it where you choose.',
      ),
      LessonStep(
        'On the phone',
        'Reading text from a card runs on the phone with Google ML Kit models bundled in the app. Weekly backups stay on the phone, and Android cloud backup is off for CardKeep.',
      ),
    ],
    keywords: ['privacy', 'cloud', 'upload', 'analytics', 'internet', 'network', 'ml kit', 'google'],
  ),
  HelpArticle(
    id: 'blurry',
    title: 'Why is my card blurry or read wrongly?',
    summary: 'Light, steadiness and a plain background fix most of it.',
    group: HelpGroup.trouble,
    art: Art.scanOne,
    steps: [
      LessonStep(
        'Light and background',
        'Use even light and a plain dark table. Glossy cards: tilt the phone a little to lose the reflection. Dim room: switch the torch on.',
      ),
      LessonStep(
        'Hold still',
        'Wait for the outline, keep the phone steady for a second, and fill most of the frame with one card.',
      ),
      LessonStep(
        'Retake or adjust',
        'On the sheet after a scan, Retake takes it again and Adjust corners fixes a wrong cut-out. In the Review queue, Blurry means retake it.',
      ),
      LessonStep(
        'Fix a field',
        'Tap the text block on the photo and choose its field, or use Read a region. You can always edit the field by hand.',
      ),
    ],
    keywords: ['blurry', 'wrong', 'misread', 'glare', 'torch', 'flash', 'dark card', 'accuracy'],
  ),
  HelpArticle(
    id: 'chips',
    title: 'What do the chips and amber fields mean?',
    summary: 'The labels on a scanned card, one by one.',
    group: HelpGroup.trouble,
    art: Art.queue,
    steps: [
      LessonStep('Amber field', 'CardKeep was not sure of this one. Compare it with the photo.'),
      LessonStep(
        'Low confidence, Blurry, Small, Glare',
        'The reading may be wrong, the photo is not sharp, the card is small in the photo, or a reflection hides text.',
      ),
      LessonStep(
        'No name found',
        'Nobody\'s name was found. It may be a place (Person or Place), or you can tap the name on the photo.',
      ),
      LessonStep(
        'No edges found, Cut off',
        'The card\'s edges could not be seen or part of the card was outside the photo. Adjust corners or retake.',
      ),
    ],
    keywords: ['chips', 'amber', 'low confidence', 'small', 'glare', 'cut off', 'no edges'],
  ),
  HelpArticle(
    id: 'autosave',
    title: 'What does Save clear cards automatically do?',
    summary: 'Clear reads skip the queue; unsure ones wait.',
    group: HelpGroup.scanning,
    art: Art.queue,
    steps: [
      LessonStep(
        'When it applies',
        'In Batch, Pile and Sweep scanning, a card read with high confidence, with a believable name and a phone, email or website, goes straight to Contacts.',
      ),
      LessonStep(
        'What waits',
        'Everything else goes to the Review queue. Places always wait, because the check needs a person\'s name.',
      ),
      LessonStep(
        'Turn it off',
        'Settings, Save clear cards automatically. Then every scanned card waits for your quick look.',
      ),
    ],
    keywords: ['auto', 'automatic', 'save', 'queue', 'batch', 'pile', 'sweep'],
  ),
  HelpArticle(
    id: 'merge',
    title: 'How do I merge duplicates, and undo it?',
    summary: 'One pair at a time, or all the obvious ones at once.',
    group: HelpGroup.organise,
    art: Art.organise,
    steps: [
      LessonStep(
        'One pair',
        'Open Duplicates, tap Compare and merge, choose the best version of each field and confirm.',
      ),
      LessonStep(
        'All obvious ones',
        'Merge all obvious duplicates covers copies with the same name and the same email or phone at the same company. You see a preview before anything changes.',
      ),
      LessonStep(
        'Undo',
        'After a bulk merge, Undo stays at the top of Duplicates until you use it or merge again. Not the same person tells CardKeep to stop suggesting a pair.',
      ),
    ],
    keywords: ['merge', 'duplicate', 'undo', 'obvious', 'same person'],
  ),
  HelpArticle(
    id: 'backups',
    title: 'How do backups work?',
    summary: 'A zip of everything, kept on the phone, plus the one you copy off.',
    group: HelpGroup.data,
    art: Art.backup,
    steps: [
      LessonStep(
        'What is in one',
        'Every contact, place, tag, event and follow-up, and the card photos and logos in use. Deleted contacts are not included.',
      ),
      LessonStep(
        'Weekly',
        'Turn on Weekly backup on this phone in Export and backup. When you open CardKeep and a week has passed, it makes one and keeps the newest four.',
      ),
      LessonStep(
        'The part only you can do',
        'Copy a backup to a computer or cloud drive you trust now and then. If the phone is lost or broken, backups on it are lost too.',
      ),
      LessonStep('Back up now', 'Makes a backup straight away and lets you choose where to save the file.'),
    ],
    keywords: ['backup', 'weekly', 'zip', 'safety', 'copy', 'lost phone'],
  ),
  HelpArticle(
    id: 'new-phone',
    title: 'How do I move to a new phone?',
    summary: 'Back up, copy the file, install, restore.',
    group: HelpGroup.data,
    art: Art.backup,
    steps: [
      LessonStep(
        'On the old phone',
        'Export and backup, Back up now, and save the zip somewhere you can reach from the new phone (a cloud drive, or copy it to a computer).',
      ),
      LessonStep(
        'On the new phone',
        'Install CardKeep from its GitHub releases page, open it, and you can skip the tour.',
      ),
      LessonStep(
        'Restore',
        'Export and backup, Restore from a backup file, pick the zip, and confirm. CardKeep restarts with everything back.',
      ),
    ],
    keywords: ['new phone', 'transfer', 'switch', 'move', 'restore', 'upgrade phone'],
  ),
  HelpArticle(
    id: 'delete',
    title: 'How do I delete a contact for good?',
    summary: 'Delete, and it is wiped after seven days.',
    group: HelpGroup.data,
    art: Art.keeps,
    steps: [
      LessonStep('Delete', 'Open the contact, three-dot menu, Delete. You get an Undo right away.'),
      LessonStep(
        'After seven days',
        'CardKeep wipes the contact\'s details, notes and card photos for good. In the meantime the contact is hidden everywhere and left out of backups.',
      ),
      LessonStep('Everything', 'Removing CardKeep from the phone removes all of its data.'),
    ],
    keywords: ['delete', 'remove', 'wipe', 'erase', 'purge', 'undo'],
  ),
  HelpArticle(
    id: 'camera-denied',
    title: 'The camera will not open',
    summary: 'Allow it in Android settings, or import photos instead.',
    group: HelpGroup.trouble,
    art: Art.camera,
    steps: [
      LessonStep('Allow the camera', 'Phone Settings, Apps, CardKeep, Permissions, Camera, Allow while using the app.'),
      LessonStep('Another app using it', 'Close other apps that may be using the camera, then reopen the scanner.'),
      LessonStep('Work without it', 'Import card photos, from the + menu, reads cards from pictures in your gallery.'),
    ],
    keywords: ['camera', 'permission', 'denied', 'blocked', 'black screen'],
  ),
  HelpArticle(
    id: 'reminders',
    title: 'Why did I not get a reminder?',
    summary: 'Check the permission, the date, and battery saving.',
    group: HelpGroup.trouble,
    art: Art.bell,
    steps: [
      LessonStep('Notifications allowed?', 'Phone Settings, Apps, CardKeep, Notifications must be on.'),
      LessonStep(
        'A date in the future',
        'A follow-up reminds you on the chosen day. If you set today, you are reminded about a minute later.',
      ),
      LessonStep(
        'Battery saving',
        'Some phones stop apps from waking up. In the phone\'s battery settings, let CardKeep run unrestricted.',
      ),
    ],
    keywords: ['reminder', 'notification', 'follow up', 'alarm', 'battery'],
  ),
  HelpArticle(
    id: 'updates',
    title: 'How do I update CardKeep?',
    summary: 'From Settings, using CardKeep\'s releases on GitHub.',
    group: HelpGroup.data,
    art: Art.help,
    steps: [
      LessonStep('Check', 'Settings, Check for updates looks at the newest release on GitHub and shows what is new.'),
      LessonStep('Install', 'If there is a newer version, Download and install. Your contacts stay as they are.'),
      LessonStep(
        'Automatically?',
        'Switch on Check when CardKeep opens if you want it to look each time. It is off by default.',
      ),
    ],
    keywords: ['update', 'upgrade', 'version', 'github', 'release', 'install'],
  ),
];

/// Everything in Help & tips: lessons first, then answers.
const helpArticles = <HelpArticle>[...lessons, ...faq];
